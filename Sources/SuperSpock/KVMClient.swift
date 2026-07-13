import Foundation

actor KVMClient {
    private var baseURL: URL?
    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var authToken: String?

    func connect(to endpoint: String) async throws -> String {
        guard let url = URL(string: endpoint), url.scheme == "https" else { throw ClientError.invalidEndpoint }
        baseURL = url
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        let session = URLSession(configuration: config)
        self.session = session

        var request = URLRequest(url: url.appendingPathComponent("api/auth/check"))
        request.httpMethod = "GET"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        if http.statusCode == 401 || http.statusCode == 403 { try await authenticate() }
        else if !(200..<400).contains(http.statusCode) { throw ClientError.http(http.statusCode) }
        try await openWebSocket()
        guard let authToken else { throw ClientError.invalidAuthenticationResponse }
        return authToken
    }

    private func authenticate() async throws {
        guard let baseURL, let session else { throw ClientError.notConfigured }
        guard let credentials = try CredentialVault.read(), !credentials.password.isEmpty else { throw ClientError.credentialsRequired }
        let password = credentials.password
        let otp = TOTP.code(secret: credentials.totpSecret) ?? ""
        // GLKVM firmware revisions have used PiKVM-compatible and GL-specific login fields.
        // Keep the payload isolated here so live protocol discovery changes one small surface.
        // RM1 firmware 1.9.2 concatenates password + six-digit TOTP and posts
        // application/x-www-form-urlencoded. This intentionally differs from
        // upstream PiKVM and is verified against the device's shipped frontend.
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "user", value: "admin"),
            URLQueryItem(name: "passwd", value: password + otp)
        ]
        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let safeCategory = Self.safeErrorCategory(from: data)
            throw ClientError.authenticationRejected(status: http.statusCode, category: safeCategory)
        }
        guard let token = Self.findToken(in: data) else { throw ClientError.invalidAuthenticationResponse }
        authToken = token
        if let cookie = HTTPCookie(properties: [
            .domain: baseURL.host ?? "",
            .path: "/",
            .name: "auth_token",
            .value: token,
            .secure: "TRUE"
        ]) { session.configuration.httpCookieStorage?.setCookie(cookie) }
    }

    private func openWebSocket() async throws {
        guard let baseURL, let session else { throw ClientError.notConfigured }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/ws"), resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        if let authToken { components.queryItems = [URLQueryItem(name: "auth_token", value: authToken)] }
        let socket = session.webSocketTask(with: components.url!)
        socket.resume(); webSocket = socket
    }

    func sendKeySequence(_ keys: [String]) async throws {
        guard let webSocket else { throw ClientError.notConnected }
        for key in keys { try await send(["event_type": "key", "event": ["key": key, "state": true]], on: webSocket) }
        for key in keys.reversed() { try await send(["event_type": "key", "event": ["key": key, "state": false]], on: webSocket) }
    }

    func sendPointer(x: Double, y: Double) async throws {
        guard let webSocket else { throw ClientError.notConnected }
        try await send(["event_type": "mouse_move", "event": ["to": [Int(x), Int(y)]]], on: webSocket)
    }

    private func send(_ object: [String: Any], on socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        try await socket.send(.data(data))
    }

    private static func findToken(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        func search(_ value: Any) -> String? {
            if let dictionary = value as? [String: Any] {
                if let token = dictionary["token"] as? String { return token }
                for nested in dictionary.values { if let token = search(nested) { return token } }
            } else if let array = value as? [Any] {
                for nested in array { if let token = search(nested) { return token } }
            }
            return nil
        }
        return search(object)
    }

    private static func safeErrorCategory(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return "empty response" }
        let lower = text.lowercased()
        if lower.contains("too") && lower.contains("attempt") { return "rate limited" }
        if lower.contains("two") || lower.contains("2fa") || lower.contains("otp") { return "2FA rejected" }
        if lower.contains("password") || lower.contains("passwd") { return "password rejected" }
        if lower.contains("forbidden") { return "forbidden" }
        return "unrecognized response"
    }

    func disconnect() { webSocket?.cancel(with: .normalClosure, reason: nil); webSocket = nil; session?.invalidateAndCancel(); session = nil; authToken = nil }
}

enum ClientError: LocalizedError {
    case invalidEndpoint, invalidResponse, notConfigured, notConnected, credentialsRequired, authenticationFailed, authenticationRejected(status: Int, category: String), invalidAuthenticationResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Enter a valid HTTPS GLKVM address."
        case .invalidResponse: "The device returned an invalid response."
        case .notConfigured: "The connection is not configured."
        case .notConnected: "Connect to the device first."
        case .credentialsRequired: "Save the admin password in Settings first."
        case .authenticationFailed: "GLKVM rejected the saved password or verification code."
        case .authenticationRejected(let status, let category): "GLKVM login failed (HTTP \(status), \(category))."
        case .invalidAuthenticationResponse: "GLKVM logged in but returned an unrecognized token response."
        case .http(let code): "GLKVM returned HTTP \(code)."
        }
    }
}
