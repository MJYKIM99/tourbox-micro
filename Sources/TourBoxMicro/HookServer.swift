import Foundation
import Network
import TourBoxCore

final class HookServer: @unchecked Sendable {
    typealias SignalHandler = @MainActor @Sendable (HookSignal) -> Void
    typealias ErrorHandler = @MainActor @Sendable (String) -> Void

    private static let maximumConnections = 8
    private static let requestTimeout: TimeInterval = 3

    private let queue = DispatchQueue(label: "com.yi.tourboxmicro.hook-server", qos: .utility)
    private let authenticationToken: String
    private let onSignal: SignalHandler
    private let onError: ErrorHandler
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]

    init(
        authenticationToken: String,
        onSignal: @escaping SignalHandler,
        onError: @escaping ErrorHandler
    ) {
        self.authenticationToken = authenticationToken
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
        queue.sync {
            listener?.cancel()
            listener = nil
            activeConnections.values.forEach { $0.cancel() }
            activeConnections.removeAll()
        }
    }

    private func serve(_ connection: NWConnection) {
        guard activeConnections.count < Self.maximumConnections else {
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection
        let request = RequestBuffer()
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receive(request, from: connection)
                self.queue.asyncAfter(deadline: .now() + Self.requestTimeout) { [weak self, weak connection] in
                    guard let self, let connection,
                          self.activeConnections[identifier] != nil else { return }
                    self.respond(status: 408, body: #"{"error":"request timeout"}"#, on: connection)
                }
            case .failed, .cancelled:
                self.activeConnections.removeValue(forKey: identifier)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(_ request: RequestBuffer, from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let data { request.data.append(data) }

            switch HookHTTPRequestParser.parse(request.data) {
            case .request(let parsed):
                self.handle(parsed, connection: connection)
                return
            case .failure(let status):
                self.respond(status: status, body: #"{"error":"invalid request"}"#, on: connection)
                return
            case .incomplete:
                break
            }

            if error != nil || isComplete {
                self.respond(status: 400, body: #"{"error":"incomplete request"}"#, on: connection)
                return
            }
            self.receive(request, from: connection)
        }
    }

    private func handle(_ request: HookHTTPRequest, connection: NWConnection) {
        guard HookAuthentication.securelyMatches(
            request.headers[HookAuthentication.normalizedHeaderName],
            expected: authenticationToken
        ) else {
            respond(status: 401, body: #"{"error":"unauthorized"}"#, on: connection)
            return
        }

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
        let reason = switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 408: "Request Timeout"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 431: "Request Header Fields Too Large"
        default: "Error"
        }
        let bodyData = Data(body.utf8)
        let headers = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var response = Data(headers.utf8)
        response.append(bodyData)
        let identifier = ObjectIdentifier(connection)
        connection.send(content: response, completion: .contentProcessed { [weak self, weak connection] _ in
            guard let self else { return }
            self.activeConnections.removeValue(forKey: identifier)
            connection?.cancel()
        })
    }
}

private final class RequestBuffer: @unchecked Sendable {
    var data = Data()
}
