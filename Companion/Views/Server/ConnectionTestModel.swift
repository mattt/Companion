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

    func test(_ server: Server, perform: @escaping @MainActor (Server) async throws -> Void) {
        testTask?.cancel()
        status = .testing
        errorMessage = nil

        testTask = Task { [weak self] in
            do {
                try await perform(server)
                guard !Task.isCancelled else { return }
                self?.status = .success
                self?.errorMessage = nil
            } catch is CancellationError {
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
