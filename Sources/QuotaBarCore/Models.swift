import Foundation

public enum ProviderID: String, Codable, CaseIterable, Hashable, Sendable {
    case openAI
    case anthropic

    public var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        }
    }

    public var shortName: String {
        switch self {
        case .openAI: "OAI"
        case .anthropic: "ANTH"
        }
    }
}

public enum MetricSource: String, Codable, Equatable, Sendable {
    case oauth
    case localHistory
    case cache
}

public struct UsageWindow: Codable, Equatable, Sendable {
    public let label: String
    public let usedPercent: Double
    public let sourceWindowMinutes: Int?
    public let resetsAt: Date?
    public let source: MetricSource
    public let note: String?

    public init(
        label: String,
        usedPercent: Double,
        sourceWindowMinutes: Int?,
        resetsAt: Date?,
        source: MetricSource,
        note: String? = nil
    ) {
        self.label = label
        self.usedPercent = usedPercent
        self.sourceWindowMinutes = sourceWindowMinutes
        self.resetsAt = resetsAt
        self.source = source
        self.note = note
    }

    public var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }
}

public struct ReserveMetric: Codable, Equatable, Sendable {
    public let remaining: Double
    public let limit: Double?
    public let unit: String
    public let resetsAt: Date?
    public let source: MetricSource
    public let note: String?

    public init(
        remaining: Double,
        limit: Double?,
        unit: String,
        resetsAt: Date?,
        source: MetricSource,
        note: String? = nil
    ) {
        self.remaining = remaining
        self.limit = limit
        self.unit = unit
        self.resetsAt = resetsAt
        self.source = source
        self.note = note
    }
}

public struct ProviderSnapshot: Codable, Equatable, Sendable {
    public let provider: ProviderID
    public let daily: UsageWindow?
    public let weekly: UsageWindow?
    public let reserve: ReserveMetric?
    public let source: String
    public let fetchedAt: Date
    public let warning: String?

    public init(
        provider: ProviderID,
        daily: UsageWindow?,
        weekly: UsageWindow?,
        reserve: ReserveMetric?,
        source: String,
        fetchedAt: Date,
        warning: String? = nil
    ) {
        self.provider = provider
        self.daily = daily
        self.weekly = weekly
        self.reserve = reserve
        self.source = source
        self.fetchedAt = fetchedAt
        self.warning = warning
    }
}

public struct SnapshotEnvelope: Codable, Equatable, Sendable {
    public let snapshots: [ProviderSnapshot]

    public init(snapshots: [ProviderSnapshot]) {
        self.snapshots = snapshots
    }
}
