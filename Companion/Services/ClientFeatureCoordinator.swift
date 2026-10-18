import Foundation
import MCP
import os

/// Handles server-to-client MCP requests: roots, sampling, and elicitation.
///
/// `MCPServerConnections` registers handlers on each `MCP.Client`
/// that forward to a value conforming to this protocol.
/// Roots come from per-server settings. Sampling and elicitation
/// need the user, so the coordinator queues them for the UI.
protocol ClientFeatureHandling: Sendable {
    func roots(forServerNamed name: String) async -> [MCP.Root]
    func handleSampling(
        serverName: String,
        parameters: MCP.CreateSamplingMessage.Parameters
    ) async throws -> MCP.CreateSamplingMessage.Result
    func handleElicitation(
        serverName: String,
        parameters: MCP.CreateElicitation.Parameters
    ) async throws -> MCP.CreateElicitation.Result
}

// MARK: - Pending requests

@MainActor
@Observable
final class PendingSamplingRequest: Identifiable {
    let id = UUID()
    let serverName: String
    let parameters: MCP.CreateSamplingMessage.Parameters

    /// Generated text, shown for review before it goes to the server.
    var generatedText: String = ""
    var modelName: String?
    var isGenerating = false
    var generationError: String?

    @ObservationIgnored
    fileprivate let continuation:
        CheckedContinuation<MCP.CreateSamplingMessage.Result, any Error>
    @ObservationIgnored
    fileprivate var isCompleted = false

    fileprivate init(
        serverName: String,
        parameters: MCP.CreateSamplingMessage.Parameters,
        continuation: CheckedContinuation<MCP.CreateSamplingMessage.Result, any Error>
    ) {
        self.serverName = serverName
        self.parameters = parameters
        self.continuation = continuation
    }

    fileprivate func resume(returning result: MCP.CreateSamplingMessage.Result) {
        guard !isCompleted else { return }
        isCompleted = true
        continuation.resume(returning: result)
    }

    fileprivate func resume(throwing error: any Error) {
        guard !isCompleted else { return }
        isCompleted = true
        continuation.resume(throwing: error)
    }
}

@MainActor
@Observable
final class PendingElicitationRequest: Identifiable {
    let id = UUID()
    let serverName: String
    let parameters: MCP.CreateElicitation.Parameters

    @ObservationIgnored
    fileprivate let continuation:
        CheckedContinuation<MCP.CreateElicitation.Result, any Error>
    @ObservationIgnored
    fileprivate var isCompleted = false

    fileprivate init(
        serverName: String,
        parameters: MCP.CreateElicitation.Parameters,
        continuation: CheckedContinuation<MCP.CreateElicitation.Result, any Error>
    ) {
        self.serverName = serverName
        self.parameters = parameters
        self.continuation = continuation
    }

    fileprivate func resume(returning result: MCP.CreateElicitation.Result) {
        guard !isCompleted else { return }
        isCompleted = true
        continuation.resume(returning: result)
    }

    fileprivate func resume(throwing error: any Error) {
        guard !isCompleted else { return }
        isCompleted = true
        continuation.resume(throwing: error)
    }
}

// MARK: - Coordinator

@MainActor
@Observable
final class ClientFeatureCoordinator {
    private(set) var pendingSamplingRequests: [PendingSamplingRequest] = []
    private(set) var pendingElicitationRequests: [PendingElicitationRequest] = []

    @ObservationIgnored
    private let settingsStore: ServerSettingsStore
    @ObservationIgnored
    let samplingService: SamplingService

    init(
        settingsStore: ServerSettingsStore = ServerSettingsStore(),
        samplingService: SamplingService = SamplingService()
    ) {
        self.settingsStore = settingsStore
        self.samplingService = samplingService
    }

    // MARK: Sampling actions (called by the review sheet)

    func generate(for request: PendingSamplingRequest) async {
        request.isGenerating = true
        request.generationError = nil
        do {
            let (text, model) = try await samplingService.generate(
                parameters: request.parameters)
            request.generatedText = text
            request.modelName = model
        } catch {
            request.generationError = error.localizedDescription
        }
        request.isGenerating = false
    }

    func approveSampling(_ request: PendingSamplingRequest) {
        let result = MCP.CreateSamplingMessage.Result(
            model: request.modelName ?? "companion",
            stopReason: .endTurn,
            role: .assistant,
            content: .text(request.generatedText)
        )
        request.resume(returning: result)
        pendingSamplingRequests.removeAll { $0.id == request.id }
    }

    /// Declines the request if the user does not answer in time.
    fileprivate func scheduleSamplingTimeout(for request: PendingSamplingRequest) {
        guard let timeout = AppSettings.requestTimeout() else { return }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self,
                pendingSamplingRequests.contains(where: { $0.id == request.id })
            else { return }
            declineSampling(request)
        }
    }

    /// Cancels the request if the user does not answer in time.
    fileprivate func scheduleElicitationTimeout(
        for request: PendingElicitationRequest
    ) {
        guard let timeout = AppSettings.requestTimeout() else { return }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard let self,
                pendingElicitationRequests.contains(where: { $0.id == request.id })
            else { return }
            completeElicitation(
                request, result: MCP.CreateElicitation.Result(action: .cancel))
        }
    }

    func declineSampling(_ request: PendingSamplingRequest) {
        request.resume(throwing: ClientFeatureError.userDeclined("sampling"))
        pendingSamplingRequests.removeAll { $0.id == request.id }
    }

    // MARK: Elicitation actions (called by the elicitation sheet)

    func completeElicitation(
        _ request: PendingElicitationRequest,
        result: MCP.CreateElicitation.Result
    ) {
        request.resume(returning: result)
        pendingElicitationRequests.removeAll { $0.id == request.id }
    }

    /// Cancels every queued request, for example when a server disconnects.
    func cancelPendingRequests(serverName: String) {
        for request in pendingSamplingRequests where request.serverName == serverName {
            request.resume(throwing: ClientFeatureError.serverDisconnected)
        }
        pendingSamplingRequests.removeAll { $0.serverName == serverName }

        for request in pendingElicitationRequests where request.serverName == serverName {
            request.resume(returning: MCP.CreateElicitation.Result(action: .cancel))
        }
        pendingElicitationRequests.removeAll { $0.serverName == serverName }
    }
}

// MARK: - ClientFeatureHandling

extension ClientFeatureCoordinator: ClientFeatureHandling {
    nonisolated func roots(forServerNamed name: String) async -> [MCP.Root] {
        ServerSettingsStore().settings(forServerNamed: name).roots
    }

    nonisolated func handleSampling(
        serverName: String,
        parameters: MCP.CreateSamplingMessage.Parameters
    ) async throws -> MCP.CreateSamplingMessage.Result {
        Logger.connection.info(
            "Sampling request from '\(serverName, privacy: .public)'")

        if SamplingService().autoApprove {
            let (text, model) = try await SamplingService().generate(parameters: parameters)
            return MCP.CreateSamplingMessage.Result(
                model: model,
                stopReason: .endTurn,
                role: .assistant,
                content: .text(text)
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let request = PendingSamplingRequest(
                    serverName: serverName,
                    parameters: parameters,
                    continuation: continuation
                )
                pendingSamplingRequests.append(request)
                scheduleSamplingTimeout(for: request)
            }
        }
    }

    nonisolated func handleElicitation(
        serverName: String,
        parameters: MCP.CreateElicitation.Parameters
    ) async throws -> MCP.CreateElicitation.Result {
        Logger.connection.info(
            "Elicitation request from '\(serverName, privacy: .public)'")

        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let request = PendingElicitationRequest(
                    serverName: serverName,
                    parameters: parameters,
                    continuation: continuation
                )
                pendingElicitationRequests.append(request)
                scheduleElicitationTimeout(for: request)
            }
        }
    }
}

enum ClientFeatureError: Swift.Error, LocalizedError {
    case userDeclined(String)
    case serverDisconnected

    var errorDescription: String? {
        switch self {
        case .userDeclined(let feature):
            return "The user declined the \(feature) request."
        case .serverDisconnected:
            return "The server disconnected before the request was answered."
        }
    }
}
