import Foundation

public protocol UsageProvider: Sendable {
    var providerID: ProviderID { get }
    func fetchSnapshot(now: Date) async throws -> ProviderSnapshot
}

public struct ProviderRefreshFailure: Equatable, Sendable {
    public let provider: ProviderID
    public let message: String

    public init(provider: ProviderID, message: String) {
        self.provider = provider
        self.message = message
    }
}

public struct RefreshReport: Equatable, Sendable {
    public let snapshots: [ProviderSnapshot]
    public let failures: [ProviderRefreshFailure]

    public init(snapshots: [ProviderSnapshot], failures: [ProviderRefreshFailure]) {
        self.snapshots = snapshots
        self.failures = failures
    }
}

public actor RefreshCoordinator {
    private let providers: [any UsageProvider]
    private let refreshPolicy = RefreshPolicy()
    private var inFlightTask: Task<RefreshReport, Never>?

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public func refreshAll(trigger: RefreshTrigger = .timer, now: Date = Date()) async -> RefreshReport {
        if let inFlightTask {
            return await inFlightTask.value
        }

        var eligibleProviders: [any UsageProvider] = []
        for provider in self.providers {
            if await self.refreshPolicy.shouldRefresh(provider: provider.providerID, now: now, trigger: trigger) {
                eligibleProviders.append(provider)
            }
        }

        if eligibleProviders.isEmpty {
            return RefreshReport(snapshots: [], failures: [])
        }

        let task = Task<RefreshReport, Never> {
            await withTaskGroup(of: ProviderRefreshResult.self) { group in
                for provider in eligibleProviders {
                    group.addTask {
                        do {
                            let snapshot = try await provider.fetchSnapshot(now: now)
                            await self.refreshPolicy.recordSuccess(provider: provider.providerID, now: now)
                            return .success(snapshot)
                        } catch {
                            await self.refreshPolicy.recordFailure(provider: provider.providerID, now: now)
                            AppLog.provider.error("Provider \(provider.providerID.displayName, privacy: .public) refresh failed: \(error.localizedDescription, privacy: .public)")
                            return .failure(ProviderRefreshFailure(provider: provider.providerID, message: error.localizedDescription))
                        }
                    }
                }

                var snapshots: [ProviderSnapshot] = []
                var failures: [ProviderRefreshFailure] = []
                for await result in group {
                    switch result {
                    case let .success(snapshot):
                        snapshots.append(snapshot)
                    case let .failure(failure):
                        failures.append(failure)
                    }
                }
                return RefreshReport(
                    snapshots: snapshots.sorted { $0.provider.rawValue < $1.provider.rawValue },
                    failures: failures.sorted { $0.provider.rawValue < $1.provider.rawValue }
                )
            }
        }

        self.inFlightTask = task
        let report = await task.value
        self.inFlightTask = nil
        return report
    }
}

private enum ProviderRefreshResult: Sendable {
    case success(ProviderSnapshot)
    case failure(ProviderRefreshFailure)
}
