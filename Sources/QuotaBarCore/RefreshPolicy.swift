import Foundation

public enum RefreshTrigger: String, Sendable {
    case startup
    case timer
    case menuOpen
    case manual
}

public actor RefreshPolicy {
    private struct ProviderState {
        var nextAllowedRefreshAt: Date
        var consecutiveFailures: Int
    }

    private var state: [ProviderID: ProviderState] = [:]

    public init() {}

    public func shouldRefresh(provider: ProviderID, now: Date, trigger: RefreshTrigger) -> Bool {
        guard trigger != .manual, trigger != .menuOpen else { return true }
        guard let state = self.state[provider] else { return true }
        return now >= state.nextAllowedRefreshAt
    }

    public func recordSuccess(provider: ProviderID, now: Date) {
        self.state[provider] = ProviderState(
            nextAllowedRefreshAt: now.addingTimeInterval(5 * 60 + jitterSeconds(for: provider)),
            consecutiveFailures: 0
        )
    }

    public func recordFailure(provider: ProviderID, now: Date) {
        let failures = (self.state[provider]?.consecutiveFailures ?? 0) + 1
        let backoff = max(5 * 60, min(30 * 60, pow(2, Double(min(failures, 5))) * 60))
        self.state[provider] = ProviderState(
            nextAllowedRefreshAt: now.addingTimeInterval(backoff + jitterSeconds(for: provider)),
            consecutiveFailures: failures
        )
    }

    private func jitterSeconds(for provider: ProviderID) -> TimeInterval {
        switch provider {
        case .openAI: 17
        case .anthropic: 31
        }
    }
}
