import SwiftUI
import WebRTC

/// Wraps the Metal-backed WebRTC video view so the real decoded remote frames
/// render directly — no embedded browser, no scraping the DOM for stats.
struct NativeVideoView: NSViewRepresentable {
    let videoView: RTCMTLNSVideoView
    let scaleMode: ScaleMode

    func makeNSView(context: Context) -> RTCMTLNSVideoView {
        videoView
    }

    // stasel/WebRTC's RTCMTLNSVideoView has no public content-mode property
    // (confirmed against Overlook's usage, which also never sets one) — the
    // Metal layer fills its bounds, so fit/fill is handled by the SwiftUI
    // layout wrapping this view, not here.
    func updateNSView(_ nsView: RTCMTLNSVideoView, context: Context) {}
}
