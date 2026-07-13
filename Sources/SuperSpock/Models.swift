import Foundation
import SwiftUI

enum ConnectionState: Equatable { case disconnected, connecting, authenticating, authenticated, connected, reconnecting, failed(String) }
enum ScaleMode: String, CaseIterable, Identifiable, Codable { case fit = "Fit", actual = "Actual Pixels", fill = "Fill"; var id: Self { self } }
enum QualityProfile: String, CaseIterable, Identifiable, Codable { case responsive = "Responsive", balanced = "Balanced", pristine = "Pristine", custom = "Custom"; var id: Self { self } }

struct KVMDevice: Codable, Hashable, Identifiable {
    var id = UUID()
    var name = "SuperSpock"
    var endpoint = "https://superspock.example-tailnet.ts.net"
}

struct SessionMetrics: Equatable {
    var resolution = "—"
    var framesPerSecond = 0
    var bitrateMbps = 0.0
    var latencyMs = 0
    var codec = "H.264"
}

@Observable @MainActor
final class AppModel {
    var device: KVMDevice
    var state: ConnectionState = .disconnected
    var scaleMode: ScaleMode = .fit
    var quality: QualityProfile = .pristine
    var showInspector = true
    var showSettings = false
    var hasSavedPassword = CredentialVault.exists
    var showStats = false
    var captureKeyboard = true
    var capturePointer = true
    var showLocalCursor = false
    var clipboardSync = true
    var audioEnabled = true
    var microphoneEnabled = false
    var microphoneMuted = true
    var volume = 0.75
    var reconnectAutomatically = true
    var metrics = SessionMetrics()
    var frame: CGImage?
    var mediaToken: String?
    var statusMessage = "Ready"
    var diagnosticEvents: [String] = []
    var selectedInspectorTab = InspectorTab.session
    let client = KVMClient()

    init() {
        if let data = UserDefaults.standard.data(forKey: "device"), let saved = try? JSONDecoder().decode(KVMDevice.self, from: data) { device = saved }
        else { device = KVMDevice() }
    }

    func saveDevice() {
        if let data = try? JSONEncoder().encode(device) { UserDefaults.standard.set(data, forKey: "device") }
    }

    func connect() {
        guard state != .connecting && state != .connected && state != .authenticated else { return }
        Task {
            diagnosticEvents.removeAll()
            record("Connection requested for \(device.endpoint)")
            state = .connecting; statusMessage = "Contacting \(device.name)…"
            do {
                state = .authenticating
                record("TLS trust and GLKVM authentication started")
                mediaToken = try await client.connect(to: device.endpoint)
                state = .connected
                statusMessage = "Connected — loading GLKVM media transport"
                metrics = .init()
                record("GLKVM token received")
                record("Authenticated GLKVM WebRTC media surface started")
            } catch {
                state = .failed(error.localizedDescription); statusMessage = error.localizedDescription; record("Failure: \(error.localizedDescription)")
            }
        }
    }


    func disconnect() { Task { await client.disconnect() }; mediaToken = nil; state = .disconnected; statusMessage = "Disconnected"; metrics = .init() }
    func sendControlAltDelete() { Task { try? await client.sendKeySequence(["ControlLeft", "AltLeft", "Delete"]) } }

    func record(_ event: String) {
        diagnosticEvents.append("\(Date.now.formatted(date: .omitted, time: .standard))  \(event)")
    }

    var diagnosticSummary: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let stateText: String = switch state {
        case .disconnected: "disconnected"; case .connecting: "connecting"; case .authenticating: "authenticating"
        case .authenticated: "authenticated (no media stream)"; case .connected: "streaming"; case .reconnecting: "reconnecting"
        case .failed(let message): "failed: \(message)"
        }
        return """
        SuperSpock diagnostics
        App version: \(version)
        Endpoint: \(device.endpoint)
        State: \(stateText)
        Status: \(statusMessage)
        TLS: system trust evaluation required
        Authentication: \(state == .authenticated || state == .connected ? "succeeded" : "not confirmed")
        Media surface: \(mediaToken == nil ? "not running" : "authenticated GLKVM WebRTC")
        Video transport: WebRTC/Janus in isolated WebKit media surface
        Audio transport: GLKVM WebRTC
        Control transport: GLKVM WebSocket/WebRTC data path

        Event log:
        \(diagnosticEvents.isEmpty ? "No events recorded" : diagnosticEvents.joined(separator: "\n"))
        """
    }
}

enum InspectorTab: String, CaseIterable, Identifiable { case session = "Session", audio = "Audio", display = "Display", input = "Input", diagnostics = "Stats"; var id: Self { self } }
