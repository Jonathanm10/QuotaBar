import Foundation

public enum StartupRefreshGate {
    public static func shouldRefresh(
        cachedSnapshots: [ProviderSnapshot],
        now: Date = Date(),
        freshnessInterval: TimeInterval = 5 * 60
    ) -> Bool {
        guard !cachedSnapshots.isEmpty else { return true }
        return cachedSnapshots.contains { now.timeIntervalSince($0.fetchedAt) > freshnessInterval }
    }
}
