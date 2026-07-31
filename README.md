# SuperSpock

Native macOS GLKVM client for the GL.iNet Comet RM1, designed around a Screen Sharing-style window rather than an embedded browser.

> **Status: work in progress.** It builds, runs, authenticates, and the native
> WebRTC video path is fully implemented — but an end-to-end video session has
> not been confirmed against real hardware yet. Treat it as a working draft,
> not a finished tool.
>
> If you want a native GLKVM client that already works today, use
> [rcawston/Overlook](https://github.com/rcawston/Overlook) — it is further
> along and it is what taught me the protocol.

## Open in Xcode

Open `Package.swift`, select the `SuperSpock` scheme, and Run. The app targets macOS 15 or later.

## Build a normal macOS app

Run `zsh Scripts/build-app.sh`. The signed application is written to `build/SuperSpock.app` and can be launched from Finder or copied to `~/Applications`.

## Security

The RM1 password and TOTP seed are stored in `~/Library/Application Support/SuperSpock/credentials.vault` with owner-only permissions and complete file protection. TLS uses the system trust store; do not import a Tailscale certificate into the app.

## Current protocol boundary

The native window, settings, secure credential storage, TOTP generation, connection lifecycle, and PiKVM-style HID WebSocket client are implemented. GL.iNet has varied authentication and streaming payloads between firmware releases. `KVMClient.authenticate()` intentionally isolates the small firmware-specific payload that must be verified against RM1 firmware 1.9.2 before relying on unattended login.

Video is a real native WebRTC client (`JanusWebRTCManager.swift`, via the `stasel/WebRTC` package), not an embedded browser. It speaks GLKVM's actual Janus signaling protocol directly: `wss://<host>/janus/ws` with `Sec-WebSocket-Protocol: janus-protocol`, session create → attach `janus.plugin.ustreamer` → `watch` → jsep offer/answer → trickle ICE → 25s keepalive, with TURN credentials pulled from `/api/turn/get_turn`. This protocol was confirmed by reading another open-source GLKVM client (rcawston/Overlook, GPLv3 — same license as this project) and independently verified against a live RM1: the auth, TURN, and Janus endpoints are all present and gated by the same auth cookie.

## What is not done

- **An end-to-end video session has not been confirmed.** The signaling
  endpoints are verified real and the client implements the full negotiation,
  but no frame has been observed rendering from actual hardware yet.
- **Unattended login is unverified.** GL.iNet has varied authentication and
  streaming payloads between firmware releases, so
  `KVMClient.authenticate()` deliberately isolates the small firmware-specific
  payload that needs checking against RM1 firmware 1.9.2.
- **Input is not wired to the video surface.** `KVMClient` implements the HID
  WebSocket calls, but nothing forwards mouse and keyboard events from the
  rendered view to them yet.
- No OCR clipboard capture, device discovery, or menu bar agent.
