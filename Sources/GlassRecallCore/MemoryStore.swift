import Foundation
import SQLite3

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum MemoryStoreError: Error, LocalizedError, Sendable {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "SQLite open failed: \(msg)"
        case .executionFailed(let msg): return "SQLite exec failed: \(msg)"
        case .prepareFailed(let msg): return "SQLite prepare failed: \(msg)"
        }
    }
}

private final class SQLiteHandle: @unchecked Sendable {
    let pointer: OpaquePointer

    init(path: String) throws {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let db { sqlite3_close_v2(db) }
            throw MemoryStoreError.openFailed(msg)
        }
        guard let opened = db else {
            throw MemoryStoreError.openFailed("nil database handle")
        }
        self.pointer = opened
    }

    deinit {
        sqlite3_close_v2(pointer)
    }
}

public actor MemoryStore {
    public let databaseURL: URL
    private let handle: SQLiteHandle
    private let embedder: SemanticEmbedder

    public static func defaultDatabaseURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GlassRecall", isDirectory: true).appendingPathComponent("memory.sqlite")
    }

    public init(databaseURL: URL = MemoryStore.defaultDatabaseURL(), embedder: SemanticEmbedder = SemanticEmbedder()) throws {
        self.databaseURL = databaseURL
        self.embedder = embedder

        let parentDir = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        self.handle = try SQLiteHandle(path: databaseURL.path)
        try Self.bootstrapSchema(db: handle.pointer)
    }

    private static func bootstrapSchema(db: OpaquePointer) throws {
        let sql = """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;
        PRAGMA temp_store = MEMORY;
        PRAGMA cache_size = -16000;

        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            app_name TEXT NOT NULL,
            bundle_id TEXT NOT NULL,
            window_title TEXT NOT NULL,
            url TEXT,
            text TEXT NOT NULL,
            tags TEXT NOT NULL DEFAULT '',
            frame_hash INTEGER NOT NULL DEFAULT 0,
            ocr_ms REAL NOT NULL DEFAULT 0,
            redacted_count INTEGER NOT NULL DEFAULT 0,
            embedding BLOB NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_memories_timestamp ON memories(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_memories_app_name ON memories(app_name);

        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
            window_title,
            app_name,
            url,
            text,
            content='memories',
            content_rowid='id',
            tokenize='porter unicode61'
        );

        CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
            INSERT INTO memories_fts(rowid, window_title, app_name, url, text)
            VALUES (new.id, new.window_title, new.app_name, COALESCE(new.url, ''), new.text);
        END;

        CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, window_title, app_name, url, text)
            VALUES ('delete', old.id, old.window_title, old.app_name, COALESCE(old.url, ''), old.text);
        END;

        CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
            INSERT INTO memories_fts(memories_fts, rowid, window_title, app_name, url, text)
            VALUES ('delete', old.id, old.window_title, old.app_name, COALESCE(old.url, ''), old.text);
            INSERT INTO memories_fts(rowid, window_title, app_name, url, text)
            VALUES (new.id, new.window_title, new.app_name, COALESCE(new.url, ''), new.text);
        END;
        """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "schema bootstrap failed"
            sqlite3_free(errMsg)
            throw MemoryStoreError.executionFailed(msg)
        }
    }

    @discardableResult
    public func insert(_ record: MemoryRecord) throws -> Int64 {
        let compositeText = "\(record.appName) \(record.windowTitle) \(record.text)"
        let embeddingData = SemanticEmbedder.encode(embedder.embed(compositeText))
        return try insert(record, embeddingData: embeddingData)
    }

    @discardableResult
    public func insertBatch(_ records: [MemoryRecord]) throws -> Int {
        guard !records.isEmpty else { return 0 }
        try exec("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for record in records {
                let compositeText = "\(record.appName) \(record.windowTitle) \(record.text)"
                let embeddingData = SemanticEmbedder.encode(embedder.embed(compositeText))
                _ = try insert(record, embeddingData: embeddingData)
            }
            try exec("COMMIT;")
            return records.count
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    private func insert(_ record: MemoryRecord, embeddingData: Data) throws -> Int64 {
        let sql = """
        INSERT INTO memories (
            timestamp, app_name, bundle_id, window_title, url, text, tags, frame_hash, ocr_ms, redacted_count, embedding
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, record.timestamp.timeIntervalSince1970)
        bindText(stmt, 2, record.appName)
        bindText(stmt, 3, record.bundleID)
        bindText(stmt, 4, record.windowTitle)
        if let url = record.url, !url.isEmpty {
            bindText(stmt, 5, url)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        bindText(stmt, 6, record.text)
        bindText(stmt, 7, record.tags.joined(separator: ","))
        sqlite3_bind_int64(stmt, 8, Int64(bitPattern: record.frameHash))
        sqlite3_bind_double(stmt, 9, record.ocrDurationMs)
        sqlite3_bind_int64(stmt, 10, Int64(record.redactedSecrets))
        _ = embeddingData.withUnsafeBytes { raw in
            sqlite3_bind_blob(stmt, 11, raw.baseAddress, Int32(embeddingData.count), SQLITE_TRANSIENT_DESTRUCTOR)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MemoryStoreError.executionFailed(lastErrorMessage())
        }
        return sqlite3_last_insert_rowid(handle.pointer)
    }

    public func search(_ query: SearchQuery) throws -> [SearchHit] {
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cutoff = query.dateRange.cutoffDate()?.timeIntervalSince1970

        if trimmed.isEmpty {
            let recent = try fetchRecent(limit: query.limit, appFilter: query.appFilter, cutoff: cutoff)
            return recent.map { record in
                SearchHit(
                    record: record,
                    snippet: Self.makeSnippet(from: record.text, queryTokens: []),
                    lexicalScore: 1.0,
                    semanticScore: 1.0,
                    combinedScore: 1.0
                )
            }
        }

        let tokens = Self.extractTokens(from: trimmed)
        let queryVector = embedder.embed(trimmed)
        let now = Date().timeIntervalSince1970

        var candidates: [Int64: (record: MemoryRecord, lexical: Double, semantic: Double)] = [:]

        // Stage 1: FTS5 lexical retrieval (strict AND first, relaxed OR fallback)
        if !tokens.isEmpty {
            let andExpr = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
            var ftsHits = try runFTSSearch(matchExpr: andExpr, appFilter: query.appFilter, cutoff: cutoff, limit: 80)
            if ftsHits.count < 5 && tokens.count > 1 {
                let orExpr = tokens.map { "\"\($0)\"*" }.joined(separator: " OR ")
                let extra = try runFTSSearch(matchExpr: orExpr, appFilter: query.appFilter, cutoff: cutoff, limit: 80)
                var seen = Set(ftsHits.map(\.record.id))
                for item in extra where seen.insert(item.record.id).inserted {
                    ftsHits.append(item)
                }
            }

            for item in ftsHits {
                let sem = Double(SemanticEmbedder.cosineSimilarity(queryVector, item.embedding))
                candidates[item.record.id] = (item.record, item.lexicalScore, sem)
            }
        }

        // Stage 2: Semantic scan over recent window to surface conceptual matches with zero exact keyword overlap
        let recentVectors = try fetchRecentEmbeddings(limit: 500, appFilter: query.appFilter, cutoff: cutoff)
        var semanticTop: [(id: Int64, score: Double)] = []
        semanticTop.reserveCapacity(32)
        for item in recentVectors {
            if candidates[item.id] != nil { continue }
            let sim = Double(SemanticEmbedder.cosineSimilarity(queryVector, item.embedding))
            if sim >= 0.16 {
                semanticTop.append((item.id, sim))
            }
        }
        semanticTop.sort { $0.score > $1.score }
        for match in semanticTop.prefix(24) {
            if let record = try fetchRecord(id: match.id) {
                candidates[record.id] = (record, 0.0, match.score)
            }
        }

        // Stage 3: Hybrid fusion (FTS5 + Cosine Semantic + Smooth Recency Decay)
        let hits: [SearchHit] = candidates.values.map { item in
            let ageDays = max(0.0, (now - item.record.timestamp.timeIntervalSince1970) / 86_400.0)
            let recency = 1.0 / (1.0 + ageDays / 14.0)
            let combined = (0.58 * item.lexical) + (0.34 * item.semantic) + (0.08 * recency)
            let snippet = Self.makeSnippet(from: item.record.text, queryTokens: tokens)
            return SearchHit(
                record: item.record,
                snippet: snippet,
                lexicalScore: item.lexical,
                semanticScore: item.semantic,
                combinedScore: combined
            )
        }
        .sorted { $0.combinedScore > $1.combinedScore }

        return Array(hits.prefix(query.limit))
    }

    public func fetchRecent(limit: Int = 60, appFilter: String? = nil, cutoff: TimeInterval? = nil) throws -> [MemoryRecord] {
        var clauses: [String] = []
        if appFilter != nil { clauses.append("app_name = ?") }
        if cutoff != nil { clauses.append("timestamp >= ?") }
        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = """
        SELECT id, timestamp, app_name, bundle_id, window_title, url, text, tags, frame_hash, ocr_ms, redacted_count
        FROM memories
        \(whereSQL)
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let appFilter { bindText(stmt, idx, appFilter); idx += 1 }
        if let cutoff { sqlite3_bind_double(stmt, idx, cutoff); idx += 1 }
        sqlite3_bind_int64(stmt, idx, Int64(limit))

        var results: [MemoryRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(readRecord(stmt: stmt, offset: 0))
        }
        return results
    }

    public func delete(id: Int64) throws {
        let sql = "DELETE FROM memories WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MemoryStoreError.executionFailed(lastErrorMessage())
        }
    }

    @discardableResult
    public func purgeRecent(minutes: Int, now: Date = Date()) throws -> Int {
        let threshold = now.addingTimeInterval(-Double(minutes) * 60.0).timeIntervalSince1970
        let sql = "DELETE FROM memories WHERE timestamp >= ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, threshold)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MemoryStoreError.executionFailed(lastErrorMessage())
        }
        return Int(sqlite3_changes(handle.pointer))
    }

    @discardableResult
    public func pruneOlderThan(days: Int, now: Date = Date()) throws -> Int {
        guard days > 0 else { return 0 }
        let threshold = now.addingTimeInterval(-Double(days) * 86_400.0).timeIntervalSince1970
        let sql = "DELETE FROM memories WHERE timestamp < ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, threshold)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw MemoryStoreError.executionFailed(lastErrorMessage())
        }
        return Int(sqlite3_changes(handle.pointer))
    }

    public func wipeAll() throws {
        try exec("DELETE FROM memories; VACUUM;")
    }

    public func totalCount() throws -> Int {
        let sql = "SELECT COUNT(*) FROM memories;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    public func totalRedactedSecrets() throws -> Int {
        let sql = "SELECT COALESCE(SUM(redacted_count), 0) FROM memories;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    public func appBreakdown(limit: Int = 8) throws -> [AppActivityBucket] {
        let sql = """
        SELECT app_name, bundle_id, COUNT(*) AS cnt, COALESCE(SUM(LENGTH(text)), 0) AS chars
        FROM memories
        GROUP BY app_name, bundle_id
        ORDER BY cnt DESC
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, Int64(limit))

        var buckets: [AppActivityBucket] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            buckets.append(AppActivityBucket(
                appName: columnString(stmt, 0),
                bundleID: columnString(stmt, 1),
                count: Int(sqlite3_column_int64(stmt, 2)),
                totalCharacters: Int(sqlite3_column_int64(stmt, 3))
            ))
        }
        return buckets
    }

    public func hourlyActivity(lastHours: Int = 12, now: Date = Date()) throws -> [HourlyActivityPoint] {
        let calendar = Calendar.current
        let start = now.addingTimeInterval(-Double(lastHours) * 3600.0).timeIntervalSince1970
        let sql = "SELECT timestamp FROM memories WHERE timestamp >= ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, start)

        var counts: [Int: Int] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
            let hour = calendar.component(.hour, from: ts)
            counts[hour, default: 0] += 1
        }

        let currentHour = calendar.component(.hour, from: now)
        return (0..<lastHours).reversed().map { offset in
            let h = (currentHour - offset + 24) % 24
            return HourlyActivityPoint(hour: h, count: counts[h, default: 0])
        }
    }

    public func databaseFileSizeBytes() -> Int64 {
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm"
        ]
        var total: Int64 = 0
        for p in paths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: p),
               let size = attrs[.size] as? NSNumber {
                total += size.int64Value
            }
        }
        return total
    }

    public func checkpoint() throws {
        try exec("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    // MARK: - Private SQLite helpers

    private func runFTSSearch(
        matchExpr: String,
        appFilter: String?,
        cutoff: TimeInterval?,
        limit: Int
    ) throws -> [(record: MemoryRecord, lexicalScore: Double, embedding: [Float])] {
        var clauses = ["memories_fts MATCH ?"]
        if appFilter != nil { clauses.append("m.app_name = ?") }
        if cutoff != nil { clauses.append("m.timestamp >= ?") }
        let whereSQL = clauses.joined(separator: " AND ")

        let sql = """
        SELECT m.id, m.timestamp, m.app_name, m.bundle_id, m.window_title, m.url, m.text, m.tags,
               m.frame_hash, m.ocr_ms, m.redacted_count, m.embedding,
               bm25(memories_fts, 3.0, 2.0, 2.5, 1.0) AS rank_score
        FROM memories_fts
        JOIN memories m ON m.id = memories_fts.rowid
        WHERE \(whereSQL)
        ORDER BY rank_score ASC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        bindText(stmt, idx, matchExpr); idx += 1
        if let appFilter { bindText(stmt, idx, appFilter); idx += 1 }
        if let cutoff { sqlite3_bind_double(stmt, idx, cutoff); idx += 1 }
        sqlite3_bind_int64(stmt, idx, Int64(limit))

        var out: [(MemoryRecord, Double, [Float])] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let record = readRecord(stmt: stmt, offset: 0)
            let embedding = readEmbedding(stmt: stmt, column: 11)
            let bm25 = sqlite3_column_double(stmt, 12)
            // SQLite FTS5 bm25() returns negative scores where more-negative is stronger match
            let normalized = 1.0 - (1.0 / (1.0 + abs(bm25) * 0.45))
            out.append((record, max(0.05, min(1.0, normalized)), embedding))
        }
        return out
    }

    private func fetchRecentEmbeddings(
        limit: Int,
        appFilter: String?,
        cutoff: TimeInterval?
    ) throws -> [(id: Int64, embedding: [Float])] {
        var clauses: [String] = []
        if appFilter != nil { clauses.append("app_name = ?") }
        if cutoff != nil { clauses.append("timestamp >= ?") }
        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")

        let sql = "SELECT id, embedding FROM memories \(whereSQL) ORDER BY timestamp DESC LIMIT ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }

        var idx: Int32 = 1
        if let appFilter { bindText(stmt, idx, appFilter); idx += 1 }
        if let cutoff { sqlite3_bind_double(stmt, idx, cutoff); idx += 1 }
        sqlite3_bind_int64(stmt, idx, Int64(limit))

        var items: [(Int64, [Float])] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let emb = readEmbedding(stmt: stmt, column: 1)
            items.append((id, emb))
        }
        return items
    }

    private func fetchRecord(id: Int64) throws -> MemoryRecord? {
        let sql = """
        SELECT id, timestamp, app_name, bundle_id, window_title, url, text, tags, frame_hash, ocr_ms, redacted_count
        FROM memories WHERE id = ? LIMIT 1;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle.pointer, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MemoryStoreError.prepareFailed(lastErrorMessage())
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return readRecord(stmt: stmt, offset: 0)
    }

    private func readRecord(stmt: OpaquePointer, offset: Int32) -> MemoryRecord {
        let id = sqlite3_column_int64(stmt, offset + 0)
        let ts = Date(timeIntervalSince1970: sqlite3_column_double(stmt, offset + 1))
        let app = columnString(stmt, offset + 2)
        let bundle = columnString(stmt, offset + 3)
        let title = columnString(stmt, offset + 4)
        let url: String? = sqlite3_column_type(stmt, offset + 5) == SQLITE_NULL ? nil : columnString(stmt, offset + 5)
        let text = columnString(stmt, offset + 6)
        let tagsRaw = columnString(stmt, offset + 7)
        let tags = tagsRaw.isEmpty ? [] : tagsRaw.split(separator: ",").map(String.init)
        let frameHash = UInt64(bitPattern: sqlite3_column_int64(stmt, offset + 8))
        let ocrMs = sqlite3_column_double(stmt, offset + 9)
        let redacted = Int(sqlite3_column_int64(stmt, offset + 10))
        return MemoryRecord(
            id: id,
            timestamp: ts,
            appName: app,
            bundleID: bundle,
            windowTitle: title,
            url: url,
            text: text,
            tags: tags,
            frameHash: frameHash,
            ocrDurationMs: ocrMs,
            redactedSecrets: redacted
        )
    }

    private func readEmbedding(stmt: OpaquePointer, column: Int32) -> [Float] {
        guard let bytes = sqlite3_column_blob(stmt, column) else {
            return [Float](repeating: 0, count: SemanticEmbedder.dimensions)
        }
        let len = Int(sqlite3_column_bytes(stmt, column))
        return SemanticEmbedder.decode(Data(bytes: bytes, count: len))
    }

    private func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT_DESTRUCTOR)
    }

    private func columnString(_ stmt: OpaquePointer, _ index: Int32) -> String {
        guard let cStr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cStr)
    }

    private func exec(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle.pointer, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "sqlite exec error"
            sqlite3_free(errMsg)
            throw MemoryStoreError.executionFailed(msg)
        }
    }

    private func lastErrorMessage() -> String {
        String(cString: sqlite3_errmsg(handle.pointer))
    }

    public static func extractTokens(from query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "_" }
            .map(String.init)
            .filter { $0.count >= 2 }
    }

    public static func makeSnippet(from text: String, queryTokens: [String], maxLength: Int = 180) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " · ")
        guard flat.count > maxLength else { return flat }

        let lower = flat.lowercased()
        for token in queryTokens {
            if let range = lower.range(of: token) {
                let matchIdx = flat.distance(from: flat.startIndex, to: range.lowerBound)
                let startOffset = max(0, matchIdx - 48)
                let start = flat.index(flat.startIndex, offsetBy: startOffset)
                let endOffset = min(flat.count, startOffset + maxLength)
                let end = flat.index(flat.startIndex, offsetBy: endOffset)
                let prefix = startOffset > 0 ? "…" : ""
                let suffix = endOffset < flat.count ? "…" : ""
                return prefix + String(flat[start..<end]) + suffix
            }
        }
        return String(flat.prefix(maxLength)) + "…"
    }
}
