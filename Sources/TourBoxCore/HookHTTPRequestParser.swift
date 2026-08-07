import Foundation

public struct HookHTTPRequest: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public enum HookHTTPRequestParseResult: Equatable, Sendable {
    case incomplete
    case request(HookHTTPRequest)
    case failure(status: Int)
}

public enum HookHTTPRequestParser {
    public static let maximumHeaderBytes = 8_192
    public static let maximumBodyBytes = 65_536
    public static let maximumRequestBytes = maximumHeaderBytes + 4 + maximumBodyBytes

    public static func parse(_ data: Data) -> HookHTTPRequestParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else {
            return data.count > maximumHeaderBytes ? .failure(status: 431) : .incomplete
        }
        guard headerRange.lowerBound <= maximumHeaderBytes else { return .failure(status: 431) }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .failure(status: 400)
        }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestParts = (lines.first ?? "").split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3,
              requestParts[2] == "HTTP/1.1" || requestParts[2] == "HTTP/1.0" else {
            return .failure(status: 400)
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { return .failure(status: 400) }
            let name = pair[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else { return .failure(status: 400) }
            headers[name] = value
        }

        guard let lengthText = headers["content-length"],
              let contentLength = Int(lengthText),
              contentLength >= 0 else {
            return .failure(status: 400)
        }
        guard contentLength <= maximumBodyBytes else { return .failure(status: 413) }
        guard headers["content-type"]?.lowercased().hasPrefix("application/json") == true else {
            return .failure(status: 415)
        }

        let bodyStart = headerRange.upperBound
        let requestLength = bodyStart + contentLength
        guard requestLength <= maximumRequestBytes else { return .failure(status: 413) }
        guard data.count >= requestLength else { return .incomplete }
        guard data.count == requestLength else { return .failure(status: 400) }

        return .request(
            HookHTTPRequest(
                method: String(requestParts[0]),
                path: String(requestParts[1]),
                headers: headers,
                body: data.subdata(in: bodyStart..<requestLength)
            )
        )
    }
}
