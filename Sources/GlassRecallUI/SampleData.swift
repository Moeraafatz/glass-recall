import Foundation
import GlassRecallCore

public enum SampleData {
    public static func demoRecords(referenceDate: Date = Date()) -> [MemoryRecord] {
        [
            MemoryRecord(
                id: 101,
                timestamp: referenceDate.addingTimeInterval(-140),
                appName: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                windowTitle: "MemoryStore.swift — GlassRecall",
                url: "file:///Sources/GlassRecallCore/MemoryStore.swift",
                text: "PRAGMA journal_mode = WAL; SQLite FTS5 porter unicode61 hybrid search merges BM25 lexical rank with 128-dim Accelerate cosine similarity in 4.2 ms.",
                tags: ["code", "web"],
                frameHash: 0xA4F91201,
                ocrDurationMs: 41.2,
                redactedSecrets: 0
            ),
            MemoryRecord(
                id: 102,
                timestamp: referenceDate.addingTimeInterval(-640),
                appName: "Terminal",
                bundleID: "com.apple.Terminal",
                windowTitle: "zsh — prod-cluster-eu",
                url: "https://status.internal/deploy/8841",
                text: "error: SQLITE_BUSY database is locked during WAL checkpoint · Fixed by setting PRAGMA busy_timeout = 3000 · OPENAI_API_KEY=[REDACTED:OPENAI_KEY]",
                tags: ["error", "redacted"],
                frameHash: 0xB8C10922,
                ocrDurationMs: 36.8,
                redactedSecrets: 1
            ),
            MemoryRecord(
                id: 103,
                timestamp: referenceDate.addingTimeInterval(-1_850),
                appName: "Zoom",
                bundleID: "us.zoom.xos",
                windowTitle: "Q4 Architecture & Storage Review",
                url: "https://zoom.us/j/994812031",
                text: "Slide 12: Zero-cloud recall drops 30-day storage from 68.9 GB raw PNG to 114 MB SQLite WAL + FTS5 + Float32 vectors. Action item: ship v1.0.0 DMG Friday.",
                tags: ["meeting", "web"],
                frameHash: 0xC91F230A,
                ocrDurationMs: 52.4,
                redactedSecrets: 0
            ),
            MemoryRecord(
                id: 104,
                timestamp: referenceDate.addingTimeInterval(-3_420),
                appName: "Safari",
                bundleID: "com.apple.Safari",
                windowTitle: "Stripe Billing — Invoice INV-2026-8841",
                url: "https://dashboard.stripe.com/invoices/inv_8841",
                text: "Invoice INV-2026-8841 · Acme Cloud Infrastructure · Subtotal $4,200.00 USD · Status: Paid · Receipt downloadable for Q4 accounting reconciliation.",
                tags: ["finance", "web"],
                frameHash: 0xD24A881F,
                ocrDurationMs: 44.1,
                redactedSecrets: 0
            ),
            MemoryRecord(
                id: 105,
                timestamp: referenceDate.addingTimeInterval(-5_900),
                appName: "VS Code",
                bundleID: "com.microsoft.VSCode",
                windowTitle: "migrations/2026_fts5_trigger.sql",
                url: "file:///migrations/2026_fts5_trigger.sql",
                text: "CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN INSERT INTO memories_fts(rowid, window_title, app_name, url, text) VALUES (...); END;",
                tags: ["code"],
                frameHash: 0xE712004C,
                ocrDurationMs: 39.5,
                redactedSecrets: 0
            ),
            MemoryRecord(
                id: 106,
                timestamp: referenceDate.addingTimeInterval(-9_100),
                appName: "Slack",
                bundleID: "com.tinyspeck.slackmacgap",
                windowTitle: "#releases — macOS Open Source",
                url: "https://app.slack.com/client/T01/C09",
                text: "Confirmed zero telemetry, zero helper daemons, zero raw screenshots saved on disk. GitHub token ghp check passed: [REDACTED:GITHUB_TOKEN].",
                tags: ["web", "redacted"],
                frameHash: 0xF321998B,
                ocrDurationMs: 34.0,
                redactedSecrets: 1
            )
        ]
    }

    public static func demoSearchHits(referenceDate: Date = Date()) -> [SearchHit] {
        let recs = demoRecords(referenceDate: referenceDate)
        return [
            SearchHit(
                record: recs[0],
                snippet: "PRAGMA journal_mode = WAL; SQLite FTS5 porter unicode61 hybrid search merges BM25 lexical rank with 128-dim Accelerate cosine similarity in 4.2 ms.",
                lexicalScore: 0.96,
                semanticScore: 0.91,
                combinedScore: 0.95
            ),
            SearchHit(
                record: recs[1],
                snippet: "error: SQLITE_BUSY database is locked during WAL checkpoint · Fixed by setting PRAGMA busy_timeout = 3000 · OPENAI_API_KEY=[REDACTED:OPENAI_KEY]",
                lexicalScore: 0.89,
                semanticScore: 0.82,
                combinedScore: 0.87
            ),
            SearchHit(
                record: recs[2],
                snippet: "Slide 12: Zero-cloud recall drops 30-day storage from 68.9 GB raw PNG to 114 MB SQLite WAL + FTS5 + Float32 vectors. Action item: ship v1.0.0 DMG.",
                lexicalScore: 0.78,
                semanticScore: 0.84,
                combinedScore: 0.81
            ),
            SearchHit(
                record: recs[4],
                snippet: "CREATE TRIGGER memories_ai AFTER INSERT ON memories BEGIN INSERT INTO memories_fts(rowid, window_title, app_name, url, text) VALUES (...);",
                lexicalScore: 0.74,
                semanticScore: 0.77,
                combinedScore: 0.75
            )
        ]
    }

    public static func demoStats() -> CaptureStats {
        CaptureStats(
            totalMemories: 14_820,
            databaseBytes: 34_603_008,
            framesEvaluated: 68_420,
            framesSkippedByDiff: 53_412,
            framesBlockedByPrivacy: 188,
            secretsRedacted: 47,
            averageOcrMs: 42.6,
            lastSearchMs: 4.2,
            isCapturing: true,
            pausedUntil: nil
        )
    }

    public static func demoAppBuckets() -> [AppActivityBucket] {
        [
            AppActivityBucket(appName: "Xcode", bundleID: "com.apple.dt.Xcode", count: 4_820, totalCharacters: 1_920_000),
            AppActivityBucket(appName: "Safari", bundleID: "com.apple.Safari", count: 3_640, totalCharacters: 1_540_000),
            AppActivityBucket(appName: "Terminal", bundleID: "com.apple.Terminal", count: 2_510, totalCharacters: 910_000),
            AppActivityBucket(appName: "VS Code", bundleID: "com.microsoft.VSCode", count: 1_940, totalCharacters: 820_000),
            AppActivityBucket(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", count: 1_120, totalCharacters: 430_000),
            AppActivityBucket(appName: "Zoom", bundleID: "us.zoom.xos", count: 790, totalCharacters: 280_000)
        ]
    }

    public static func demoHourlyActivity() -> [HourlyActivityPoint] {
        let counts = [6, 14, 28, 42, 37, 54, 49, 63, 71, 58, 44, 62]
        return counts.enumerated().map { idx, c in
            HourlyActivityPoint(hour: (9 + idx) % 24, count: c)
        }
    }
}
