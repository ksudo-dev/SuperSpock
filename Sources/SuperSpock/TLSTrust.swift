import Foundation

/// Accepts the server's TLS certificate without validating it against the
/// system trust store, when the user has explicitly opted in.
///
/// GLKVM devices present two very different certificates depending on how you
/// reach them:
///
/// - Over a Tailscale `*.ts.net` name, Tailscale provisions a real Let's
///   Encrypt certificate whose subject matches the hostname. This validates
///   normally and needs no override.
/// - Over a LAN address — an IP, or the device's `.local` mDNS name — the
///   device serves its own self-signed certificate issued for `CN=localhost`.
///   That can never validate against the system trust store, no matter what,
///   because it does not match the name being requested and no public CA
///   signed it.
///
/// So this exists for the LAN case. It is off by default: an unvalidated TLS
/// connection cannot prove the box answering is actually your KVM, which
/// matters because this app sends an admin password over it. Prefer the
/// Tailscale name when you can.
final class TLSTrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let allowInsecure: Bool

    init(allowInsecure: Bool) {
        self.allowInsecure = allowInsecure
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowInsecure,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
