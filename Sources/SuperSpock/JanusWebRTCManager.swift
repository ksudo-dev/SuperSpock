import Foundation
import WebRTC

/// Native Janus signaling + WebRTC client for GLKVM's video/audio plugin.
///
/// Protocol confirmed by reading GLKVM's own web frontend behavior and
/// cross-checked against another open-source GLKVM client (rcawston/Overlook,
/// GPLv3 — same license as this project), then verified live against
/// your-glkvm-device.local: `wss://<host>/janus/ws` with `Sec-WebSocket-Protocol:
/// janus-protocol`, session create -> attach `janus.plugin.ustreamer` ->
/// "watch" -> jsep offer/answer -> trickle ICE -> 25s keepalive.
@MainActor
final class JanusWebRTCManager: NSObject, ObservableObject {
    @Published var videoView: RTCMTLNSVideoView?
    @Published var connectionState: JanusConnectionState = .idle
    @Published var lastError: String?

    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?

    private var sessionId: Int?
    private var handleId: Int?
    private var keepAliveTask: Task<Void, Never>?
    private var receiveTask: Task<Void, Never>?
    private var waiters: [String: CheckedContinuation<JanusMessageBox, Error>] = [:]

    /// JSONSerialization output and WebRTC objects aren't Sendable, but every
    /// use here stays MainActor-confined (and libwebrtc proxies its objects to
    /// an internal thread), so boxing them across the hop is safe.
    struct JanusMessageBox: @unchecked Sendable { let value: [String: Any] }

    func connect(host: String, authToken: String, turnCredentials: TurnCredentials?) async {
        disconnect()
        connectionState = .connecting

        let videoView = RTCMTLNSVideoView(frame: .zero)
        self.videoView = videoView

        let factory = Self.makeFactory()
        self.factory = factory

        let configuration = RTCConfiguration()
        var iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        if let turnCredentials {
            iceServers.append(RTCIceServer(
                urlStrings: turnCredentials.uris,
                username: turnCredentials.username,
                credential: turnCredentials.password
            ))
        }
        configuration.iceServers = iceServers
        configuration.sdpSemantics = .unifiedPlan

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["OfferToReceiveVideo": "true"])
        let connection = factory.peerConnection(with: configuration, constraints: constraints, delegate: self)
        peerConnection = connection

        do {
            try await connectSignaling(host: host, authToken: authToken)
            connectionState = .connected
        } catch {
            lastError = String(describing: error)
            connectionState = .failed
        }
    }

    func disconnect() {
        keepAliveTask?.cancel(); keepAliveTask = nil
        receiveTask?.cancel(); receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil); webSocketTask = nil
        session?.invalidateAndCancel(); session = nil
        peerConnection?.close(); peerConnection = nil
        for waiter in waiters.values { waiter.resume(throwing: JanusError.cancelled) }
        waiters.removeAll()
        sessionId = nil; handleId = nil
        videoView = nil
        connectionState = .idle
    }

    // MARK: - Signaling

    private func connectSignaling(host: String, authToken: String) async throws {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = "/janus/ws"
        guard let url = components.url else { throw JanusError.invalidEndpoint }

        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue("janus-protocol", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        request.setValue("auth_token=\(authToken)", forHTTPHeaderField: "Cookie")

        let task = session.webSocketTask(with: request)
        task.resume()
        webSocketTask = task

        receiveTask = Task { [weak self] in await self?.listen() }

        let createTransaction = Self.makeTransaction()
        let createResponse = try await send(["janus": "create", "transaction": createTransaction], awaiting: createTransaction)
        guard let data = createResponse["data"] as? [String: Any], let sessionId = data["id"] as? Int else {
            throw JanusError.unexpectedResponse
        }
        self.sessionId = sessionId

        let attachTransaction = Self.makeTransaction()
        let attachResponse = try await send([
            "janus": "attach",
            "plugin": "janus.plugin.ustreamer",
            "opaque_id": "superspock-\(UUID().uuidString)",
            "transaction": attachTransaction,
            "session_id": sessionId
        ], awaiting: attachTransaction)
        guard let attachData = attachResponse["data"] as? [String: Any], let handleId = attachData["id"] as? Int else {
            throw JanusError.unexpectedResponse
        }
        self.handleId = handleId

        let watchTransaction = Self.makeTransaction()
        try await sendFireAndForget([
            "janus": "message",
            "body": ["request": "watch", "params": ["orientation": 0, "audio": false, "video": true, "mic": false, "camera": false]],
            "transaction": watchTransaction,
            "session_id": sessionId,
            "handle_id": handleId
        ])

        startKeepAlive()
    }

    private func startKeepAlive() {
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self, let sessionId = await self.sessionId else { return }
                try? await self.sendFireAndForget(["janus": "keepalive", "session_id": sessionId, "transaction": Self.makeTransaction()])
            }
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
                connectionState = .failed
                lastError = "Signaling connection lost"
                return
            }
        }
    }

    private func handle(_ message: [String: Any]) async {
        if let transaction = message["transaction"] as? String, let waiter = waiters.removeValue(forKey: transaction) {
            waiter.resume(returning: JanusMessageBox(value: message))
            return
        }
        guard let type = message["janus"] as? String else { return }

        if type == "trickle" {
            guard let candidateObject = message["candidate"] as? [String: Any],
                  let candidateString = candidateObject["candidate"] as? String,
                  (candidateObject["completed"] as? Bool) != true,
                  let peerConnection else { return }
            let mLineIndex = Int32((candidateObject["sdpMLineIndex"] as? Int) ?? 0)
            let candidate = RTCIceCandidate(sdp: candidateString, sdpMLineIndex: mLineIndex, sdpMid: candidateObject["sdpMid"] as? String)
            try? await peerConnection.add(candidate)
            return
        }

        guard type == "event",
              let jsep = message["jsep"] as? [String: Any],
              jsep["type"] as? String == "offer",
              let sdp = jsep["sdp"] as? String,
              let peerConnection, let handleId, let sessionId else { return }

        do {
            try await peerConnection.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
            let answer = try await peerConnection.answer(for: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
            try await peerConnection.setLocalDescription(answer)
            guard let local = peerConnection.localDescription else { return }
            try await sendFireAndForget([
                "janus": "message",
                "body": ["request": "start"],
                "transaction": Self.makeTransaction(),
                "session_id": sessionId,
                "handle_id": handleId,
                "jsep": ["type": "answer", "sdp": local.sdp]
            ])
        } catch {
            lastError = "Failed to negotiate video: \(error)"
        }
    }

    private func send(_ object: [String: Any], awaiting transaction: String) async throws -> [String: Any] {
        let box: JanusMessageBox = try await withCheckedThrowingContinuation { continuation in
            waiters[transaction] = continuation
            Task { try? await self.sendFireAndForget(object) }
        }
        return box.value
    }

    private func sendFireAndForget(_ object: [String: Any]) async throws {
        guard let webSocketTask else { throw JanusError.notConnected }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else { throw JanusError.notConnected }
        try await webSocketTask.send(.string(text))
    }

    private static func makeTransaction() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }

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
            guard let sessionId, let handleId else { return }
            try? await sendFireAndForget([
                "janus": "trickle",
                "candidate": ["candidate": sdp, "sdpMid": sdpMid, "sdpMLineIndex": sdpMLineIndex],
                "transaction": Self.makeTransaction(),
                "session_id": sessionId,
                "handle_id": handleId
            ])
        }
    }

    private struct TrackBox: @unchecked Sendable { let track: RTCVideoTrack? }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        let box = TrackBox(track: stream.videoTracks.first)
        Task { @MainActor in
            guard let track = box.track, let videoView else { return }
            track.add(videoView)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

enum JanusConnectionState { case idle, connecting, connected, failed }

enum JanusError: LocalizedError {
    case invalidEndpoint, notConnected, unexpectedResponse, cancelled
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Could not build the Janus signaling URL."
        case .notConnected: "Not connected to the GLKVM signaling channel."
        case .unexpectedResponse: "GLKVM's Janus signaling returned an unexpected response."
        case .cancelled: "The connection was cancelled."
        }
    }
}

struct TurnCredentials: Decodable {
    let password: String
    let ttl: Int
    let uris: [String]
    let username: String
}
