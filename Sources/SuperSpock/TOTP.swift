import Foundation
import CryptoKit

enum TOTP {
    static func secret(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["otpauth", "apple-otpauth"].contains(url.scheme?.lowercased() ?? ""),
           let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name.lowercased() == "secret" })?.value {
            return normalizedSecret(value)
        }
        return normalizedSecret(trimmed)
    }

    private static func normalizedSecret(_ input: String) -> String? {
        let normalized = input.uppercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "=" }
        guard normalized.count >= 16, normalized.allSatisfy({ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".contains($0) }) else { return nil }
        return normalized
    }

    static func code(secret: String, date: Date = Date(), digits: Int = 6, period: TimeInterval = 30) -> String? {
        guard let normalized = self.secret(from: secret), let keyData = Base32.decode(normalized) else { return nil }
        var counter = UInt64(date.timeIntervalSince1970 / period).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let hash = HMAC<Insecure.SHA1>.authenticationCode(for: message, using: SymmetricKey(data: keyData))
        let bytes = Array(hash)
        let offset = Int(bytes.last! & 0x0f)
        let value = (UInt32(bytes[offset] & 0x7f) << 24) | (UInt32(bytes[offset+1]) << 16) | (UInt32(bytes[offset+2]) << 8) | UInt32(bytes[offset+3])
        return String(format: "%0*u", digits, value % UInt32(pow(10.0, Double(digits))))
    }
}

enum Base32 {
    static func decode(_ value: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        let map = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })
        var buffer = 0, bits = 0; var output = Data()
        for char in value.uppercased().filter({ !$0.isWhitespace && $0 != "-" && $0 != "=" }) {
            guard let part = map[char] else { return nil }
            buffer = (buffer << 5) | part; bits += 5
            if bits >= 8 { bits -= 8; output.append(UInt8((buffer >> bits) & 0xff)) }
        }
        return output.isEmpty ? nil : output
    }
}
