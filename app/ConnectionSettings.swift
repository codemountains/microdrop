#if os(iOS)
import Foundation
import Observation

@MainActor
@Observable
final class ConnectionSettings {
    enum State {
        case loading
        case empty
        case registered(CredentialRegistration)
        case unavailable(String)
    }

    private(set) var state = State.loading
    private(set) var isSaving = false
    private var revision = 0

    var hasRegistration: Bool {
        if case .registered = state { return true }
        return false
    }

    func refresh() async {
        guard !isSaving else { return }
        await reload()
    }

    private func reload() async {
        revision += 1
        let currentRevision = revision
        let result = await Task.detached {
            Result { try CredentialStore.registration() }
        }.value
        guard currentRevision == revision else { return }
        switch result {
        case .success(let registration):
            state = registration.map(State.registered) ?? .empty
        case .failure(let error):
            state = .unavailable(error.localizedDescription)
        }
    }

    func register(serviceID: String, apiKey: String) async throws {
        try await change { try CredentialStore.register(serviceID: serviceID, apiKey: apiKey) }
    }

    func delete(_ registration: CredentialRegistration) async throws {
        try await change { try CredentialStore.delete(registration) }
    }

    private func change(_ operation: @escaping @Sendable () throws -> Void) async throws {
        guard !isSaving else { throw ChangeInProgress() }
        isSaving = true
        revision += 1
        let result = await Task.detached { Result { try operation() } }.value
        await reload()
        isSaving = false
        try result.get()
    }

    private struct ChangeInProgress: LocalizedError {
        var errorDescription: String? { "設定を保存しています。少し待ってからお試しください。" }
    }
}
#endif
