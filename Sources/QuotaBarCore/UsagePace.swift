import Foundation

public enum PaceStage: String, Sendable, Equatable, Codable {
    case onTrack
    case slightReserve
    case moderateReserve
    case deepReserve
    case slightDeficit
    case moderateDeficit
    case severeDeficit

    public var isReserve: Bool {
        switch self {
        case .slightReserve, .moderateReserve, .deepReserve: true
        default: false
        }
    }

    public var isDeficit: Bool {
        switch self {
        case .slightDeficit, .moderateDeficit, .severeDeficit: true
        default: false
        }
    }
}

public struct UsagePace: Sendable, Equatable {
    public let stage: PaceStage
    public let deltaPercent: Double
    public let expectedPercent: Double
    public let actualPercent: Double
    public let etaUntilExhaustion: TimeInterval?
    public let lastsToReset: Bool

    public init(
        stage: PaceStage,
        deltaPercent: Double,
        expectedPercent: Double,
        actualPercent: Double,
        etaUntilExhaustion: TimeInterval?,
        lastsToReset: Bool
    ) {
        self.stage = stage
        self.deltaPercent = deltaPercent
        self.expectedPercent = expectedPercent
        self.actualPercent = actualPercent
        self.etaUntilExhaustion = etaUntilExhaustion
        self.lastsToReset = lastsToReset
    }

    public static func compute(window: UsageWindow, now: Date = Date()) -> UsagePace? {
        guard
            let resetsAt = window.resetsAt,
            let minutes = window.sourceWindowMinutes,
            minutes > 0
        else { return nil }

        let duration = TimeInterval(minutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let elapsed = max(0, min(duration, duration - timeUntilReset))
        let expected = clamp((elapsed / duration) * 100, lower: 0, upper: 100)
        let actual = clamp(window.usedPercent, lower: 0, upper: 100)

        if elapsed == 0, actual > 0 { return nil }
        let delta = actual - expected

        var eta: TimeInterval?
        var lasts = false
        if elapsed > 0, actual > 0 {
            let rate = actual / elapsed
            if rate > 0 {
                let remaining = max(0, 100 - actual)
                let candidate = remaining / rate
                if candidate >= timeUntilReset {
                    lasts = true
                } else {
                    eta = candidate
                }
            }
        } else if elapsed > 0, actual == 0 {
            lasts = true
        }

        return UsagePace(
            stage: stage(for: delta),
            deltaPercent: delta,
            expectedPercent: expected,
            actualPercent: actual,
            etaUntilExhaustion: eta,
            lastsToReset: lasts
        )
    }

    private static func stage(for delta: Double) -> PaceStage {
        let magnitude = abs(delta)
        if magnitude <= 2 { return .onTrack }
        if magnitude <= 6 { return delta > 0 ? .slightDeficit : .slightReserve }
        if magnitude <= 12 { return delta > 0 ? .moderateDeficit : .moderateReserve }
        return delta > 0 ? .severeDeficit : .deepReserve
    }
}

private func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
    min(max(value, lower), upper)
}
