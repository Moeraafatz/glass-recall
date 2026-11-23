import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public actor CaptureEngine {
    private let store: MemoryStore
    private let differ: FrameDiffer
    private var config: RecallConfig
    private var loopTask: Task<Void, Never>?
    private var stats = CaptureStats()
    private var ocrSamplesCount: Int = 0
    private var ocrDurationSumMs: Double = 0
    private var onStatsUpdate: (@Sendable (CaptureStats) -> Void)?

    public init(store: MemoryStore, config: RecallConfig = .default) {
        self.store = store
        self.differ = FrameDiffer()
        self.config = config
    }

    public func setOnStatsUpdate(_ callback: (@Sendable (CaptureStats) -> Void)?) {
        self.onStatsUpdate = callback
    }

    public func updateConfig(_ newConfig: RecallConfig) {
        self.config = newConfig
    }

    public func currentStats() async -> CaptureStats {
        stats.totalMemories = (try? await store.totalCount()) ?? stats.totalMemories
        stats.databaseBytes = await store.databaseFileSizeBytes()
        stats.secretsRedacted = (try? await store.totalRedactedSecrets()) ?? stats.secretsRedacted
        return stats
    }

    public func start() {
        guard loopTask == nil else { return }
        stats.isCapturing = true
        stats.pausedUntil = nil
        emitStats()

        loopTask = Task { [weak self] in
            guard let self else { return }
            var idleBackoffMultiplier = 1.0
            while !Task.isCancelled {
                let processed = await self.captureOnce()
                idleBackoffMultiplier = processed ? 1.0 : min(3.0, idleBackoffMultiplier + 0.5)
                let baseInterval = await self.config.captureIntervalSeconds
                let sleepSec = max(1.5, baseInterval * idleBackoffMultiplier)
                try? await Task.sleep(for: .seconds(sleepSec))
            }
        }
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        stats.isCapturing = false
        emitStats()
    }

    public func pause(minutes: Int) {
        stats.pausedUntil = Date().addingTimeInterval(Double(minutes) * 60.0)
        emitStats()
    }

    public func resume() {
        stats.pausedUntil = nil
        if loopTask == nil {
            start()
        } else {
            emitStats()
        }
    }

    @discardableResult
    public func captureOnce() async -> Bool {
        if let pausedUntil = stats.pausedUntil {
            if Date() < pausedUntil {
                return false
            } else {
                stats.pausedUntil = nil
            }
        }

        if ContextInspector.isScreenLocked() || !ContextInspector.hasScreenRecordingPermission() {
            return false
        }

        guard let context = await MainActor.run(body: { ContextInspector.currentWindowContext() }) else {
            return false
        }

        // Skip our own app window
        if context.bundleID == Bundle.main.bundleIdentifier && !context.bundleID.isEmpty {
            return false
        }

        // Strict privacy gate BEFORE capturing a single pixel
        if config.isExcluded(bundleID: context.bundleID, windowTitle: context.windowTitle) {
            stats.framesBlockedByPrivacy += 1
            emitStats()
            return false
        }

        guard let cgImage = try? await Self.captureActiveImage(forPID: context.processID) else {
            return false
        }

        stats.framesEvaluated += 1
        let diff = differ.evaluate(image: cgImage, threshold: config.diffThreshold)
        if !diff.shouldProcess {
            stats.framesSkippedByDiff += 1
            emitStats()
            return false
        }

        // Run offline Vision OCR — cgImage is discarded immediately after this scope exits
        guard let ocr = try? OCREngine.recognize(image: cgImage, fastMode: config.fastOCRMode) else {
            return false
        }

        let sanitized = TextSanitizer.sanitize(ocr.text, redactSecrets: config.redactSecrets)
        guard sanitized.cleanText.count >= 12 else {
            return false
        }

        let resolvedURL = context.url ?? sanitized.extractedURLs.first
        let record = MemoryRecord(
            timestamp: Date(),
            appName: context.appName,
            bundleID: context.bundleID,
            windowTitle: context.windowTitle,
            url: resolvedURL,
            text: sanitized.cleanText,
            tags: sanitized.detectedTags,
            frameHash: diff.signature.dHash,
            ocrDurationMs: ocr.durationMs,
            redactedSecrets: sanitized.redactedCount
        )

        do {
            _ = try await store.insert(record)
            ocrSamplesCount += 1
            ocrDurationSumMs += ocr.durationMs
            stats.averageOcrMs = ocrDurationSumMs / Double(ocrSamplesCount)
            stats.totalMemories = (try? await store.totalCount()) ?? (stats.totalMemories + 1)
            stats.databaseBytes = await store.databaseFileSizeBytes()
            stats.secretsRedacted += sanitized.redactedCount

            // Periodically enforce retention policy
            if stats.totalMemories % 50 == 0 && config.retentionDays > 0 {
                _ = try? await store.pruneOlderThan(days: config.retentionDays)
            }
            emitStats()
            return true
        } catch {
            return false
        }
    }

    private func emitStats() {
        let snapshot = stats
        onStatsUpdate?(snapshot)
    }

    private static func captureActiveImage(forPID pid: Int32) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.scalesToFit = true

        if let activeWindow = content.windows.first(where: {
            $0.owningApplication?.processID == pid && $0.isOnScreen && $0.frame.width >= 200 && $0.frame.height >= 120
        }) {
            let filter = SCContentFilter(desktopIndependentWindow: activeWindow)
            config.width = min(Int(activeWindow.frame.width * 1.5), 1920)
            config.height = min(Int(activeWindow.frame.height * 1.5), 1200)
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        }

        guard let display = content.displays.first else {
            throw NSError(domain: "GlassRecall.Capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "No active display available"])
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        config.width = min(display.width, 1920)
        config.height = min(display.height, 1200)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
