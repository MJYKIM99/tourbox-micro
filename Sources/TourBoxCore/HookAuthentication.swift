import Darwin
import Foundation

public enum HookAuthentication {
    public static let headerName = "X-TourBox-Token"
    public static let normalizedHeaderName = headerName.lowercased()

    public static var defaultTokenURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TourBox Micro", isDirectory: true)
            .appendingPathComponent("hook-token")
    }

    public static func loadOrCreateToken(at url: URL = defaultTokenURL) throws -> String {
        if let token = try? loadToken(at: url) { return token }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let token = (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        let bytes = Array((token + "\n").utf8)
        let descriptor = Darwin.open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { return try loadToken(at: url) }
            throw HookAuthenticationError.unableToCreateToken
        }
        var succeeded = false
        defer {
            Darwin.close(descriptor)
            if !succeeded { try? fileManager.removeItem(at: url) }
        }
        let written = bytes.withUnsafeBytes { buffer in
            Darwin.write(descriptor, buffer.baseAddress, buffer.count)
        }
        guard written == bytes.count, Darwin.fsync(descriptor) == 0 else {
            throw HookAuthenticationError.unableToCreateToken
        }
        succeeded = true
        return token
    }

    public static func loadToken(at url: URL = defaultTokenURL) throws -> String {
        let token = try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.count == 64, token.allSatisfy(\.isHexDigit) else {
            throw HookAuthenticationError.invalidTokenFile(url)
        }
        return token
    }

    public static func securelyMatches(_ candidate: String?, expected: String) -> Bool {
        guard let candidate else { return false }
        let lhs = Array(candidate.utf8)
        let rhs = Array(expected.utf8)
        var difference = lhs.count ^ rhs.count
        let count = max(lhs.count, rhs.count)
        for index in 0..<count {
            difference |= Int((index < lhs.count ? lhs[index] : 0) ^ (index < rhs.count ? rhs[index] : 0))
        }
        return difference == 0
    }
}

public enum HookAuthenticationError: LocalizedError {
    case invalidTokenFile(URL)
    case unableToCreateToken

    public var errorDescription: String? {
        switch self {
        case .invalidTokenFile:
            "The TourBox Micro hook token is invalid."
        case .unableToCreateToken:
            "The TourBox Micro hook token could not be created."
        }
    }
}
