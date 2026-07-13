import Foundation

enum CredentialVault {
    struct Credentials: Codable {
        let password: String
        let totpSecret: String
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SuperSpock", isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent("credentials.vault") }

    static func save(password: String, totpSecret: String) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var directory = directoryURL
        try? directory.setResourceValues(values)

        let data = try JSONEncoder().encode(Credentials(password: password, totpSecret: totpSecret))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func read() throws -> Credentials? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600 else {
            throw VaultError.unsafePermissions
        }
        return try JSONDecoder().decode(Credentials.self, from: Data(contentsOf: fileURL))
    }

    static var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
}

enum VaultError: LocalizedError {
    case unsafePermissions
    var errorDescription: String? { "The credentials vault has unsafe permissions and was not opened." }
}
