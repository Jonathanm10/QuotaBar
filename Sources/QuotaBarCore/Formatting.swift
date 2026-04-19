import Foundation

public enum Formatting {
    private static func relativeFormatter() -> RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }

    private static func absoluteFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    public static func percentString(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    public static func usageSummary(window: UsageWindow?) -> String {
        guard let window else { return "Unavailable" }
        let note = window.sourceWindowMinutes.map { " (\($0 / 60)h source)" } ?? ""
        return "\(percentString(window.usedPercent)) used [\(window.source.rawValue)]\(note)"
    }

    public static func reserveSummary(metric: ReserveMetric?) -> String {
        guard let metric else { return "Unavailable" }
        if let limit = metric.limit, limit > 0 {
            return "\(numberString(metric.remaining)) / \(numberString(limit)) \(metric.unit) [\(metric.source.rawValue)]"
        }
        return "\(numberString(metric.remaining)) \(metric.unit) [\(metric.source.rawValue)]"
    }

    public static func resetSummary(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return "\(relativeFormatter().localizedString(for: date, relativeTo: Date())) (\(absoluteFormatter().string(from: date)))"
    }

    public static func ageSummary(_ date: Date) -> String {
        relativeFormatter().localizedString(for: date, relativeTo: Date())
    }

    public static func compactUsage(
        _ snapshot: ProviderSnapshot,
        includesWeekly: Bool = true,
        showRemaining: Bool = false
    ) -> String {
        let dailyText = formatPercent(snapshot.daily?.usedPercent, showRemaining: showRemaining)
        guard includesWeekly else { return dailyText }
        let weeklyText = formatPercent(snapshot.weekly?.usedPercent, showRemaining: showRemaining)
        return "\(dailyText)/\(weeklyText)"
    }

    private static func formatPercent(_ used: Double?, showRemaining: Bool) -> String {
        guard let used else { return "—" }
        let value = showRemaining ? max(0, 100 - used) : used
        return "\(Int(value.rounded()))%"
    }

    public static func paceLabel(_ pace: UsagePace?) -> String {
        guard let pace else { return "—" }
        let magnitude = Int(abs(pace.deltaPercent).rounded())
        switch pace.stage {
        case .onTrack: return "On pace"
        case .slightReserve, .moderateReserve, .deepReserve:
            return "Reserve +\(magnitude)%"
        case .slightDeficit, .moderateDeficit, .severeDeficit:
            return "Deficit -\(magnitude)%"
        }
    }

    public static func paceDetail(_ pace: UsagePace?) -> String? {
        guard let pace else { return nil }
        if pace.lastsToReset { return "Lasts to reset" }
        if let eta = pace.etaUntilExhaustion {
            return "Runs out in \(shortDuration(eta))"
        }
        return nil
    }

    public static func shortDuration(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds / 60)
        if totalMinutes < 60 { return "\(max(0, totalMinutes))m" }
        let hours = totalMinutes / 60
        if hours < 48 {
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
        }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? "\(days)d" : "\(days)d\(remHours)h"
    }

    private static func numberString(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.005 {
            return String(Int(value.rounded()))
        }
        return String(format: "%.2f", value)
    }
}
