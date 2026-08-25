import Foundation
import Darwin
@testable import QuotaBarCore

final class QuotaBarCoreTests: @unchecked Sendable {
    func testOpenAIAuthParsesOAuthTokens() throws {
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
        XCTAssert(decoded.tokens?.accessToken == "access")
        XCTAssert(decoded.tokens?.accountID == "account")
    }

    func testOpenAIUsageDecodesWindowsAndCredits() throws {
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
        XCTAssert(decoded.rateLimit?.primaryWindow?.usedPercent == 3)
        XCTAssert(decoded.credits?.balance == "12.5")
    }

    func testOpenAIUsageDecodesZeroAndFractionalPercents() throws {
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
        XCTAssert(decoded.rateLimit?.primaryWindow?.usedPercent == 0)
        XCTAssert(decoded.rateLimit?.secondaryWindow?.usedPercent == 0.5)
    }

    func testOpenAIRefreshFailureDescriptionIncludesServerBody() {
        let error = OpenAIProviderError.refreshFailed(
            statusCode: 400,
            body: #"{"error":"invalid_grant","error_description":"Refresh token expired"}"#
        )

        XCTAssert(error.localizedDescription.contains("HTTP 400"))
        XCTAssert(error.localizedDescription.contains("invalid_grant"))
        XCTAssert(error.localizedDescription.contains("Refresh token expired"))
    }

    func testOpenAIRefreshDecodeFailureDescriptionIncludesBody() {
        let error = OpenAIProviderError.refreshDecodeFailed(
            reason: "missing access_token",
            body: #"{"unexpected":true}"#
        )

        XCTAssert(error.localizedDescription.contains("missing access_token"))
        XCTAssert(error.localizedDescription.contains(#""unexpected":true"#))
    }

    func testOpenAIUsageFailureDescriptionIncludesServerBody() {
        let error = OpenAIProviderError.httpError(
            statusCode: 403,
            body: #"{"detail":"account header required"}"#
        )

        XCTAssert(error.localizedDescription.contains("HTTP 403"))
        XCTAssert(error.localizedDescription.contains("account header required"))
    }

    func testAnthropicUsageDecodesWindows() throws {
        let json = """
        {
          "five_hour": { "utilization": 10.0, "resets_at": "2026-04-17T15:00:00.545103+00:00" },
          "seven_day": { "utilization": 2.0, "resets_at": "2026-04-24T05:00:00.545127+00:00" }
        }
        """

        let decoded = try JSONDecoder().decode(AnthropicUsageResponse.self, from: Data(json.utf8))
        XCTAssert(decoded.fiveHour?.utilization == 10.0)
        XCTAssert(decoded.sevenDay?.utilization == 2.0)
    }

    func testAnthropicUsageDecodesScopedLimits() throws {
        let json = """
        {
          "five_hour": { "utilization": 6.0, "resets_at": "2026-08-25T16:09:59.930588+00:00" },
          "seven_day": { "utilization": 15.0, "resets_at": "2026-08-31T07:59:59.930611+00:00" },
          "seven_day_opus": null,
          "tangelo": null,
          "limits": [
            { "kind": "session", "group": "session", "percent": 6, "severity": "normal",
              "resets_at": "2026-08-25T16:09:59.930588+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_all", "group": "weekly", "percent": 15, "severity": "normal",
              "resets_at": "2026-08-31T07:59:59.930611+00:00", "scope": null, "is_active": false },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 26, "severity": "normal",
              "resets_at": "2026-08-31T07:59:59.930933+00:00",
              "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": true }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(AnthropicUsageResponse.self, from: Data(json.utf8))
        let snapshot = try AnthropicProvider.makeSnapshot(from: decoded, now: Date(timeIntervalSince1970: 1))

        XCTAssert(snapshot.daily?.usedPercent == 6)
        XCTAssert(snapshot.weekly?.usedPercent == 15)
        XCTAssert(snapshot.additionalWindows.count == 1)
        XCTAssert(snapshot.additionalWindows.first?.label == "Fable")
        XCTAssert(snapshot.additionalWindows.first?.usedPercent == 26)
        XCTAssert(snapshot.additionalWindows.first?.sourceWindowMinutes == 10_080)
        XCTAssert(snapshot.additionalWindows.first?.resetsAt != nil)
    }

    func testAnthropicSnapshotIgnoresUnscopedLimits() throws {
        let json = """
        {
          "five_hour": { "utilization": 6.0, "resets_at": null },
          "seven_day": { "utilization": 15.0, "resets_at": null },
          "limits": [
            { "kind": "session", "group": "session", "percent": 6, "scope": null },
            { "kind": "weekly_all", "group": "weekly", "percent": 15, "scope": null },
            { "kind": "weekly_scoped", "group": "weekly", "percent": 40, "scope": { "model": null, "surface": "cowork" } }
          ]
        }
        """

        let decoded = try JSONDecoder().decode(AnthropicUsageResponse.self, from: Data(json.utf8))
        let snapshot = try AnthropicProvider.makeSnapshot(from: decoded, now: Date(timeIntervalSince1970: 1))
        XCTAssert(snapshot.additionalWindows.isEmpty)
        XCTAssert(snapshot.extraWindows == nil)
    }

    func testSnapshotStoreRoundTrips() async throws {
        let root = URL(filePath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        let store = SnapshotStore(appSupportRoot: root)
        let snapshot = ProviderSnapshot(
            provider: .openAI,
            daily: UsageWindow(label: "5h", usedPercent: 10, sourceWindowMinutes: 300, resetsAt: Date(timeIntervalSince1970: 1), source: .oauth, note: nil),
            weekly: nil,
            reserve: nil,
            extraWindows: [UsageWindow(label: "Fable", usedPercent: 26, sourceWindowMinutes: 10_080, resetsAt: nil, source: .oauth)],
            source: "oauth",
            fetchedAt: Date(timeIntervalSince1970: 2)
        )

        try await store.save([snapshot])
        let loaded = try await store.load()
        XCTAssert(loaded == [snapshot])
    }

    func testSnapshotDecodesLegacyEnvelopeWithoutExtraWindows() throws {
        let json = """
        {
          "snapshots": [
            { "provider": "anthropic", "daily": null, "weekly": null, "reserve": null,
              "source": "oauth", "fetchedAt": 0, "warning": null }
          ]
        }
        """
        let envelope = try JSONDecoder().decode(SnapshotEnvelope.self, from: Data(json.utf8))
        XCTAssert(envelope.snapshots.first?.extraWindows == nil)
        XCTAssert(envelope.snapshots.first?.additionalWindows.isEmpty == true)
    }

    func testCompactUsageFormatsUsedPercents() {
        let snapshot = ProviderSnapshot(
            provider: .openAI,
            daily: UsageWindow(label: "5h", usedPercent: 3.4, sourceWindowMinutes: 300, resetsAt: nil, source: .oauth),
            weekly: UsageWindow(label: "Weekly", usedPercent: 14.6, sourceWindowMinutes: 10080, resetsAt: nil, source: .oauth),
            reserve: nil,
            source: "oauth",
            fetchedAt: .now
        )
        XCTAssert(Formatting.compactUsage(snapshot) == "3%/15%")
    }

    func testCompactUsageAppendsScopedWindow() {
        let snapshot = ProviderSnapshot(
            provider: .anthropic,
            daily: UsageWindow(label: "5h", usedPercent: 3.4, sourceWindowMinutes: 300, resetsAt: nil, source: .oauth),
            weekly: UsageWindow(label: "Weekly", usedPercent: 14.6, sourceWindowMinutes: 10080, resetsAt: nil, source: .oauth),
            reserve: nil,
            extraWindows: [UsageWindow(label: "Fable", usedPercent: 26, sourceWindowMinutes: 10080, resetsAt: nil, source: .oauth)],
            source: "oauth",
            fetchedAt: .now
        )
        XCTAssert(Formatting.compactUsage(snapshot) == "3%/15%/26%")
        XCTAssert(Formatting.compactUsage(snapshot, includesWeekly: false) == "3%/26%")
        XCTAssert(Formatting.compactUsage(snapshot, showRemaining: true) == "97%/85%/74%")
    }

    func testStartupRefreshGateSkipsFreshCache() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let freshSnapshot = ProviderSnapshot(
            provider: .openAI,
            daily: nil,
            weekly: nil,
            reserve: nil,
            source: "cache",
            fetchedAt: now.addingTimeInterval(-60)
        )

        XCTAssert(StartupRefreshGate.shouldRefresh(cachedSnapshots: [freshSnapshot], now: now) == false)
        XCTAssert(StartupRefreshGate.shouldRefresh(cachedSnapshots: [freshSnapshot], now: now.addingTimeInterval(301)) == true)
    }

    func testRefreshPolicyFailureBackoffRespectsFiveMinuteFloor() async {
        let policy = RefreshPolicy()
        let now = Date(timeIntervalSince1970: 3_000_000)
        await policy.recordFailure(provider: .openAI, now: now)
        let shouldRefreshBeforeFloor = await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(299), trigger: .timer)
        let shouldRefreshAfterFloor = await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(318), trigger: .timer)
        XCTAssert(shouldRefreshBeforeFloor == false)
        XCTAssert(shouldRefreshAfterFloor == true)
    }

    func testRefreshPolicyMenuOpenBypassesSuccessThrottle() async {
        let policy = RefreshPolicy()
        let now = Date(timeIntervalSince1970: 4_000_000)
        await policy.recordSuccess(provider: .openAI, now: now)

        let shouldRefreshOnTimer = await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(10), trigger: .timer)
        let shouldRefreshOnMenuOpen = await policy.shouldRefresh(provider: .openAI, now: now.addingTimeInterval(10), trigger: .menuOpen)
        XCTAssert(shouldRefreshOnTimer == false)
        XCTAssert(shouldRefreshOnMenuOpen == true)
    }

    func testRefreshCoordinatorReportsProviderFailureBesideSuccess() async {
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

        XCTAssert(report.snapshots == [anthropicSnapshot])
        XCTAssert(report.failures == [
            ProviderRefreshFailure(provider: .openAI, message: "token refresh unavailable"),
        ])
    }

    func testRefreshReportOnlySurfacesFailuresWithoutProviderSnapshots() {
        let report = RefreshReport(
            snapshots: [],
            failures: [
                ProviderRefreshFailure(provider: .anthropic, message: "HTTP 403"),
                ProviderRefreshFailure(provider: .openAI, message: "token refresh unavailable"),
            ]
        )

        XCTAssert(report.failuresWithoutSnapshots(attachedProviders: [.anthropic]) == [
            ProviderRefreshFailure(provider: .openAI, message: "token refresh unavailable"),
        ])
        XCTAssert(report.failuresWithoutSnapshots(attachedProviders: [.anthropic, .openAI]).isEmpty)
    }

    func testCachedSnapshotMarkedAfterRefreshFailureKeepsCacheProvenance() {
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

        XCTAssert(marked.weekly?.usedPercent == 25)
        XCTAssert(marked.source == "cache")
        XCTAssert(marked.warning == "OpenAI refresh failed: token refresh unavailable")
    }

    func testUsagePaceReturnsOnTrackWhenHalfway() {
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
        XCTAssert(pace?.stage == .onTrack)
        XCTAssert(pace != nil && abs(pace!.deltaPercent) <= 2)
    }

    func testUsagePaceFlagsReserveWhenWellUnderExpected() {
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
        XCTAssert(pace?.stage == .moderateReserve || pace?.stage == .deepReserve)
        XCTAssert(pace != nil && pace!.deltaPercent < 0)
        XCTAssert(pace?.lastsToReset == true)
    }

    func testUsagePaceFlagsDeficitWhenWellOverExpected() {
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
        XCTAssert(pace?.stage == .severeDeficit)
        XCTAssert(pace != nil && pace!.deltaPercent > 0)
        XCTAssert(pace?.etaUntilExhaustion != nil)
    }

    func testPaceLabelFormatsReserveAndDeficit() {
        let onPace = UsagePace(stage: .onTrack, deltaPercent: 0, expectedPercent: 50, actualPercent: 50, etaUntilExhaustion: nil, lastsToReset: true)
        XCTAssert(Formatting.paceLabel(onPace) == "On pace")

        let reserve = UsagePace(stage: .moderateReserve, deltaPercent: -8.4, expectedPercent: 50, actualPercent: 41.6, etaUntilExhaustion: nil, lastsToReset: true)
        XCTAssert(Formatting.paceLabel(reserve) == "Reserve +8%")

        let deficit = UsagePace(stage: .moderateDeficit, deltaPercent: 9.2, expectedPercent: 50, actualPercent: 59.2, etaUntilExhaustion: 3600, lastsToReset: false)
        XCTAssert(Formatting.paceLabel(deficit) == "Deficit -9%")
    }

    func testShortDurationFormatsSensibly() {
        XCTAssert(Formatting.shortDuration(45 * 60) == "45m")
        XCTAssert(Formatting.shortDuration(3 * 60 * 60) == "3h")
        XCTAssert(Formatting.shortDuration(3 * 60 * 60 + 30 * 60) == "3h30m")
        XCTAssert(Formatting.shortDuration(3 * 24 * 60 * 60) == "3d")
    }

}

@main
enum QuotaBarCoreTestRunner {
    static func main() async {
        let suite = QuotaBarCoreTests()
        let tests = [
            TestCase("openAIAuthParsesOAuthTokens", suite.testOpenAIAuthParsesOAuthTokens),
            TestCase("openAIUsageDecodesWindowsAndCredits", suite.testOpenAIUsageDecodesWindowsAndCredits),
            TestCase("openAIUsageDecodesZeroAndFractionalPercents", suite.testOpenAIUsageDecodesZeroAndFractionalPercents),
            TestCase("openAIRefreshFailureDescriptionIncludesServerBody", suite.testOpenAIRefreshFailureDescriptionIncludesServerBody),
            TestCase("openAIRefreshDecodeFailureDescriptionIncludesBody", suite.testOpenAIRefreshDecodeFailureDescriptionIncludesBody),
            TestCase("openAIUsageFailureDescriptionIncludesServerBody", suite.testOpenAIUsageFailureDescriptionIncludesServerBody),
            TestCase("anthropicUsageDecodesWindows", suite.testAnthropicUsageDecodesWindows),
            TestCase("anthropicUsageDecodesScopedLimits", suite.testAnthropicUsageDecodesScopedLimits),
            TestCase("anthropicSnapshotIgnoresUnscopedLimits", suite.testAnthropicSnapshotIgnoresUnscopedLimits),
            TestCase("snapshotStoreRoundTrips", suite.testSnapshotStoreRoundTrips),
            TestCase("snapshotDecodesLegacyEnvelopeWithoutExtraWindows", suite.testSnapshotDecodesLegacyEnvelopeWithoutExtraWindows),
            TestCase("compactUsageFormatsUsedPercents", suite.testCompactUsageFormatsUsedPercents),
            TestCase("compactUsageAppendsScopedWindow", suite.testCompactUsageAppendsScopedWindow),
            TestCase("startupRefreshGateSkipsFreshCache", suite.testStartupRefreshGateSkipsFreshCache),
            TestCase("refreshPolicyFailureBackoffRespectsFiveMinuteFloor", suite.testRefreshPolicyFailureBackoffRespectsFiveMinuteFloor),
            TestCase("refreshPolicyMenuOpenBypassesSuccessThrottle", suite.testRefreshPolicyMenuOpenBypassesSuccessThrottle),
            TestCase("refreshCoordinatorReportsProviderFailureBesideSuccess", suite.testRefreshCoordinatorReportsProviderFailureBesideSuccess),
            TestCase("refreshReportOnlySurfacesFailuresWithoutProviderSnapshots", suite.testRefreshReportOnlySurfacesFailuresWithoutProviderSnapshots),
            TestCase("cachedSnapshotMarkedAfterRefreshFailureKeepsCacheProvenance", suite.testCachedSnapshotMarkedAfterRefreshFailureKeepsCacheProvenance),
            TestCase("usagePaceReturnsOnTrackWhenHalfway", suite.testUsagePaceReturnsOnTrackWhenHalfway),
            TestCase("usagePaceFlagsReserveWhenWellUnderExpected", suite.testUsagePaceFlagsReserveWhenWellUnderExpected),
            TestCase("usagePaceFlagsDeficitWhenWellOverExpected", suite.testUsagePaceFlagsDeficitWhenWellOverExpected),
            TestCase("paceLabelFormatsReserveAndDeficit", suite.testPaceLabelFormatsReserveAndDeficit),
            TestCase("shortDurationFormatsSensibly", suite.testShortDurationFormatsSensibly),
        ]

        var failures = 0
        for test in tests {
            do {
                try await test.run()
                print("PASS \(test.name)")
            } catch {
                failures += 1
                print("FAIL \(test.name): \(error)")
            }
        }

        print("\(tests.count - failures)/\(tests.count) tests passed")
        if failures > 0 {
            exit(1)
        }
    }
}

private struct TestCase {
    let name: String
    let run: () async throws -> Void

    init(_ name: String, _ run: @escaping () -> Void) {
        self.name = name
        self.run = { run() }
    }

    init(_ name: String, _ run: @escaping () throws -> Void) {
        self.name = name
        self.run = { try run() }
    }

    init(_ name: String, _ run: @escaping () async -> Void) {
        self.name = name
        self.run = { await run() }
    }

    init(_ name: String, _ run: @escaping () async throws -> Void) {
        self.name = name
        self.run = { try await run() }
    }
}

private func XCTAssert(
    _ condition: @autoclosure () -> Bool,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard condition() else {
        let suffix = message.isEmpty ? "" : ": \(message)"
        fputs("Assertion failed at \(file):\(line)\(suffix)\n", stderr)
        exit(1)
    }
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
