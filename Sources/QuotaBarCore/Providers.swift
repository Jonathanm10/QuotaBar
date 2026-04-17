import Foundation

public protocol UsageProvider: Sendable {
    var providerID: ProviderID { get }
    func fetchSnapshot(now: Date) async throws -> ProviderSnapshot
}

public actor RefreshCoordinator {
    private let providers: [any UsageProvider]
    private let refreshPolicy = RefreshPolicy()
    private var inFlightTask: Task<[ProviderSnapshot], Never>?

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public func refreshAll(trigger: RefreshTrigger = .timer, now: Date = Date()) async -> [ProviderSnapshot] {
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
            return []
        }

        let task = Task<[ProviderSnapshot], Never> {
            await withTaskGroup(of: ProviderSnapshot?.self) { group in
                for provider in eligibleProviders {
                    group.addTask {
                        do {
                            let snapshot = try await provider.fetchSnapshot(now: now)
                            await self.refreshPolicy.recordSuccess(provider: provider.providerID, now: now)
                            return snapshot
                        } catch {
                            await self.refreshPolicy.recordFailure(provider: provider.providerID, now: now)
                            AppLog.provider.error("Provider \(provider.providerID.displayName, privacy: .public) refresh failed")
                            return nil
                        }
                    }
                }

                var snapshots: [ProviderSnapshot] = []
                for await snapshot in group {
                    if let snapshot {
                        snapshots.append(snapshot)
                    }
                }
                return snapshots.sorted { $0.provider.rawValue < $1.provider.rawValue }
            }
        }

        self.inFlightTask = task
        let snapshots = await task.value
        self.inFlightTask = nil
        return snapshots
    }
}
