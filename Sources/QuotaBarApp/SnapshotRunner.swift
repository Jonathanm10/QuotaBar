import AppKit
import SwiftUI
import QuotaBarCore

@MainActor
enum SnapshotRunner {
    static func render(to path: String) {
        let state = AppState()
        let now = Date()
        state.apply(mockSnapshot(
            .openAI,
            dailyPct: 34, dailyResetIn: 4 * 3600 + 10 * 60,
            weeklyPct: 61, weeklyResetIn: 3 * 86400 + 4 * 3600,
            now: now
        ))
        state.apply(mockSnapshot(
            .anthropic,
            dailyPct: 72, dailyResetIn: 2 * 3600 + 40 * 60,
            weeklyPct: 88, weeklyResetIn: 86400 + 9 * 3600,
            now: now
        ))
        state.lastRefreshAt = now.addingTimeInterval(-8)

        let view = DashboardView(state: state, preferences: Preferences.shared, onRefresh: {}, onQuit: {})
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0
        renderer.isOpaque = true

        guard let image = renderer.nsImage else {
            FileHandle.standardError.write(Data("snapshot: renderer returned nil\n".utf8))
            return
        }
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            FileHandle.standardError.write(Data("snapshot: could not encode PNG\n".utf8))
            return
        }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("snapshot: wrote \(path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        } catch {
            FileHandle.standardError.write(Data("snapshot: write failed: \(error)\n".utf8))
        }
    }

    private static func mockSnapshot(
        _ provider: ProviderID,
        dailyPct: Double,
        dailyResetIn: TimeInterval,
        weeklyPct: Double,
        weeklyResetIn: TimeInterval,
        now: Date
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: provider,
            daily: UsageWindow(
                label: "5h",
                usedPercent: dailyPct,
                sourceWindowMinutes: 300,
                resetsAt: now.addingTimeInterval(dailyResetIn),
                source: .oauth
            ),
            weekly: UsageWindow(
                label: "7d",
                usedPercent: weeklyPct,
                sourceWindowMinutes: 7 * 24 * 60,
                resetsAt: now.addingTimeInterval(weeklyResetIn),
                source: .oauth
            ),
            reserve: nil,
            source: "oauth",
            fetchedAt: now
        )
    }
}
