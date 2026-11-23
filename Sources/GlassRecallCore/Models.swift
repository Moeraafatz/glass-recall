import Foundation

public struct MemoryRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: Int64
    public let timestamp: Date
    public let appName: String
    public let bundleID: String
    public let windowTitle: String
    public let url: String?
    public let text: String
    public let tags: [String]
    public let frameHash: UInt64
    public let ocrDurationMs: Double
    public let redactedSecrets: Int

    public init(
        id: Int64 = 0,
        timestamp: Date = Date(),
        appName: String,
        bundleID: String,
        windowTitle: String,
        url: String? = nil,
        text: String,
        tags: [String] = [],
        frameHash: UInt64 = 0,
        ocrDurationMs: Double = 0,
        redactedSecrets: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.url = url
        self.text = text
        self.tags = tags
        self.frameHash = frameHash
        self.ocrDurationMs = ocrDurationMs
        self.redactedSecrets = redactedSecrets
    }
}

public struct SearchHit: Identifiable, Hashable, Sendable {
    public let record: MemoryRecord
    public let snippet: String
    public let lexicalScore: Double
    public let semanticScore: Double
    public let combinedScore: Double

    public var id: Int64 { record.id }

    public init(
        record: MemoryRecord,
        snippet: String,
        lexicalScore: Double,
        semanticScore: Double,
        combinedScore: Double
    ) {
        self.record = record
        self.snippet = snippet
        self.lexicalScore = lexicalScore
        self.semanticScore = semanticScore
        self.combinedScore = combinedScore
    }
}

public enum DateRangeFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Time"
    case today = "Today"
    case week = "7 Days"
    case month = "30 Days"

    public var id: String { rawValue }

    public func cutoffDate(from now: Date = Date()) -> Date? {
        switch self {
        case .all:
            return nil
        case .today:
            return Calendar.current.startOfDay(for: now)
        case .week:
            return now.addingTimeInterval(-7 * 86_400)
        case .month:
            return now.addingTimeInterval(-30 * 86_400)
        }
    }
}

public struct SearchQuery: Sendable {
    public var text: String
    public var appFilter: String?
    public var dateRange: DateRangeFilter
    public var limit: Int

    public init(
        text: String,
        appFilter: String? = nil,
        dateRange: DateRangeFilter = .all,
        limit: Int = 40
    ) {
        self.text = text
        self.appFilter = appFilter
        self.dateRange = dateRange
        self.limit = limit
    }
}

public struct AppActivityBucket: Identifiable, Hashable, Sendable {
    public let appName: String
    public let bundleID: String
    public let count: Int
    public let totalCharacters: Int

    public var id: String { bundleID.isEmpty ? appName : bundleID }

    public init(appName: String, bundleID: String, count: Int, totalCharacters: Int) {
        self.appName = appName
        self.bundleID = bundleID
        self.count = count
        self.totalCharacters = totalCharacters
    }
}

public struct HourlyActivityPoint: Identifiable, Hashable, Sendable {
    public let hour: Int
    public let count: Int

    public var id: Int { hour }

    public init(hour: Int, count: Int) {
        self.hour = hour
        self.count = count
    }
}

public struct CaptureStats: Sendable, Codable {
    public var totalMemories: Int
    public var databaseBytes: Int64
    public var framesEvaluated: Int
    public var framesSkippedByDiff: Int
    public var framesBlockedByPrivacy: Int
    public var secretsRedacted: Int
    public var averageOcrMs: Double
    public var lastSearchMs: Double
    public var isCapturing: Bool
    public var pausedUntil: Date?

    public var skipRatePercent: Double {
        guard framesEvaluated > 0 else { return 0 }
        return (Double(framesSkippedByDiff) / Double(framesEvaluated)) * 100.0
    }

    public var estimatedRawScreenshotsBytes: Int64 {
        // Conservative 1.4 MB per Retina PNG screenshot vs compressed text + FTS5 + 128-dim vector
        Int64(max(totalMemories, 0)) * 1_450_000
    }

    public init(
        totalMemories: Int = 0,
        databaseBytes: Int64 = 0,
        framesEvaluated: Int = 0,
        framesSkippedByDiff: Int = 0,
        framesBlockedByPrivacy: Int = 0,
        secretsRedacted: Int = 0,
        averageOcrMs: Double = 0,
        lastSearchMs: Double = 0,
        isCapturing: Bool = false,
        pausedUntil: Date? = nil
    ) {
        self.totalMemories = totalMemories
        self.databaseBytes = databaseBytes
        self.framesEvaluated = framesEvaluated
        self.framesSkippedByDiff = framesSkippedByDiff
        self.framesBlockedByPrivacy = framesBlockedByPrivacy
        self.secretsRedacted = secretsRedacted
        self.averageOcrMs = averageOcrMs
        self.lastSearchMs = lastSearchMs
        self.isCapturing = isCapturing
        self.pausedUntil = pausedUntil
    }
}

public struct RecallConfig: Codable, Sendable, Equatable {
    public var captureIntervalSeconds: Double
    public var diffThreshold: Double
    public var retentionDays: Int
    public var redactSecrets: Bool
    public var fastOCRMode: Bool
    public var excludedBundleIDs: [String]
    public var excludedTitleKeywords: [String]

    public static let builtInExcludedBundleIDs: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "org.keepassxc.keepassxc",
        "com.dashlane.Dashlane",
        "com.apple.systempreferences"
    ]

    public static let builtInExcludedTitleKeywords: [String] = [
        "Private Browsing",
        "Incognito",
        "InPrivate",
        "Private Window",
        "1Password",
        "Keychain Access",
        "Passwords"
    ]

    public static let `default` = RecallConfig(
        captureIntervalSeconds: 4.0,
        diffThreshold: 0.025,
        retentionDays: 30,
        redactSecrets: true,
        fastOCRMode: false,
        excludedBundleIDs: builtInExcludedBundleIDs,
        excludedTitleKeywords: builtInExcludedTitleKeywords
    )

    public init(
        captureIntervalSeconds: Double = 4.0,
        diffThreshold: Double = 0.025,
        retentionDays: Int = 30,
        redactSecrets: Bool = true,
        fastOCRMode: Bool = false,
        excludedBundleIDs: [String] = builtInExcludedBundleIDs,
        excludedTitleKeywords: [String] = builtInExcludedTitleKeywords
    ) {
        self.captureIntervalSeconds = captureIntervalSeconds
        self.diffThreshold = diffThreshold
        self.retentionDays = retentionDays
        self.redactSecrets = redactSecrets
        self.fastOCRMode = fastOCRMode
        self.excludedBundleIDs = excludedBundleIDs
        self.excludedTitleKeywords = excludedTitleKeywords
    }

    public func isExcluded(bundleID: String, windowTitle: String) -> Bool {
        let lowerBundle = bundleID.lowercased()
        if excludedBundleIDs.contains(where: { lowerBundle == $0.lowercased() || lowerBundle.hasPrefix($0.lowercased() + ".") }) {
            return true
        }
        let lowerTitle = windowTitle.lowercased()
        if excludedTitleKeywords.contains(where: { !$0.isEmpty && lowerTitle.contains($0.lowercased()) }) {
            return true
        }
        return false
    }
}

public struct WindowContext: Sendable, Equatable {
    public let appName: String
    public let bundleID: String
    public let windowTitle: String
    public let url: String?
    public let processID: Int32

    public init(
        appName: String,
        bundleID: String,
        windowTitle: String,
        url: String? = nil,
        processID: Int32 = 0
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.url = url
        self.processID = processID
    }
}
