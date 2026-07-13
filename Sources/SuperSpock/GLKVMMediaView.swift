import SwiftUI
import WebKit

struct GLKVMMediaView: NSViewRepresentable {
    let endpoint: URL
    let authToken: String
    let scaleMode: ScaleMode
    let onMetrics: @MainActor (String, Double) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onMetrics: onMetrics) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false

        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "superspockMetrics")
        controller.addUserScript(WKUserScript(source: bootstrapScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        controller.addUserScript(WKUserScript(source: polishScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        configuration.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        view.customUserAgent = "SuperSpock/0.4 GLKVM-native-shell"

        let cookie = HTTPCookie(properties: [
            .domain: endpoint.host ?? "",
            .path: "/",
            .name: "auth_token",
            .value: authToken,
            .secure: "TRUE",
            .sameSitePolicy: "None"
        ])!
        configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
            var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
            components.fragment = "/"
            view.load(URLRequest(url: components.url!))
        }
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let mode = scaleMode == .fill ? "cover" : scaleMode == .actual ? "none" : "contain"
        view.evaluateJavaScript("document.documentElement.style.setProperty('--superspock-fit','\(mode)')")
    }

    private var bootstrapScript: String {
        let encoded = authToken
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        return """
        localStorage.setItem('gl-kvm-token-key', '\(encoded)');
        document.cookie = 'auth_token=\(encoded); path=/; Secure; SameSite=None';
        """
    }

    private var polishScript: String {
        #"""
        (() => {
          const style = document.createElement('style');
          style.textContent = `
            html, body, #app { margin:0!important; width:100%!important; height:100%!important; overflow:hidden!important; background:#000!important; }
            video, canvas { object-fit:var(--superspock-fit, contain)!important; }
            ::-webkit-scrollbar { display:none!important; }
          `;
          document.head.appendChild(style);
          document.documentElement.style.setProperty('--superspock-fit', 'contain');
          var last = '';
          setInterval(() => {
            const text = document.body ? document.body.innerText : '';
            const match = text.match(/WebRTC\s+H\.264\s*-\s*(\d+)x(\d+)\s*\/\s*(\d+)\s*kbps/i);
            if (match) {
              const signature = match.slice(1).join(':');
              if (signature !== last) {
                last = signature;
                window.webkit.messageHandlers.superspockMetrics.postMessage({
                  resolution: `${match[1]}×${match[2]}`,
                  bitrateKbps: Number(match[3])
                });
              }
            }
          }, 1000);
        })();
        """#
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onMetrics: @MainActor (String, Double) -> Void
        init(onMetrics: @escaping @MainActor (String, Double) -> Void) { self.onMetrics = onMetrics }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "superspockMetrics", let values = message.body as? [String: Any],
                  let resolution = values["resolution"] as? String,
                  let bitrate = values["bitrateKbps"] as? Double else { return }
            Task { @MainActor in onMetrics(resolution, bitrate / 1000) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if navigationAction.targetFrame?.isMainFrame == true,
               let sourceHost = webView.url?.host,
               let targetHost = navigationAction.request.url?.host,
               sourceHost != targetHost {
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }
}
