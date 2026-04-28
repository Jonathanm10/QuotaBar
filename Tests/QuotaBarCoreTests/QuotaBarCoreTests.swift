import Foundation
import Testing
@testable import QuotaBarCore

@Test
func openAIAuthParsesOAuthTokens() throws {
    let json = """
    {
      "auth_mode": "oauth",
      "last_refresh": "2026-04-16T10:00:00Z",
      "tokens": {
        "access_token": "access",
        "account_id": "account",
        "id_token": "id",
        "refresh_token": "refresh"
      }
    }
    """
    let decoded = try JSONDecoder.iso8601.decode(OpenAIAuthFile.self, from: Data(json.utf8))
    #expect(decoded.tokens?.accessToken == "access")
    #expect(decoded.tokens?.accountID == "account")
}

@Test
func openAIUsageDecodesWindowsAndCredits() throws {
    let json = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": {
          "used_percent": 3,
          "limit_window_seconds": 18000,
          "reset_at": 1776440459
        },
        "secondary_window": {
          "used_percent": 4,
          "limit_window_seconds": 604800,
          "reset_at": 1777009247
        }
      },
      "credits": {
        "balance": "12.5"
      }
    }
    """

    let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: Data(json.utf8))
    #expect(decoded.rateLimit?.primaryWindow?.usedPercent == 3)
    #expect(decoded.credits?.balance == "12.5")
}

@Test
func openAIUsageDecodesZeroAndFractionalPercents() throws {
    let json = """
    {
      "rate_limit": {
        "primary_window": {
          "used_percent": 0.0,
          "limit_window_seconds": 18000,
          "reset_at": 1776440459
        },
        "secondary_window": {
          "used_percent": 0.5,
          "limit_window_seconds": 604800,
          "reset_at": 1777009247
        }
      }
    }
    """

    let decoded = try JSONDecoder().decode(OpenAIUsageResponse.self, from: Data(json.utf8))
    #expect(decoded.rateLimit?.primaryWindow?.usedPercent == 0)
    #expect(decoded.rateLimit?.secondaryWindow?.usedPercent == 0.5)
}

@Test
func anthropicUsageDecodesWindows() throws {
    let json = """
    {
      "five_hour": { "utilization": 10.0, "resets_at": "2026-04-17T15:00:00.545103+00:00" },
      "seven_day": { "utilization": 2.0, "resets_at": "2026-04-24T05:00:00.545127+00:00" }
    }
    """

    let decoded = try JSONDecoder().decode(AnthropicUsageResponse.self, from: Data(json.utf8))
    #expect(decoded.fiveHour?.utilization == 10.0)
    #expect(decoded.sevenDay?.utilization == 2.0)
}

@Test
func snapshotStoreRoundTrips() async throws {
    let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
    let store = SnapshotStore(appSupportRoot: root)
    let snapshot = ProviderSnapshot(
        provider: .openAI,
        daily: UsageWindow(label: "5h", usedPercent: 10, sourceWindowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1), source: .oauth, note: nil),
        weekly: nil,
        reserve: nil,
        source: "oauth",
        fetchedAt: Date(timeIntervalSince1970: 2)
    )

    try await store.save([snapshot])
    let loaded = try await store.load()
    #expect(loaded == [snapshot])
}

@Test
func compactUsageFormatsUsedPercents() {
    let snapshot = ProviderSnapshot(
        provider: .openAI,
        daily: UsageWindow(label: "5h", usedPercent: 3.4, sourceWindowMinutes: 300, resetsAt: nil, source: .oauth),
        weekly: UsageWindow(label: "Weekly", usedPercent: 14.6, sourceWindowMinutes: 10080, resetsAt: nil, source: .oauth),
        reserve: nil,
        source: "oauth",
        fetchedAt: .now
    )
    #expect(Formatting.compactUsage(snapshot) == "3%/15%")
}

@Test
func startupRefreshGateSkipsFreshCache() {
    let now = Date(timeIntervalSince1970: 2_000_000)
    let freshSnapshot = ProviderSnapshot(
        provider: .openAI,
        daily: nil,
        weekly: nil,
        reserve: nil,
        source: "cache",
        fetchedAt: now.addingTimeInterval(-60)
    )

    #expect(StartupRefreshGate.shouldRefresh(cachedSnapshots: [freshSnapshot], now: now) == false)
    #expect(StartupRefreshGate.shouldRefresh(cachedSnapshots: [freshSnapshot], now: now.addingTimeInterval(301)) == true)
}

@Test
func refreshPolicyFailureBackoffRespectsFiveMinuteFloor() async {
    let policy = RefreshPolicy()
    let now = Date(timeIntervalSince1970: 3_000_000)
    await policy.recordFailure(provider: .openAI, now: now)
    #expect(await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(299), trigger: .timer) == false)
    #expect(await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(318), trigger: .timer) == true)
}

@Test
func refreshPolicyMenuOpenBypassesSuccessThrottle() async {
    let policy = RefreshPolicy()
    let now = Date(timeIntervalSince1970: 4_000_000)
    await policy.recordSuccess(provider: .openAI, now: now)

    #expect(await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(10), trigger: .timer) == false)
    #expect(await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(10), trigger: .menuOpen) == true)
}

@Test
func refreshCoordinatorReportsProviderFailureBesideSuccess() async {
    let now = Date(timeIntervalSince1970: 5_000_000)
    let anthropicSnapshot = ProviderSnapshot(
        provider: .anthropic,
        daily: nil,
        weekly: UsageWindow(label: "7d", usedPercent: 1, sourceWindowMinutes: 10_080, resetsAt: nil, source: .oauth),
        reserve: nil,
        source: "oauth",
        fetchedAt: now
    )
    let coordinator = RefreshCoordinator(providers: [
        StubProvider(providerID: .openAI) { _ in throw StubProviderError.refreshFailed },
        StubProvider(providerID: .anthropic) { _ in anthropicSnapshot },
    ])

    let report = await coordinator.refreshAll(trigger: .manual, now: now)

    #expect(report.snapshots == [anthropicSnapshot])
    #expect(report.failures == [
        ProviderRefreshFailure(provider: .openAI, message: "token refresh unavailable"),
    ])
}

@Test
func cachedSnapshotMarkedAfterRefreshFailureKeepsCacheProvenance() {
    let cached = ProviderSnapshot(
        provider: .openAI,
        daily: nil,
        weekly: UsageWindow(label: "7d", usedPercent: 25, sourceWindowMinutes: 10_080, resetsAt: nil, source: .cache),
        reserve: nil,
        source: "cache",
        fetchedAt: Date(timeIntervalSince1970: 6_000_000)
    )
    let marked = cached.markingRefreshFailure(
        ProviderRefreshFailure(provider: .openAI, message: "token refresh unavailable")
    )

    #expect(marked.weekly?.usedPercent == 25)
    #expect(marked.source == "cache")
    #expect(marked.warning == "OpenAI refresh failed: token refresh unavailable")
}

@Test
func usagePaceReturnsOnTrackWhenHalfway() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(2.5 * 60 * 60)
    let window = UsageWindow(
        label: "5h",
        usedPercent: 49,
        sourceWindowMinutes: 300,
        resetsAt: resetsAt,
        source: .oauth
    )
    let pace = UsagePace.compute(window: window, now: now)
    #expect(pace?.stage == .onTrack)
    #expect(pace != nil && abs(pace!.deltaPercent) <= 2)
}

@Test
func usagePaceFlagsReserveWhenWellUnderExpected() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(2.5 * 60 * 60)
    let window = UsageWindow(
        label: "5h",
        usedPercent: 10,
        sourceWindowMinutes: 300,
        resetsAt: resetsAt,
        source: .oauth
    )
    let pace = UsagePace.compute(window: window, now: now)
    #expect(pace?.stage == .moderateReserve || pace?.stage == .deepReserve)
    #expect(pace != nil && pace!.deltaPercent < 0)
    #expect(pace?.lastsToReset == true)
}

@Test
func usagePaceFlagsDeficitWhenWellOverExpected() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    let resetsAt = now.addingTimeInterval(2.5 * 60 * 60)
    let window = UsageWindow(
        label: "5h",
        usedPercent: 85,
        sourceWindowMinutes: 300,
        resetsAt: resetsAt,
        source: .oauth
    )
    let pace = UsagePace.compute(window: window, now: now)
    #expect(pace?.stage == .severeDeficit)
    #expect(pace != nil && pace!.deltaPercent > 0)
    #expect(pace?.etaUntilExhaustion != nil)
}

@Test
func paceLabelFormatsReserveAndDeficit() {
    let onPace = UsagePace(stage: .onTrack, deltaPercent: 0, expectedPercent: 50, actualPercent: 50, etaUntilExhaustion: nil, lastsToReset: true)
    #expect(Formatting.paceLabel(onPace) == "On pace")

    let reserve = UsagePace(stage: .moderateReserve, deltaPercent: -8.4, expectedPercent: 50, actualPercent: 41.6, etaUntilExhaustion: nil, lastsToReset: true)
    #expect(Formatting.paceLabel(reserve) == "Reserve +8%")

    let deficit = UsagePace(stage: .moderateDeficit, deltaPercent: 9.2, expectedPercent: 50, actualPercent: 59.2, etaUntilExhaustion: 3600, lastsToReset: false)
    #expect(Formatting.paceLabel(deficit) == "Deficit -9%")
}

@Test
func shortDurationFormatsSensibly() {
    #expect(Formatting.shortDuration(45 * 60) == "45m")
    #expect(Formatting.shortDuration(3 * 60 * 60) == "3h")
    #expect(Formatting.shortDuration(3 * 60 * 60 + 30 * 60) == "3h30m")
    #expect(Formatting.shortDuration(3 * 24 * 60 * 60) == "3d")
}

private struct StubProvider: UsageProvider {
    let providerID: ProviderID
    let fetch: @Sendable (Date) async throws -> ProviderSnapshot

    init(providerID: ProviderID, fetch: @escaping @Sendable (Date) async throws -> ProviderSnapshot) {
        self.providerID = providerID
        self.fetch = fetch
    }

    func fetchSnapshot(now: Date) async throws -> ProviderSnapshot {
        try await fetch(now)
    }
}

private enum StubProviderError: LocalizedError, Sendable {
    case refreshFailed

    var errorDescription: String? {
        "token refresh unavailable"
    }
}
