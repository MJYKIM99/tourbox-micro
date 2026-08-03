import Foundation
import Network
import TourBoxCore

final class HookServer: @unchecked Sendable {
    typealias SignalHandler = @MainActor @Sendable (HookSignal) -> Void
    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private let queue = DispatchQueue(label: "com.yi.tourboxmicro.hook-server", qos: .utility)
    private let onSignal: SignalHandler
    private let onError: ErrorHandler
    private var listener: NWListener?

    init(onSignal: @escaping SignalHandler, onError: @escaping ErrorHandler) {
        self.onSignal = onSignal
        self.onError = onError
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 50501)!
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .failed(let error) = state else { return }
            Task { @MainActor in self.onError(error.localizedDescription) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func serve(_ connection: NWConnection) {
        let request = HTTPRequestBuffer()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(request, from: connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(_ request: HTTPRequestBuffer, from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let data { request.data.append(data) }

            if let parsed = request.parseIfComplete() {
                self.handle(parsed, connection: connection)
                return
            }
            if error != nil || isComplete {
                self.respond(status: 400, body: #"{"error":"invalid request"}"#, on: connection)
                return
            }
            self.receive(request, from: connection)
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        let eventName = request.path.split(separator: "/").last.map(String.init)
        guard request.method == "POST",
              request.path.hasPrefix("/tourbox-hook/"),
              let eventName,
              let event = CodexHookEvent(rawValue: eventName),
              let payload = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] else {
            respond(status: 400, body: #"{"error":"unsupported hook"}"#, on: connection)
            return
        }

        let signal = HookClassifier.classify(event: event, payload: payload)
        Task { @MainActor in self.onSignal(signal) }
        respond(status: 200, body: "{}", on: connection)
    }

    private func respond(status: Int, body: String, on connection: NWConnection) {
        let reason = status == 200 ? "OK" : "Bad Request"
        let bodyData = Data(body.utf8)
        let headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private final class HTTPRequestBuffer: @unchecked Sendable {
    var data = Data()

    func parseIfComplete() -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator) else { return nil }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestParts = (lines.first ?? "").split(separator: " ")
        guard requestParts.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1).map(String.init)
            if pair.count == 2, pair[0].caseInsensitiveCompare("Content-Length") == .orderedSame {
                contentLength = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return HTTPRequest(method: String(requestParts[0]), path: String(requestParts[1]), body: body)
    }
}

private struct HTTPRequest: Sendable {
    let method: String
    let path: String
    let body: Data
}
