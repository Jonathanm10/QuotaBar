import SwiftUI
import QuotaBarCore

struct DashboardView: View {
    @Bindable var state: AppState
    @Bindable var preferences: Preferences
    var onRefresh: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            content
            hairline
            footer
        }
        .frame(width: 380)
        .background(
            LinearGradient(
                colors: [QBColor.bgTop, QBColor.bgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .preferredColorScheme(.dark)
    }

    private var hairline: some View {
        Rectangle().fill(QBColor.line).frame(height: 1)
    }

    private var header: some View {
        HStack(spacing: 10) {
            LiveDot(isActive: state.isPopoverPresented)
            Text("QuotaBar")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(QBColor.ink)
            Spacer()
            RefreshButton(
                isRefreshing: state.isRefreshing,
                isVisible: state.isPopoverPresented,
                action: onRefresh
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private var content: some View {
        if state.orderedSnapshots.isEmpty {
            EmptyStateView(isRefreshing: state.isRefreshing, error: state.lastError)
        } else {
            VStack(spacing: 10) {
                ForEach(state.orderedSnapshots, id: \.provider) { snapshot in
                    ProviderCardView(snapshot: snapshot, showRemaining: preferences.showPercentRemaining)
                }
                if let warning = state.lastError {
                    WarningBanner(text: warning)
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            PulseDot(isActive: state.isPopoverPresented)
            Text(state.lastRefreshAt.map { "Updated \(Formatting.ageSummary($0))" } ?? "Not yet refreshed")
                .font(.system(size: 11))
                .foregroundStyle(QBColor.ink3)
            Spacer()
            PaceMarkerLegend()
            Button("", action: onQuit)
                .buttonStyle(.plain)
                .keyboardShortcut("q", modifiers: [.command])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityLabel("Quit QuotaBar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - Provider card (bar layout)

struct ProviderCardView: View {
    let snapshot: ProviderSnapshot
    let showRemaining: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(spacing: 8) {
                    BarRow(title: "Daily", window: snapshot.daily, now: context.date, showRemaining: showRemaining)
                    BarRow(title: "Weekly", window: snapshot.weekly, now: context.date, showRemaining: showRemaining)
                    if let warning = snapshot.warning {
                        WarningBanner(text: warning)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [QBColor.panelTop, QBColor.panelBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(QBColor.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProviderLogoChip(provider: snapshot.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.provider.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(QBColor.ink)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(subtitle(now: context.date))
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(QBColor.ink3)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                worstBadge
            }
        }
    }

    private var worstUsed: Double {
        max(snapshot.daily?.usedPercent ?? 0, snapshot.weekly?.usedPercent ?? 0)
    }

    private var badgeValue: Double {
        showRemaining ? max(0, 100 - worstUsed) : worstUsed
    }

    private var worstBadge: some View {
        Text("\(Int(badgeValue.rounded()))%")
            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(QBColor.ink)
    }

    private func subtitle(now: Date) -> String {
        let sourceTag = snapshot.source.uppercased()
        let paces = [snapshot.daily, snapshot.weekly]
            .compactMap { $0 }
            .compactMap { UsagePace.compute(window: $0, now: now) }
        guard let worst = paces.max(by: { $0.deltaPercent < $1.deltaPercent }) else {
            return sourceTag
        }
        let phrase: String = switch worst.stage {
        case .onTrack: "on pace"
        case .slightReserve, .moderateReserve, .deepReserve: "banking reserve"
        case .slightDeficit, .moderateDeficit, .severeDeficit: "burning fast"
        }
        return "\(sourceTag) · \(phrase)"
    }
}

// MARK: - Bar row

struct BarRow: View {
    let title: String
    let window: UsageWindow?
    let now: Date
    let showRemaining: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(QBColor.ink3)
                .frame(width: 48, alignment: .leading)
            BarTrack(window: window, now: now, showRemaining: showRemaining)
                .frame(maxWidth: .infinity)
            PaceMeta(window: window, now: now)
                .frame(width: 92, alignment: .trailing)
        }
    }
}

struct BarTrack: View {
    let window: UsageWindow?
    let now: Date
    let showRemaining: Bool

    private var usedPct: Double { clamp01(window?.usedPercent ?? 0, hi: 100) }
    private var displayPct: Double { showRemaining ? 100 - usedPct : usedPct }
    private var expected: Double? {
        guard let window, let pace = UsagePace.compute(window: window, now: now) else { return nil }
        let raw = pace.expectedPercent
        return showRemaining ? max(0, 100 - raw) : raw
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillWidth = max(0, w * displayPct / 100)
            let tickX: CGFloat? = expected.map { max(0, w * $0 / 100) - 1 }
            let fillColor = window == nil ? QBColor.ink3.opacity(0.35) : UsageColor.forUsedPercent(usedPct)

            ZStack(alignment: .leading) {
                // 7px track, vertically centered inside the 13px row
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(QBColor.trackBg)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(QBColor.line, lineWidth: 1)
                        )
                    Capsule(style: .continuous)
                        .fill(fillColor)
                        .frame(width: fillWidth)
                        .animation(.easeInOut(duration: 0.55), value: displayPct)
                }
                .frame(height: 7)
                .clipShape(Capsule(style: .continuous))

                // pace tick — 2×13 extending above/below the track
                if let tickX {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 2, height: 13)
                        .shadow(color: Color.white.opacity(0.2), radius: 1.5)
                        .offset(x: tickX)
                        .animation(.easeInOut(duration: 0.55), value: tickX)
                }
            }
            .frame(height: 13)
        }
        .frame(height: 13)
    }
}

struct PaceMeta: View {
    let window: UsageWindow?
    let now: Date

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            deltaLine
            etaLine
        }
    }

    private var pace: UsagePace? {
        guard let window else { return nil }
        return UsagePace.compute(window: window, now: now)
    }

    private var isStale: Bool {
        guard let window, let reset = window.resetsAt else { return false }
        return reset <= now
    }

    @ViewBuilder
    private var deltaLine: some View {
        if isStale {
            Text("Stale")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(QBColor.warn)
        } else if let pace {
            Text(Formatting.paceLabel(pace))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(PaceColor.forStage(pace.stage))
        } else {
            Text("—")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(QBColor.ink3)
        }
    }

    @ViewBuilder
    private var etaLine: some View {
        if let text = etaText {
            Text(text)
                .font(.system(size: 10, design: .rounded).monospacedDigit())
                .foregroundStyle(QBColor.ink3)
                .lineLimit(1)
        }
    }

    private var etaText: String? {
        if isStale, let reset = window?.resetsAt {
            return "reset \(Formatting.shortDuration(now.timeIntervalSince(reset))) ago"
        }
        if let pace, let eta = pace.etaUntilExhaustion {
            return "out \(Formatting.shortDuration(eta))"
        }
        if let reset = window?.resetsAt {
            return "until \(Formatting.shortDuration(reset.timeIntervalSince(now)))"
        }
        return nil
    }
}

// MARK: - Refresh button

struct RefreshButton: View {
    let isRefreshing: Bool
    let isVisible: Bool
    let action: () -> Void
    @State private var clickBump: Double = 0

    private var shouldSpin: Bool { isRefreshing && isVisible }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.55)) { clickBump += 360 }
            action()
        } label: {
            Group {
                if shouldSpin {
                    SpinningRefreshIcon(bump: clickBump)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.small)
                        .foregroundStyle(QBColor.ink2)
                        .rotationEffect(.degrees(clickBump))
                }
            }
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(QBColor.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .keyboardShortcut("r", modifiers: [.command])
        .help("Refresh now (⌘R)")
    }
}

private struct SpinningRefreshIcon: View {
    let bump: Double
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let degrees = elapsed / 0.9 * 360
            Image(systemName: "arrow.clockwise")
                .imageScale(.small)
                .foregroundStyle(QBColor.ink2)
                .rotationEffect(.degrees(degrees + bump))
        }
    }
}

// MARK: - Chips, pills, dots

struct ProviderLogoChip: View {
    let provider: ProviderID

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(chipColor)
            BrandLogoView(provider: provider, size: 15)
                .foregroundStyle(Color.white)
        }
        .frame(width: 24, height: 24)
    }

    private var chipColor: Color {
        switch provider {
        case .openAI: QBColor.oaiChip
        case .anthropic: QBColor.antChip
        }
    }
}

struct LiveDot: View {
    let isActive: Bool
    @State private var lit = false

    var body: some View {
        Circle()
            .fill(QBColor.ok)
            .frame(width: 8, height: 8)
            .shadow(color: QBColor.ok.opacity(lit ? 0.7 : 0.25), radius: lit ? 5 : 2)
            .onAppear { self.updateAnimation(for: self.isActive) }
            .onChange(of: isActive) { _, now in self.updateAnimation(for: now) }
    }

    private func updateAnimation(for active: Bool) {
        if active {
            lit = false
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                lit = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                lit = false
            }
        }
    }
}

struct PulseDot: View {
    let isActive: Bool
    @State private var on = false

    var body: some View {
        Circle()
            .fill(QBColor.accent)
            .frame(width: 6, height: 6)
            .opacity(on ? 1 : 0.35)
            .onAppear { self.updateAnimation(for: self.isActive) }
            .onChange(of: isActive) { _, now in self.updateAnimation(for: now) }
    }

    private func updateAnimation(for active: Bool) {
        if active {
            on = false
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                on = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                on = false
            }
        }
    }
}

struct PaceMarkerLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.55))
                .frame(width: 2, height: 10)
            Text("on-pace marker")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(QBColor.ink3)
        }
    }
}

struct WarningBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(QBColor.warn)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct EmptyStateView: View {
    let isRefreshing: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .imageScale(.large)
                .foregroundStyle(QBColor.ink3)
            Text("No data yet")
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(QBColor.ink)
            Text(isRefreshing ? "Fetching first snapshot…" : "Waiting for initial refresh.")
                .font(.system(size: 11))
                .foregroundStyle(QBColor.ink3)
            if let error {
                WarningBanner(text: error)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 44)
    }
}

// MARK: - Palette

private enum QBColor {
    static let bgTop = Color(red: 20 / 255, green: 22 / 255, blue: 27 / 255)
    static let bgBottom = Color(red: 16 / 255, green: 18 / 255, blue: 23 / 255)
    static let panelTop = Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255)
    static let panelBottom = Color(red: 27 / 255, green: 30 / 255, blue: 36 / 255)
    static let line = Color(red: 36 / 255, green: 39 / 255, blue: 47 / 255)
    static let trackBg = Color(red: 12 / 255, green: 14 / 255, blue: 21 / 255)
    static let ink = Color(red: 238 / 255, green: 240 / 255, blue: 243 / 255)
    static let ink2 = Color(red: 155 / 255, green: 162 / 255, blue: 173 / 255)
    static let ink3 = Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255)
    static let ok = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let warn = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    static let hot = Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255)
    static let crit = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    static let oaiChip = Color(red: 16 / 255, green: 163 / 255, blue: 127 / 255)
    static let antChip = Color(red: 217 / 255, green: 119 / 255, blue: 87 / 255)
    static let accent = Color(red: 96 / 255, green: 165 / 255, blue: 250 / 255)
}

enum UsageColor {
    static func forUsedPercent(_ used: Double) -> Color {
        used >= 80 ? QBColor.crit : QBColor.ink2
    }
}

enum PaceColor {
    static func forStage(_ stage: PaceStage) -> Color {
        switch stage {
        case .moderateDeficit, .severeDeficit: QBColor.crit
        default: QBColor.ink2
        }
    }
}

private func clamp01(_ value: Double, hi: Double = 1) -> Double {
    min(max(value, 0), hi)
}
