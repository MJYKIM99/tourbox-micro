import Foundation
import Network
import TourBoxCore

final class TourBoxServer: @unchecked Sendable {
    typealias EventHandler = @MainActor @Sendable (TourBoxEvent) -> Void
    typealias ConnectionHandler = @MainActor @Sendable (Bool, String?) -> Void

    private static let maximumCandidates = 4
    private static let candidateTimeout: TimeInterval = 5
    private static let maximumCandidateBytes = 2_048

    private let queue = DispatchQueue(label: "com.yi.tourboxmicro.tourbox-server", qos: .userInteractive)
    private let onEvent: EventHandler
    private let onConnection: ConnectionHandler
    private var listener: NWListener?
    private var connection: NWConnection?
    private var candidates: [ObjectIdentifier: CandidateBuffer] = [:]

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
        queue.sync {
            connection?.cancel()
            candidates.values.forEach { $0.connection.cancel() }
            listener?.cancel()
            connection = nil
            candidates.removeAll()
            listener = nil
        }
    }

    private func accept(_ candidate: NWConnection) {
        guard candidates.count < Self.maximumCandidates else {
            candidate.cancel()
            return
        }
        let identifier = ObjectIdentifier(candidate)
        let buffer = CandidateBuffer(connection: candidate)
        candidates[identifier] = buffer
        candidate.stateUpdateHandler = { [weak self, weak candidate] state in
            guard let self, let candidate else { return }
            switch state {
            case .ready:
                if self.connection == nil {
                    self.promote(candidate, firstEvent: nil)
                } else {
                    self.receiveCandidate(buffer)
                    self.queue.asyncAfter(deadline: .now() + Self.candidateTimeout) { [weak self, weak candidate] in
                        guard let self, let candidate,
                              self.candidates.removeValue(forKey: identifier) != nil else { return }
                        candidate.cancel()
                    }
                }
            case .failed, .cancelled:
                self.candidates.removeValue(forKey: identifier)
                if self.connection === candidate {
                    self.connection = nil
                    let errorDescription: String?
                    if case .failed(let error) = state {
                        errorDescription = error.localizedDescription
                    } else {
                        errorDescription = nil
                    }
                    Task { @MainActor in self.onConnection(false, errorDescription) }
                }
            default:
                break
            }
        }
        candidate.start(queue: queue)
    }

    private func receiveCandidate(_ candidate: CandidateBuffer) {
        candidate.connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self, weak candidate] data, _, isComplete, error in
            guard let self, let candidate else { return }
            let identifier = ObjectIdentifier(candidate.connection)
            guard self.candidates[identifier] != nil else { return }
            if let data {
                candidate.byteCount += data.count
                if let event = TourBoxProtocolDecoder.decode(data) {
                    self.promote(candidate.connection, firstEvent: event)
                    return
                }
            }
            if error != nil || isComplete || candidate.byteCount > Self.maximumCandidateBytes {
                self.candidates.removeValue(forKey: identifier)
                candidate.connection.cancel()
                return
            }
            self.receiveCandidate(candidate)
        }
    }

    private func promote(_ candidate: NWConnection, firstEvent: TourBoxEvent?) {
        let identifier = ObjectIdentifier(candidate)
        candidates.removeValue(forKey: identifier)
        let previous = connection
        connection = candidate
        previous?.cancel()
        Task { @MainActor in
            self.onConnection(true, nil)
            if let firstEvent { self.onEvent(firstEvent) }
        }
        receive(from: candidate)
    }

    private func receive(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection, self.connection === connection else { return }
            if let data, let event = TourBoxProtocolDecoder.decode(data) {
                Task { @MainActor in self.onEvent(event) }
            }
            if let error {
                self.disconnect(connection, error: error.localizedDescription)
                return
            }
            if isComplete {
                self.disconnect(connection, error: nil)
                return
            }
            self.receive(from: connection)
        }
    }

    private func disconnect(_ connection: NWConnection, error: String?) {
        guard self.connection === connection else { return }
        self.connection = nil
        connection.cancel()
        Task { @MainActor in self.onConnection(false, error) }
    }
}

private final class CandidateBuffer: @unchecked Sendable {
    let connection: NWConnection
    var byteCount = 0

    init(connection: NWConnection) {
        self.connection = connection
    }
}
