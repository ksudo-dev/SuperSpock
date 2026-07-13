# SuperSpock

Native macOS GLKVM client for the GL.iNet Comet RM1, designed around a Screen Sharing-style window rather than an embedded browser.

## Open in Xcode

Open `Package.swift`, select the `SuperSpock` scheme, and Run. The app targets macOS 15 or later.

## Build a normal macOS app

Run `zsh Scripts/build-app.sh`. The signed application is written to `build/SuperSpock.app` and can be launched from Finder or copied to `~/Applications`.

## Security

The RM1 password and TOTP seed are stored in `~/Library/Application Support/SuperSpock/credentials.vault` with owner-only permissions and complete file protection. TLS uses the system trust store; do not import a Tailscale certificate into the app.

## Current protocol boundary

The native window, settings, secure credential storage, TOTP generation, connection lifecycle, and PiKVM-style HID WebSocket client are implemented. GL.iNet has varied authentication and streaming payloads between firmware releases. `KVMClient.authenticate()` intentionally isolates the small firmware-specific payload that must be verified against RM1 firmware 1.9.2 before relying on unattended login. The renderer is ready to receive decoded frames; direct H.264 demux/decode must be matched to the live RM1 stream endpoint.
