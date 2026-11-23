import Foundation
import GlassRecallCore
import XCTest

final class GlassRecallTests: XCTestCase {
    func testFrameDifferSkipsIdenticalAndDetectsChange() throws {
        let frameA = try XCTUnwrap(BenchmarkRunner.renderSyntheticScreenFrame(
            title: "Xcode — CaptureEngine.swift",
            lines: ["actor CaptureEngine { func captureOnce() async -> Bool }"],
            accentShade: 0.12
        ))
        let frameB = try XCTUnwrap(BenchmarkRunner.renderSyntheticScreenFrame(
            title: "Safari — Stripe Invoice INV-991",
            lines: ["Subtotal: 4200 USD", "Paid November 23 2026", "Receipt verified"],
            accentShade: 0.45
        ))

        let differ = FrameDiffer()
        let first = differ.evaluate(image: frameA, threshold: 0.025)
        XCTAssertTrue(first.shouldProcess, "First frame must always be processed")

        let second = differ.evaluate(image: frameA, threshold: 0.025)
        XCTAssertFalse(second.shouldProcess, "Identical static frame must be skipped")
        XCTAssertEqual(second.changedCellRatio, 0.0, accuracy: 0.0001)

        let third = differ.evaluate(image: frameB, threshold: 0.025)
        XCTAssertTrue(third.shouldProcess, "Materially different window must trigger capture")
        XCTAssertGreaterThan(third.changedCellRatio, 0.05)
    }

    func testTextSanitizerRedactsSecretsAndExtractsURLs() {
        let input = """
        Deploying service to https://api.example.com/v2/health
        OPENAI_API_KEY=sk-proj-abc123def456ghi789jkl012mno345
        GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwx
        AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
        Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
        error: SQLITE_BUSY database is locked
        """

        let result = TextSanitizer.sanitize(input, redactSecrets: true)
        XCTAssertGreaterThanOrEqual(result.redactedCount, 4)
        XCTAssertFalse(result.cleanText.contains("sk-proj-"))
        XCTAssertFalse(result.cleanText.contains("ghp_123456"))
        XCTAssertFalse(result.cleanText.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(result.cleanText.contains("eyJhbGci"))
        XCTAssertTrue(result.cleanText.contains("[REDACTED:"))
        XCTAssertTrue(result.extractedURLs.contains("https://api.example.com/v2/health"))
        XCTAssertTrue(result.detectedTags.contains("error"))
        XCTAssertTrue(result.detectedTags.contains("redacted"))
    }

    func testPrivacyExclusionRulesBlockSensitiveAppsAndPrivateWindows() {
        let config = RecallConfig.default
        XCTAssertTrue(config.isExcluded(bundleID: "com.1password.1password", windowTitle: "Vault"))
        XCTAssertTrue(config.isExcluded(bundleID: "com.apple.Passwords", windowTitle: "Passwords"))
        XCTAssertTrue(config.isExcluded(bundleID: "com.apple.Safari", windowTitle: "Banking — Private Browsing"))
        XCTAssertTrue(config.isExcluded(bundleID: "com.google.Chrome", windowTitle: "Checkout (Incognito)"))
        XCTAssertFalse(config.isExcluded(bundleID: "com.apple.dt.Xcode", windowTitle: "MemoryStore.swift"))
    }

    func testMemoryStoreHybridSearchAndPurge() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gr-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try MemoryStore(databaseURL: tempDir.appendingPathComponent("test.sqlite"))
        let now = Date()

        _ = try await store.insert(MemoryRecord(
            timestamp: now.addingTimeInterval(-120),
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode",
            windowTitle: "MemoryStore.swift",
            url: nil,
            text: "SQLite WAL checkpoint fixed SQLITE_BUSY locking issue during concurrent FTS5 writes.",
            tags: ["code", "error"],
            frameHash: 111,
            ocrDurationMs: 38.0,
            redactedSecrets: 0
        ))

        _ = try await store.insert(MemoryRecord(
            timestamp: now.addingTimeInterval(-3600),
            appName: "Safari",
            bundleID: "com.apple.Safari",
            windowTitle: "Stripe Billing Invoice",
            url: "https://dashboard.stripe.com/invoices/inv_42",
            text: "Annual enterprise cloud invoice subtotal 4200 USD paid on schedule.",
            tags: ["finance", "web"],
            frameHash: 222,
            ocrDurationMs: 42.0,
            redactedSecrets: 1
        ))

        let count = try await store.totalCount()
        XCTAssertEqual(count, 2)

        // Punctuation-heavy query must never break FTS5 syntax
        let ftsHits = try await store.search(SearchQuery(text: "error: sqlite/wal (busy)", limit: 10))
        XCTAssertFalse(ftsHits.isEmpty)
        XCTAssertEqual(ftsHits.first?.record.appName, "Xcode")

        // App filter check
        let safariHits = try await store.search(SearchQuery(text: "invoice", appFilter: "Safari", limit: 10))
        XCTAssertEqual(safariHits.count, 1)
        XCTAssertEqual(safariHits.first?.record.url, "https://dashboard.stripe.com/invoices/inv_42")

        // Purge last 15 minutes removes only the recent Xcode entry
        let purged = try await store.purgeRecent(minutes: 15, now: now)
        XCTAssertEqual(purged, 1)
        let remaining = try await store.totalCount()
        XCTAssertEqual(remaining, 1)
    }

    func testVisionOCRExtractsTextFromSyntheticScreen() throws {
        let frame = try XCTUnwrap(BenchmarkRunner.renderSyntheticScreenFrame(
            title: "GlassRecall Vision Verification",
            lines: [
                "SQLite FTS5 Hybrid Semantic Screen Memory",
                "Zero Cloud Uploads Zero Raw Screenshots"
            ]
        ))

        let ocr = try OCREngine.recognize(image: frame, fastMode: false)
        let lower = ocr.text.lowercased()
        XCTAssertGreaterThan(ocr.lineCount, 0)
        XCTAssertTrue(lower.contains("sqlite"), "Expected OCR text to contain 'sqlite', got: \(ocr.text)")
        XCTAssertTrue(lower.contains("semantic") || lower.contains("memory"), "Expected OCR text to extract main body, got: \(ocr.text)")
    }
}
