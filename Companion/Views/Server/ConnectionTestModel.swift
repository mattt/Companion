import Foundation

/// State for the "Test Connection" action in the add and edit server sheets.
@MainActor
@Observable
final class ConnectionTestModel {
    enum Status: Equatable {
        case idle
        case testing
        case success
        case failed
        case cancelled
    }

    private(set) var status: Status = .idle
    private(set) var errorMessage: String?

    private var testTask: Task<Void, Never>?

    var isTesting: Bool { status == .testing }
    var hasSucceeded: Bool { status == .success }

    func test(
        name: String, configuration: Server.Configuration, settings: ServerConnectionSettings,
        using store: ServerStore
    ) {
        let server = Server(id: UUID().uuidString, name: name, configuration: configuration)
        testTask?.cancel()
        status = .testing
        errorMessage = nil

        testTask = Task { [weak self] in
            do {
                try await store.testConnection(server, settings: settings)
                guard !Task.isCancelled else { return }
                self?.status = .success
                self?.errorMessage = nil
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                self?.status = .cancelled
                self?.errorMessage = "Test cancelled"
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed
                self?.errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        testTask?.cancel()
        testTask = nil
        status = .cancelled
        errorMessage = "Test cancelled"
    }

    func reset() {
        testTask?.cancel()
        testTask = nil
        status = .idle
        errorMessage = nil
    }
}
