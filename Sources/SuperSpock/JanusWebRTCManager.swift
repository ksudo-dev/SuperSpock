import Foundation
import WebRTC

/// Native WebRTC client for GLKVM's **Pion** signaling gateway.
///
/// Current RM1 firmware serves video through GL.iNet's own Pion gateway at
/// `wss://<host>/pion/ws`, NOT the Janus `/janus/ws` path older clients use —
/// on this device `/janus/ws` returns HTTP 502 while `/pion/ws` upgrades
/// cleanly (101). Protocol reverse-engineered from the RM1's own shipped
/// frontend JS bundle, verified live.
///
/// Pion flow:
/// 1. open `wss://<host>/pion/ws?auth_token=<token>`
/// 2. send `{"type":"config","video":true,"hid":true,...}`
/// 3. receive `{"type":"offer","sdp":<base64(JSON({type,sdp}))>}`
/// 4. answer, then exchange `{"type":"candidate",...}` both directions and
///    `{"type":"client-ice-complete"}` when local gathering finishes
///
/// Hard-won specifics, do not remove casually:
/// - The auth token goes in the query string, not a cookie — browsers can't
///   set cookies on WebSockets, so the device gates on `?auth_token=`.
/// - SDP is wrapped as base64-encoded JSON `{type,sdp}`, not a raw string.
/// - With `sdpSemantics = .unifiedPlan`, remote tracks arrive via
///   `didAdd rtpReceiver:streams:`, NOT `didAdd stream:`.
/// - The offer only appears once the device has an HDMI signal to stream; no
///   signal means no offer (and the REST snapshot 503s).
@MainActor
@Observable
final class JanusWebRTCManager: NSObject {
    var videoView: RTCMTLNSVideoView?
    var connectionState: JanusConnectionState = .idle
    var lastError: String?
    var receivedVideoTrack = false
    var iceState = "new"

    /// Step-by-step signaling log, surfaced into AppModel.diagnosticEvents.
    @ObservationIgnored var onEvent: (@MainActor (String) -> Void)?

    @ObservationIgnored private var factory: RTCPeerConnectionFactory?
    @ObservationIgnored private var peerConnection: RTCPeerConnection?
    @ObservationIgnored private var webSocketTask: URLSessionWebSocketTask?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var socketDelegate: JanusSocketDelegate?

    @ObservationIgnored private var receiveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingCandidates: [RTCIceCandidate] = []
    @ObservationIgnored private var hasRemoteDescription = false

    private func log(_ message: String) {
        onEvent?("pion: \(message)")
    }

    func connect(host: String, authToken: String, turnCredentials: TurnCredentials?, allowInsecureTLS: Bool = false) async {
        disconnect()
        connectionState = .connecting
        receivedVideoTrack = false

        let videoView = RTCMTLNSVideoView(frame: .zero)
        self.videoView = videoView

        let factory = Self.makeFactory()
        self.factory = factory

        let configuration = RTCConfiguration()
        var iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        // The RM1 can return TURN credentials with an empty uris array (it
        // does over Tailscale, where no relay is needed). RTCIceServer throws
        // an NSException on an empty list, so only add it when populated.
        if let turnCredentials, !turnCredentials.uris.isEmpty {
            iceServers.append(RTCIceServer(
                urlStrings: turnCredentials.uris,
                username: turnCredentials.username,
                credential: turnCredentials.password
            ))
            log("TURN configured (\(turnCredentials.uris.count) uris)")
        } else {
            log("no usable TURN credentials — STUN only")
        }
        configuration.iceServers = iceServers
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["OfferToReceiveVideo": "true"])
        let connection = factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
        peerConnection = connection

        do {
            try openSignaling(host: host, authToken: authToken, allowInsecureTLS: allowInsecureTLS)
            connectionState = .connected
            log("signaling open — sent config, waiting for offer")
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            log("FAILED: \(lastError ?? "unknown")")
            connectionState = .failed
        }
    }

    func disconnect() {
        receiveTask?.cancel(); receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil); webSocketTask = nil
        session?.invalidateAndCancel(); session = nil
        socketDelegate = nil
        peerConnection?.close(); peerConnection = nil
        pendingCandidates.removeAll()
        hasRemoteDescription = false
        videoView = nil
        receivedVideoTrack = false
        connectionState = .idle
    }

    // MARK: - Signaling (Pion)

    private func openSignaling(host: String, authToken: String, allowInsecureTLS: Bool) throws {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = "/pion/ws"
        // Token goes in the query string — browsers (and thus GLKVM's own
        // frontend) can't set cookies on a WebSocket, so the device gates
        // here. Verified against the shipped JS bundle.
        components.queryItems = [URLQueryItem(name: "auth_token", value: authToken)]
        guard let url = components.url else { throw JanusError.invalidEndpoint }

        // Same trust policy as the HTTP API: a self-signed LAN cert fails the
        // upgrade too, silently, and looks like "no video" rather than TLS.
        let socketDelegate = JanusSocketDelegate(allowInsecure: allowInsecureTLS)
        socketDelegate.onOpen = { [weak self] _ in
            Task { @MainActor in self?.log("websocket open") }
        }
        socketDelegate.onClose = { [weak self] code in
            Task { @MainActor in self?.log("websocket closed (code \(code))") }
        }
        socketDelegate.onHTTPFailure = { [weak self] status in
            Task { @MainActor in
                self?.log("websocket upgrade rejected: HTTP \(status)")
                self?.lastError = "The device rejected the video connection (HTTP \(status))."
                self?.connectionState = .failed
            }
        }
        self.socketDelegate = socketDelegate

        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["Origin": "https://\(host)"]
        let session = URLSession(configuration: config, delegate: socketDelegate, delegateQueue: nil)
        self.session = session

        log("opening \(url.absoluteString)")
        let task = session.webSocketTask(with: url)
        task.resume()
        webSocketTask = task

        receiveTask = Task { [weak self] in await self?.listen() }

        // Pion waits for the client to declare what it wants before sending an
        // offer. hid:true also gets us the negotiated input datachannel.
        log("sending config (video, hid)")
        Task {
            try? await sendJSON([
                "type": "config", "video": true, "speaker": false, "mic": false, "hid": true,
                "flexfecLevel": 0, "orientation": 0, "camera": false
            ])
        }
    }

    private func listen() async {
        guard let webSocketTask else { return }
        while true {
            do {
                let message = try await webSocketTask.receive()
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        await handle(object)
                    }
                case .data(let data):
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        await handle(object)
                    }
                @unknown default: break
                }
            } catch {
                log("receive failed: \(error.localizedDescription)")
                if connectionState == .connecting || connectionState == .connected {
                    lastError = "Signaling connection lost: \(error.localizedDescription)"
                    connectionState = .failed
                }
                return
            }
        }
    }

    private func handle(_ message: [String: Any]) async {
        guard let type = message["type"] as? String, let peerConnection else { return }

        switch type {
        case "offer":
            // Pion base64-encodes JSON {type,sdp} rather than sending raw SDP.
            guard let encoded = message["sdp"] as? String,
                  let decoded = Data(base64Encoded: encoded),
                  let jsep = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any],
                  let sdp = jsep["sdp"] as? String else {
                log("offer: could not decode base64 jsep"); return
            }
            log("offer received (\(sdp.count) bytes sdp) — answering")
            do {
                try await peerConnection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
                hasRemoteDescription = true
                for candidate in pendingCandidates { try? await peerConnection.add(candidate) }
                pendingCandidates.removeAll()

                let answer = try await peerConnection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
                try await peerConnection.setLocalDescription(answer)
                guard let local = peerConnection.localDescription else { return }
                let payload = try JSONSerialization.data(withJSONObject: ["type": "answer", "sdp": local.sdp])
                try await sendJSON(["type": "answer", "sdp": payload.base64EncodedString()])
                log("answer sent — ICE connecting")
            } catch {
                lastError = "Failed to negotiate video: \(error.localizedDescription)"
                log("negotiation error: \(error.localizedDescription)")
                connectionState = .failed
            }

        case "candidate":
            guard let candidateString = message["candidate"] as? String else { return }
            let mLineIndex = Int32((message["sdpMLineIndex"] as? Int) ?? 0)
            let candidate = RTCIceCandidate(sdp: candidateString, sdpMLineIndex: mLineIndex, sdpMid: message["sdpMid"] as? String)
            if hasRemoteDescription {
                try? await peerConnection.add(candidate)
            } else {
                pendingCandidates.append(candidate)
            }

        case "server-ice-complete":
            log("server ICE complete")

        default:
            log("unhandled message: \(type)")
        }
    }

    private func sendJSON(_ object: [String: Any]) async throws {
        guard let webSocketTask else { throw JanusError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { throw JanusError.notConnected }
        try await webSocketTask.send(.string(text))
    }

    private static func makeFactory() -> RTCPeerConnectionFactory {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }
}

extension JanusWebRTCManager: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        let sdp = candidate.sdp
        let sdpMid = candidate.sdpMid ?? "0"
        let sdpMLineIndex = Int(candidate.sdpMLineIndex)
        Task { @MainActor in
            try? await sendJSON([
                "type": "candidate", "candidate": sdp, "sdpMid": sdpMid, "sdpMLineIndex": sdpMLineIndex
            ])
        }
    }

    private struct TrackBox: @unchecked Sendable { let track: RTCVideoTrack? }

    /// Unified Plan delivers remote tracks here. `didAdd stream:` below is
    /// kept only as a legacy fallback — on this device it never fires with
    /// a video track while this one does.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams: [RTCMediaStream]) {
        let box = TrackBox(track: rtpReceiver.track as? RTCVideoTrack)
        Task { @MainActor in
            guard let track = box.track else { return }
            log("video track received via rtpReceiver")
            receivedVideoTrack = true
            if let videoView { track.add(videoView) }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let box = TrackBox(track: stream.videoTracks.first)
        Task { @MainActor in
            guard let track = box.track else { return }
            log("video track received via legacy stream callback")
            receivedVideoTrack = true
            if let videoView { track.add(videoView) }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let name: String = switch newState {
        case .new: "new"; case .checking: "checking"; case .connected: "connected"
        case .completed: "completed"; case .failed: "failed"; case .disconnected: "disconnected"
        case .closed: "closed"; case .count: "count"; @unknown default: "unknown"
        }
        Task { @MainActor in
            iceState = name
            log("ICE \(name)")
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        guard newState == .complete else { return }
        Task { @MainActor in
            log("local ICE gathering complete")
            try? await sendJSON(["type": "client-ice-complete"])
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

/// Extends the shared trust delegate with WebSocket lifecycle callbacks so
/// the signaling log can show definitively whether the upgrade succeeded.
final class JanusSocketDelegate: TLSTrustDelegate, URLSessionWebSocketDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    var onOpen: ((String?) -> Void)?
    var onClose: ((Int) -> Void)?
    var onHTTPFailure: ((Int) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen?(`protocol`)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onClose?(closeCode.rawValue)
    }

    // When the upgrade is rejected outright, the only place the HTTP status
    // is visible is the completed task's response.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error != nil, let http = task.response as? HTTPURLResponse {
            onHTTPFailure?(http.statusCode)
        }
    }
}

enum JanusConnectionState { case idle, connecting, connected, failed }

enum JanusError: LocalizedError {
    case invalidEndpoint, notConnected
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Could not build the GLKVM signaling URL."
        case .notConnected: "Not connected to the GLKVM signaling channel."
        }
    }
}

struct TurnCredentials: Decodable {
    let password: String
    let ttl: Int
    let uris: [String]
    let username: String
}
