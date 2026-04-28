import AppKit
import SwiftUI
import QuotaBarCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let state = AppState()
    private let preferences = Preferences.shared
    private let snapshotStore = SnapshotStore()
    private let refreshCoordinator = RefreshCoordinator(providers: [
        OpenAIProvider(),
        AnthropicProvider(),
    ])

    private var refreshTimer: Timer?
    private var popoverMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        self.configureStatusItem()
        self.configurePopover()

        Task {
            await self.loadCachedSnapshots()
            if StartupRefreshGate.shouldRefresh(cachedSnapshots: self.state.orderedSnapshots) {
                await self.refresh(trigger: .startup)
            }
        }

        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { await self.refresh(trigger: .timer) }
        }
        self.refreshTimer?.tolerance = 30
    }

    func applicationWillTerminate(_ notification: Notification) {
        self.refreshTimer?.invalidate()
        self.removePopoverMonitor()
    }

    // MARK: - Setup

    private func configureStatusItem() {
        guard let button = self.statusItem.button else { return }
        button.image = nil
        button.title = ""
        button.target = self
        button.action = #selector(self.handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "QuotaBar — OpenAI & Anthropic usage"
        self.updateStatusBar()
    }

    private func configurePopover() {
        self.popover.delegate = self
        self.popover.behavior = .transient
        self.popover.animates = true
        self.popover.contentSize = NSSize(width: 380, height: 380)
        let root = DashboardView(
            state: self.state,
            preferences: self.preferences,
            onRefresh: { [weak self] in
                guard let self else { return }
                Task { await self.refresh(trigger: .manual) }
            },
            onQuit: { NSApp.terminate(nil) }
        )
        self.popover.contentViewController = NSHostingController(rootView: root)
    }

    // MARK: - Status item interaction

    @objc
    private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) == true)
        if isRightClick {
            self.showContextMenu()
            return
        }
        self.togglePopover(sender: sender)
    }

    private func togglePopover(sender: NSStatusBarButton) {
        if self.popover.isShown {
            self.popover.performClose(nil)
            return
        }
        self.popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        self.installPopoverMonitor()
        if self.shouldRefreshOnOpen() {
            Task { await self.refresh(trigger: .menuOpen) }
        }
    }

    private func installPopoverMonitor() {
        self.removePopoverMonitor()
        self.popoverMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.popover.isShown {
                    self.popover.performClose(nil)
                    self.removePopoverMonitor()
                }
            }
        }
    }

    private func removePopoverMonitor() {
        if let monitor = self.popoverMonitor {
            NSEvent.removeMonitor(monitor)
            self.popoverMonitor = nil
        }
    }

    func popoverDidShow(_ notification: Notification) {
        self.state.isPopoverPresented = true
    }

    func popoverDidClose(_ notification: Notification) {
        self.state.isPopoverPresented = false
        self.removePopoverMonitor()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(self.handleManualRefresh), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        menu.addItem(.separator())

        let weeklyItem = NSMenuItem(
            title: "Show Weekly in Menu Bar",
            action: #selector(self.handleToggleWeeklyInStatusBar),
            keyEquivalent: ""
        )
        weeklyItem.target = self
        weeklyItem.state = self.preferences.showWeeklyInStatusBar ? .on : .off
        menu.addItem(weeklyItem)

        let remainingItem = NSMenuItem(
            title: "Show Percent Remaining",
            action: #selector(self.handleTogglePercentRemaining),
            keyEquivalent: ""
        )
        remainingItem.target = self
        remainingItem.state = self.preferences.showPercentRemaining ? .on : .off
        menu.addItem(remainingItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit QuotaBar", action: #selector(self.handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        self.statusItem.menu = menu
        self.statusItem.button?.performClick(nil)
        self.statusItem.menu = nil
    }

    private func shouldRefreshOnOpen() -> Bool {
        let oldest = self.state.snapshots.values.map(\.fetchedAt).min() ?? .distantPast
        return Date().timeIntervalSince(oldest) > 30
    }

    // MARK: - Data

    private func loadCachedSnapshots() async {
        do {
            let loaded = try await self.snapshotStore.load()
            let cached = loaded.map(self.asCachedSnapshot(_:))
            for snapshot in cached {
                self.state.apply(snapshot)
            }
            self.state.lastRefreshAt = cached.map(\.fetchedAt).max()
            self.updateStatusBar()
        } catch {
            AppLog.cache.error("Failed to load cache")
            self.state.lastError = "Cache unreadable"
        }
    }

    private func refresh(trigger: RefreshTrigger) async {
        AppLog.refresh.info("Refreshing snapshots: \(trigger.rawValue, privacy: .public)")
        self.state.isRefreshing = true
        defer { self.state.isRefreshing = false }

        let report = await self.refreshCoordinator.refreshAll(trigger: trigger)
        for failure in report.failures {
            if let cached = self.state.snapshots[failure.provider] {
                self.state.apply(cached.markingRefreshFailure(failure))
            }
        }

        guard !report.snapshots.isEmpty || !report.failures.isEmpty else { return }
        for snapshot in report.snapshots {
            self.state.apply(snapshot)
        }
        if !report.snapshots.isEmpty {
            self.state.lastRefreshAt = Date()
        }
        self.state.lastError = self.errorSummary(for: report.failures)
        let snapshots = self.state.orderedSnapshots
        if !report.snapshots.isEmpty {
            do {
                try await self.snapshotStore.save(snapshots)
            } catch {
                AppLog.cache.error("Failed to save cache")
            }
        }
        self.updateStatusBar()
    }

    private func errorSummary(for failures: [ProviderRefreshFailure]) -> String? {
        guard !failures.isEmpty else { return nil }
        let details = failures
            .map { "\($0.provider.displayName) refresh failed: \($0.message)" }
            .joined(separator: "\n")
        return "\(details)\nShowing cached values."
    }

    private func asCachedSnapshot(_ snapshot: ProviderSnapshot) -> ProviderSnapshot {
        ProviderSnapshot(
            provider: snapshot.provider,
            daily: snapshot.daily.map { cachedWindow in
                UsageWindow(
                    label: cachedWindow.label,
                    usedPercent: cachedWindow.usedPercent,
                    sourceWindowMinutes: cachedWindow.sourceWindowMinutes,
                    resetsAt: cachedWindow.resetsAt,
                    source: .cache,
                    note: cachedWindow.note
                )
            },
            weekly: snapshot.weekly.map { cachedWindow in
                UsageWindow(
                    label: cachedWindow.label,
                    usedPercent: cachedWindow.usedPercent,
                    sourceWindowMinutes: cachedWindow.sourceWindowMinutes,
                    resetsAt: cachedWindow.resetsAt,
                    source: .cache,
                    note: cachedWindow.note
                )
            },
            reserve: nil,
            source: "cache",
            fetchedAt: snapshot.fetchedAt,
            warning: snapshot.warning
        )
    }

    private func updateStatusBar() {
        guard let button = self.statusItem.button else { return }
        let snapshots = self.state.orderedSnapshots
        let image = StatusBarRenderer.render(
            snapshots: snapshots,
            includesWeekly: self.preferences.showWeeklyInStatusBar,
            showRemaining: self.preferences.showPercentRemaining
        )
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
    }

    // MARK: - Actions

    @objc
    private func handleManualRefresh() {
        Task { await self.refresh(trigger: .manual) }
    }

    @objc
    private func handleToggleWeeklyInStatusBar() {
        self.preferences.showWeeklyInStatusBar.toggle()
        self.updateStatusBar()
    }

    @objc
    private func handleTogglePercentRemaining() {
        self.preferences.showPercentRemaining.toggle()
        self.updateStatusBar()
    }

    @objc
    private func handleQuit() {
        NSApp.terminate(nil)
    }
}
