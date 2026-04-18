import Foundation
import Observation
import QuotaBarCore

@MainActor
@Observable
final class AppState {
    var snapshots: [ProviderID: ProviderSnapshot] = [:]
    var isRefreshing = false
    var isPopoverPresented = false
    var lastRefreshAt: Date?
    var lastError: String?

    var orderedSnapshots: [ProviderSnapshot] {
        snapshots.values.sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    func apply(_ snapshot: ProviderSnapshot) {
        snapshots[snapshot.provider] = snapshot
    }
}
