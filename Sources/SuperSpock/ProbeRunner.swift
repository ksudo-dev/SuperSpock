import Foundation

/// Headless diagnostic: authenticates with the saved vault credentials, runs
/// the complete Pion/WebRTC negotiation, and prints every signaling step.
/// Exits 0 once a video track arrives and ICE connects; nonzero otherwise.
///
///     .build/debug/SuperSpock --probe https://<device-hostname> [--insecure]
enum ProbeRunner {
    static func run(endpoint: String, allowInsecureTLS: Bool) {
        guard endpoint.hasPrefix("https://") else {
            print("usage: SuperSpock --probe https://<device-hostname> [--insecure]")
            exit(64)
        }
        print("probe: \(endpoint) (insecure TLS: \(allowInsecureTLS))")

        Task { @MainActor in
            let client = KVMClient()
            let manager = JanusWebRTCManager()
            manager.onEvent = { print("  \($0)") }

            do {
                print("  auth: connecting…")
                let token = try await client.connect(to: endpoint, allowInsecureTLS: allowInsecureTLS)
                print("  auth: OK (token \(token.count) chars)")

                let turn = try? await client.fetchTurnCredentials()
                guard let host = await client.currentHost() else {
                    print("  FAIL: no host after connect"); exit(70)
                }

                await manager.connect(host: host, authToken: token, turnCredentials: turn, allowInsecureTLS: allowInsecureTLS)
                if manager.connectionState == .failed {
                    print("  FAIL: \(manager.lastError ?? "signaling failed")"); exit(69)
                }

                // Signaling is done; the offer, ICE, and first track arrive
                // asynchronously. Poll up to 30s for proof of life.
                for second in 1...30 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if manager.receivedVideoTrack && (manager.iceState == "connected" || manager.iceState == "completed") {
                        print("  SUCCESS after \(second)s: video track attached, ICE \(manager.iceState)")
                        exit(0)
                    }
                    if manager.connectionState == .failed {
                        print("  FAIL: \(manager.lastError ?? "unknown")"); exit(69)
                    }
                }
                print("  TIMEOUT after 30s — track: \(manager.receivedVideoTrack), ICE: \(manager.iceState)")
                exit(75)
            } catch {
                print("  FAIL: \((error as? LocalizedError)?.errorDescription ?? String(describing: error))")
                exit(69)
            }
        }
        RunLoop.main.run()
    }
}
