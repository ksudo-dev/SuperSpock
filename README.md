# SuperSpock

Native macOS GLKVM client for the GL.iNet Comet RM1, designed around a Screen Sharing-style window rather than an embedded browser.

## Open in Xcode

Open `Package.swift`, select the `SuperSpock` scheme, and Run. The app targets macOS 15 or later.

## Build a normal macOS app

Run `zsh Scripts/build-app.sh`. The signed application is written to `build/SuperSpock.app` and can be launched from Finder or copied to `~/Applications`.

## Security

The RM1 password and TOTP seed are stored in `~/Library/Application Support/SuperSpock/credentials.vault` with owner-only permissions and complete file protection. TLS uses the system trust store; do not import a Tailscale certificate into the app.

## Current protocol boundary

The native window, settings, secure credential storage, TOTP generation, connection lifecycle, and PiKVM-style HID WebSocket client are implemented. GL.iNet has varied authentication and streaming payloads between firmware releases. `KVMClient.authenticate()` intentionally isolates the small firmware-specific payload that must be verified against RM1 firmware 1.9.2 before relying on unattended login.

Video is now a real native WebRTC client (`JanusWebRTCManager.swift`, via the `stasel/WebRTC` package), not an embedded browser. It speaks GLKVM's actual Janus signaling protocol directly: `wss://<host>/janus/ws` with `Sec-WebSocket-Protocol: janus-protocol`, session create → attach `janus.plugin.ustreamer` → `watch` → jsep offer/answer → trickle ICE → 25s keepalive, with TURN credentials pulled from `/api/turn/get_turn`. This protocol was confirmed by reading another open-source GLKVM client (rcawston/Overlook, GPLv3 — same license as this project) and independently verified live against `your-glkvm-device.local` (auth, turn, and Janus endpoints all present and gated by the same auth cookie).

**Not yet verified: whether this actually compiles and streams a frame.** This was written and reasoned through carefully, matching a known-working implementation's exact API calls, but it has not been built in Xcode or run against the real RM1 — this environment only has Command Line Tools' Swift 6.1, and this package needs Swift 6.2. Build it in Xcode next; expect to debug real compile errors together.
