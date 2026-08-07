import Foundation
import Testing
@testable import TourBoxCore

@Test func hookRequestParserHandlesPartialAuthenticatedJSONRequest() throws {
    let token = String(repeating: "a", count: 64)
    let body = Data(#"{"thread_id":"thread-1"}"#.utf8)
    let header = "POST /tourbox-hook/Stop HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nX-TourBox-Token: \(token)\r\n\r\n"
    var request = Data(header.utf8)
    request.append(body)

    #expect(HookHTTPRequestParser.parse(request.prefix(request.count - 1)) == .incomplete)
    let parsed = try #require(requestValue(HookHTTPRequestParser.parse(request)))
    #expect(parsed.method == "POST")
    #expect(parsed.path == "/tourbox-hook/Stop")
    #expect(parsed.body == body)
    #expect(HookAuthentication.securelyMatches(
        parsed.headers[HookAuthentication.normalizedHeaderName],
        expected: token
    ))
}

@Test func hookRequestParserRejectsOversizedOrMalformedRequests() {
    let oversizedHeader = Data(("POST / HTTP/1.1\r\nX-Fill: " + String(repeating: "a", count: 8_300)).utf8)
    #expect(HookHTTPRequestParser.parse(oversizedHeader) == .failure(status: 431))

    let oversizedBody = Data("POST / HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: 70000\r\n\r\n".utf8)
    #expect(HookHTTPRequestParser.parse(oversizedBody) == .failure(status: 413))

    let wrongType = Data("POST / HTTP/1.1\r\nContent-Type: text/plain\r\nContent-Length: 0\r\n\r\n".utf8)
    #expect(HookHTTPRequestParser.parse(wrongType) == .failure(status: 415))
}

@Test func hookAuthenticationCreatesPrivateTokenAndRejectsMismatch() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("tourbox-hook-token-tests-\(UUID().uuidString)")
    let url = directory.appendingPathComponent("hook-token")
    defer { try? FileManager.default.removeItem(at: directory) }

    let token = try HookAuthentication.loadOrCreateToken(at: url)
    #expect(token.count == 64)
    #expect(try HookAuthentication.loadToken(at: url) == token)
    #expect(HookAuthentication.securelyMatches(token, expected: token))
    #expect(!HookAuthentication.securelyMatches(nil, expected: token))
    #expect(!HookAuthentication.securelyMatches(token + "a", expected: token))
    let permissions = try #require(
        FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
    )
    #expect(permissions.intValue & 0o777 == 0o600)
}

private func requestValue(_ result: HookHTTPRequestParseResult) -> HookHTTPRequest? {
    guard case .request(let request) = result else { return nil }
    return request
}
