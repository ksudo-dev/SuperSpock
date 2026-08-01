# SuperSpock

"SuperSpock" is the current codename for a native macOS GLKVM client for the GL.iNet Comet RM1. The name may change before a first release. The app is built around a Screen Sharing-style window rather than an embedded browser.

> **Status: work in progress.** The app builds, runs, authenticates, and receives
> a native WebRTC video track from a live RM1. The probe recorded an offer, ICE
> connected, and the video track attached. Input is not wired to the video
> surface yet, so this is a working draft, not a finished tool.
>
> If you want a native GLKVM client that already works today, use
> [rcawston/Overlook](https://github.com/rcawston/Overlook). It has working
> input, OCR capture, and device discovery that this project does not.

## Links

- Field note: https://sudo-dev.com/superspock-kvm-client
- Sudo-Dev: https://sudo-dev.com

## Open in Xcode

Open `Package.swift`, select the `SuperSpock` scheme, and Run. The app targets macOS 15 or later.

## Build a normal macOS app

Run `zsh Scripts/build-app.sh`. The signed application is written to `build/SuperSpock.app` and can be launched from Finder or copied to `~/Applications`.

## Security

The RM1 password and TOTP seed are stored in `~/Library/Application Support/SuperSpock/credentials.vault` with owner-only permissions and complete file protection. TLS uses the system trust store; do not import a Tailscale certificate into the app.

## Current protocol boundary

The native window, settings, secure credential storage, TOTP generation, connection lifecycle, and PiKVM-style HID WebSocket client are implemented. GL.iNet has varied authentication and streaming payloads between firmware releases. `KVMClient.authenticate()` intentionally isolates the small firmware-specific payload that must be verified against RM1 firmware 1.9.2 before relying on unattended login.

Video is a real native WebRTC client (`JanusWebRTCManager.swift`, via the `stasel/WebRTC` package), not an embedded browser. On current RM1 firmware it speaks GL.iNet's Pion signaling gateway directly at `wss://<host>/pion/ws?auth_token=<token>`. The client sends a configuration message, receives a base64-wrapped offer, answers it, exchanges ICE candidates, and attaches the remote video track. The older `/janus/ws` path returns HTTP 502 on this firmware. The Pion flow was reverse-engineered from the RM1's shipped frontend and verified against live hardware with the headless probe.

## What is not done

- **Input is not wired to the video surface.** `KVMClient` implements the HID
  WebSocket calls, and Pion's config handshake requests a dedicated `hid`
  data channel alongside the video track, but nothing forwards mouse and
  keyboard events from the rendered view into either path yet.
- **Unattended login is unverified.** GL.iNet has varied authentication and
  streaming payloads between firmware releases, so
  `KVMClient.authenticate()` deliberately isolates the small firmware-specific
  payload that needs checking against RM1 firmware 1.9.2.
- No OCR clipboard capture, device discovery, or menu bar agent.
