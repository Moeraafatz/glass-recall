import AppKit
import Foundation
import GlassRecallCore
import Observation

public enum RecallTab: String, CaseIterable, Identifiable, Sendable {
    case search = "Search"
    case timeline = "Timeline"
    case insights = "Insights"
    case privacy = "Privacy"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .timeline: return "clock.arrow.circlepath"
        case .insights: return "chart.xyaxis.line"
        case .privacy: return "shield.lefthalf.filled"
        }
    }

    public var shortcut: String {
        switch self {
        case .search: return "⌘1"
        case .timeline: return "⌘2"
        case .insights: return "⌘3"
        case .privacy: return "⌘4"
        }
    }
}

@MainActor
@Observable
public final class AppState {
    public var selectedTab: RecallTab = .search
    public var queryText: String = ""
    public var selectedAppFilter: String? = nil
    public var dateRange: DateRangeFilter = .all
    public var hits: [SearchHit] = []
    public var recentRecords: [MemoryRecord] = []
    public var appBuckets: [AppActivityBucket] = []
    public var hourlyActivity: [HourlyActivityPoint] = []
    public var stats: CaptureStats = CaptureStats()
    public var config: RecallConfig = .default
    public var hasScreenPermission: Bool = false
    public var hasAccessibilityPermission: Bool = false
    public var statusToast: String? = nil
    public var newExclusionInput: String = ""
    public let isPreviewSnapshot: Bool

    private let store: MemoryStore?
    private let captureEngine: CaptureEngine?
    private var searchTask: Task<Void, Never>?

    public init(store: MemoryStore? = nil, isPreviewSnapshot: Bool = false) {
        self.store = store
        self.isPreviewSnapshot = isPreviewSnapshot
        if let store {
            self.captureEngine = CaptureEngine(store: store, config: .default)
        } else {
            self.captureEngine = nil
        }
        if !isPreviewSnapshot {
            refreshPermissions()
        }
    }

    public static func demo(tab: RecallTab = .search, query: String = "sqlite wal fts5") -> AppState {
        let state = AppState(store: nil, isPreviewSnapshot: true)
        state.selectedTab = tab
        state.queryText = query
        state.hits = SampleData.demoSearchHits()
        state.recentRecords = SampleData.demoRecords()
        state.stats = SampleData.demoStats()
        state.appBuckets = SampleData.demoAppBuckets()
        state.hourlyActivity = SampleData.demoHourlyActivity()
        state.hasScreenPermission = true
        state.hasAccessibilityPermission = true
        return state
    }

    public func bootstrap() async {
        guard !isPreviewSnapshot, let captureEngine else { return }
        refreshPermissions()
        await captureEngine.setOnStatsUpdate { [weak self] newStats in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let lastMs = self.stats.lastSearchMs
                var merged = newStats
                merged.lastSearchMs = lastMs
                self.stats = merged
            }
        }
        await reloadAll()
        if hasScreenPermission {
            await captureEngine.start()
        }
    }

    public func refreshPermissions() {
        hasScreenPermission = ContextInspector.hasScreenRecordingPermission()
        hasAccessibilityPermission = ContextInspector.hasAccessibilityPermission()
    }

    public func requestScreenPermission() {
        ContextInspector.requestScreenRecordingPermission()
        ContextInspector.openScreenRecordingSettings()
        refreshPermissions()
    }

    public func openAccessibilitySettings() {
        ContextInspector.openAccessibilitySettings()
        refreshPermissions()
    }

    public func toggleCapture() {
        guard let captureEngine else {
            stats.isCapturing.toggle()
            return
        }
        Task {
            if stats.isCapturing && stats.pausedUntil == nil {
                await captureEngine.stop()
            } else {
                refreshPermissions()
                if hasScreenPermission {
                    await captureEngine.resume()
                } else {
                    requestScreenPermission()
                }
            }
            await reloadAll()
        }
    }

    public func pauseCapture(minutes: Int) {
        guard let captureEngine else {
            stats.pausedUntil = Date().addingTimeInterval(Double(minutes) * 60)
            return
        }
        Task {
            await captureEngine.pause(minutes: minutes)
            showToast("Paused capture for \(minutes)m")
        }
    }

    public func triggerSearch() {
        guard !isPreviewSnapshot else { return }
        searchTask?.cancel()
        let q = SearchQuery(text: queryText, appFilter: selectedAppFilter, dateRange: dateRange, limit: 40)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled, let store else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            if let results = try? await store.search(q) {
                let elapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
                self.hits = results
                self.stats.lastSearchMs = elapsed
            }
        }
    }

    public func reloadAll() async {
        guard !isPreviewSnapshot, let store else { return }
        let t0 = CFAbsoluteTimeGetCurrent()
        let q = SearchQuery(text: queryText, appFilter: selectedAppFilter, dateRange: dateRange, limit: 40)
        if let results = try? await store.search(q) {
            hits = results
            stats.lastSearchMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        }
        if let recent = try? await store.fetchRecent(limit: 40) {
            recentRecords = recent
        }
        if let buckets = try? await store.appBreakdown(limit: 6) {
            appBuckets = buckets
        }
        if let hourly = try? await store.hourlyActivity(lastHours: 12) {
            hourlyActivity = hourly
        }
        if let captureEngine {
            let liveStats = await captureEngine.currentStats()
            let lastMs = stats.lastSearchMs
            var merged = liveStats
            merged.lastSearchMs = lastMs
            stats = merged
        }
    }

    public func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Copied text to clipboard")
    }

    public func openURL(_ urlString: String?) {
        guard let urlString, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    public func deleteMemory(id: Int64) {
        guard let store else {
            hits.removeAll { $0.id == id }
            recentRecords.removeAll { $0.id == id }
            return
        }
        Task {
            try? await store.delete(id: id)
            await reloadAll()
            showToast("Deleted memory entry")
        }
    }

    public func purgeRecent(minutes: Int) {
        guard let store else {
            showToast("Purged last \(minutes)m")
            return
        }
        Task {
            let removed = (try? await store.purgeRecent(minutes: minutes)) ?? 0
            await reloadAll()
            showToast("Purged \(removed) memories from last \(minutes)m")
        }
    }

    public func wipeAllMemories() {
        guard let store else {
            hits.removeAll()
            recentRecords.removeAll()
            return
        }
        Task {
            try? await store.wipeAll()
            await reloadAll()
            showToast("All local memory wiped")
        }
    }

    public func updateConfig(_ mutate: (inout RecallConfig) -> Void) {
        mutate(&config)
        guard let captureEngine else { return }
        let updated = config
        Task {
            await captureEngine.updateConfig(updated)
        }
    }

    public func addCustomExclusion() {
        let trimmed = newExclusionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateConfig { cfg in
            if !cfg.excludedTitleKeywords.contains(trimmed) {
                cfg.excludedTitleKeywords.append(trimmed)
            }
        }
        newExclusionInput = ""
        showToast("Blocked keyword \"\(trimmed)\"")
    }

    public func showToast(_ message: String) {
        statusToast = message
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if statusToast == message {
                statusToast = nil
            }
        }
    }
}
