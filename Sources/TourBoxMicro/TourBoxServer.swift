import Foundation
import Network
import TourBoxCore

final class TourBoxServer: @unchecked Sendable {
    typealias EventHandler = @MainActor @Sendable (TourBoxEvent) -> Void
    typealias ConnectionHandler = @MainActor @Sendable (Bool, String?) -> Void

    private let queue = DispatchQueue(label: "com.yi.tourboxmicro.tourbox-server", qos: .userInteractive)
    private let onEvent: EventHandler
    private let onConnection: ConnectionHandler
    private var listener: NWListener?
    private var connection: NWConnection?

    init(onEvent: @escaping EventHandler, onConnection: @escaping ConnectionHandler) {
        self.onEvent = onEvent
        self.onConnection = onConnection
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 50500)!
        )
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let error):
                Task { @MainActor in self.onConnection(false, error.localizedDescription) }
            case .cancelled:
                Task { @MainActor in self.onConnection(false, nil) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    func stop() {
        connection?.cancel()
        listener?.cancel()
        connection = nil
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        self.connection?.cancel()
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self else { return }
            switch state {
            case .ready:
                Task { @MainActor in self.onConnection(true, nil) }
                if let connection { self.receive(from: connection) }
            case .failed(let error):
                Task { @MainActor in self.onConnection(false, error.localizedDescription) }
            case .cancelled:
                Task { @MainActor in self.onConnection(false, nil) }
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self, weak connection] data, _, isComplete, error in
            guard let self else { return }
            if let data, let event = TourBoxProtocolDecoder.decode(data) {
                Task { @MainActor in self.onEvent(event) }
            }
            if let error {
                Task { @MainActor in self.onConnection(false, error.localizedDescription) }
                connection?.cancel()
                return
            }
            if isComplete {
                Task { @MainActor in self.onConnection(false, nil) }
                connection?.cancel()
                return
            }
            if let connection { self.receive(from: connection) }
        }
    }
}
