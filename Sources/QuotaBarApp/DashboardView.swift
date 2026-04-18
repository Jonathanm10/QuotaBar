import SwiftUI
import QuotaBarCore

struct DashboardView: View {
    @Bindable var state: AppState
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
            EmptyStateView(isRefreshing: state.isRefreshing)
        } else {
            VStack(spacing: 10) {
                ForEach(state.orderedSnapshots, id: \.provider) { snapshot in
                    ProviderCardView(snapshot: snapshot)
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
            Legend()
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

// MARK: - Provider Card

struct ProviderCardView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProviderLogoChip(provider: snapshot.provider)
                Text(snapshot.provider.displayName)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .foregroundStyle(QBColor.ink)
                Spacer()
                SourcePill(text: snapshot.source)
            }

            HStack(alignment: .center, spacing: 10) {
                GaugePanel(title: "Daily", window: snapshot.daily)
                Rectangle()
                    .fill(QBColor.line)
                    .frame(width: 1, height: 64)
                GaugePanel(title: "Weekly", window: snapshot.weekly)
            }
        }
        .padding(12)
        .background(
            ZStack {
                LinearGradient(
                    colors: [QBColor.panelTop, QBColor.panelBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
                GridBackground()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(QBColor.line, lineWidth: 1)
        )
    }
}

struct GaugePanel: View {
    let title: String
    let window: UsageWindow?

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            GaugeRing(
                percent: window?.usedPercent ?? 0,
                color: UsageColor.forUsedPercent(window?.usedPercent ?? 0),
                hasData: window != nil
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(QBColor.ink2)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let pace = window.flatMap { UsagePace.compute(window: $0, now: context.date) }
                    let stale = isStale(now: context.date)
                    VStack(alignment: .leading, spacing: 3) {
                        paceLine(pace: pace, stale: stale)
                        metaLines(pace: pace, now: context.date, stale: stale)
                    }
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func paceLine(pace: UsagePace?, stale: Bool) -> some View {
        if stale {
            Text("Stale")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(QBColor.warn)
        } else if let pace {
            Text(Formatting.paceLabel(pace))
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(PaceColor.forStage(pace.stage))
        } else {
            Text("—")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(QBColor.ink3)
        }
    }

    @ViewBuilder
    private func metaLines(pace: UsagePace?, now: Date, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let runOut = runOutSummary(pace: pace) {
                Text(runOut)
                    .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                    .foregroundStyle(QBColor.ink3)
            }
            if let reset = resetSummary(now: now, stale: stale) {
                Text(reset)
                    .font(.system(size: 10.5, design: .rounded).monospacedDigit())
                    .foregroundStyle(stale ? QBColor.warn : QBColor.ink3)
            }
        }
    }

    private func isStale(now: Date) -> Bool {
        guard let window, let reset = window.resetsAt else { return false }
        return reset <= now
    }

    private func resetSummary(now: Date, stale: Bool) -> String? {
        guard let window, let reset = window.resetsAt else { return nil }
        if stale { return "reset " + Formatting.shortDuration(now.timeIntervalSince(reset)) + " ago" }
        return "reset " + Formatting.shortDuration(reset.timeIntervalSince(now))
    }

    private func runOutSummary(pace: UsagePace?) -> String? {
        guard let pace else { return nil }
        if pace.lastsToReset { return "lasts" }
        if let eta = pace.etaUntilExhaustion {
            return "out " + Formatting.shortDuration(eta)
        }
        return nil
    }
}

// MARK: - Gauge ring

struct GaugeRing: View {
    let percent: Double
    let color: Color
    let hasData: Bool
    var size: CGFloat = 54

    var body: some View {
        ZStack {
            Circle().fill(QBColor.ringTrack)
            PieArc(fraction: clamped / 100)
                .fill(color)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 19 / 255, green: 22 / 255, blue: 27 / 255),
                            Color(red: 15 / 255, green: 17 / 255, blue: 22 / 255),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Circle().strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
                )
                .padding(4)
            Group {
                if hasData {
                    Text("\(Int(clamped.rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(QBColor.ink)
                } else {
                    Text("—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(QBColor.ink3)
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(hasData ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.55), value: clamped)
    }

    private var clamped: Double { min(max(percent, 0), 100) }
}

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

struct PieArc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let f = min(max(fraction, 0), 1)
        guard f > 0 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * f),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Chips, pills, dots

struct ProviderLogoChip: View {
    let provider: ProviderID

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(chipColor)
            Text(letter)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(letterColor)
        }
        .frame(width: 22, height: 22)
    }

    private var letter: String {
        switch provider {
        case .openAI: "O"
        case .anthropic: "A"
        }
    }

    private var chipColor: Color {
        switch provider {
        case .openAI: QBColor.oaiChip
        case .anthropic: QBColor.antChip
        }
    }

    private var letterColor: Color {
        switch provider {
        case .openAI: Color(red: 0, green: 0, blue: 17 / 255)
        case .anthropic: Color(red: 42 / 255, green: 19 / 255, blue: 5 / 255)
        }
    }
}

struct SourcePill: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .tracking(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(QBColor.ink3)
            .background(
                Capsule().strokeBorder(QBColor.line, lineWidth: 0.5)
            )
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

struct Legend: View {
    var body: some View {
        HStack(spacing: 10) {
            legendItem(color: QBColor.ok, label: "ok")
            legendItem(color: QBColor.warn, label: "warn")
            legendItem(color: QBColor.crit, label: "crit")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
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
    }
}

struct EmptyStateView: View {
    let isRefreshing: Bool

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
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Grid background

struct GridBackground: View {
    var body: some View {
        Canvas { ctx, size in
            let step: CGFloat = 22
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += step
            }
            ctx.stroke(path, with: .color(Color.white.opacity(0.03)), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .opacity(0.55)
    }
}

// MARK: - Palette

private enum QBColor {
    static let bgTop = Color(red: 20 / 255, green: 22 / 255, blue: 27 / 255)
    static let bgBottom = Color(red: 16 / 255, green: 18 / 255, blue: 23 / 255)
    static let panelTop = Color(red: 22 / 255, green: 24 / 255, blue: 29 / 255)
    static let panelBottom = Color(red: 27 / 255, green: 30 / 255, blue: 36 / 255)
    static let line = Color(red: 36 / 255, green: 39 / 255, blue: 47 / 255)
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
    static let ringTrack = Color.white.opacity(0.07)
}

enum UsageColor {
    static func forUsedPercent(_ used: Double) -> Color {
        switch used {
        case ..<50: QBColor.ok
        case ..<75: QBColor.warn
        case ..<90: QBColor.hot
        default: QBColor.crit
        }
    }
}

enum PaceColor {
    static func forStage(_ stage: PaceStage) -> Color {
        switch stage {
        case .onTrack: QBColor.ink2
        case .slightReserve: QBColor.ok
        case .moderateReserve, .deepReserve: Color.mint
        case .slightDeficit: QBColor.warn
        case .moderateDeficit, .severeDeficit: QBColor.crit
        }
    }
}
