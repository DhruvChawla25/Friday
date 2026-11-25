// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import SQLite3

/// OpenCode: its database (`~/.local/share/opencode/opencode.db`) keeps a
/// token and cost total per session. Friday opens it read-only and sums only
/// those number columns; it never reads messages. OpenCode works with many
/// providers, so there is no single limit to show.
struct OpenCodeUsageProvider: UsageProvider {
    let tool = AITool.openCode
    static let databasePath = ".local/share/opencode/opencode.db"
    /// A session counts as live if it changed in the last few minutes.
    static let liveWindow: TimeInterval = 5 * 60

    struct Totals: Equatable {
        var sessions = 0
        var tokens = 0
        var cost = 0.0
        var lastUpdated: Date?
    }

    func usage(in env: UsageEnvironment) -> ToolUsage {
        let url = env.url(Self.databasePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return .notInstalled(tool) }
        let dayStart = env.calendar.startOfDay(for: env.now)
        guard let today = Self.totals(databaseAt: url, since: dayStart) else {
            return ToolUsage(tool: tool, isInstalled: true, source: "Could not read OpenCode's database")
        }
        let latest = Self.totals(databaseAt: url, since: .distantPast)?.lastUpdated
        let live = latest.map { env.now.timeIntervalSince($0) < Self.liveWindow } ?? false
        return ToolUsage(
            tool: tool,
            isInstalled: true,
            isLive: live,
            liveDetail: live ? "Session active" : nil,
            meters: [Self.meter(today: today)],
            source: "OpenCode's local database",
            lastActive: latest
        )
    }

    static func meter(today: Totals) -> UsageMeter {
        var detail = "\(today.sessions) \(today.sessions == 1 ? "session" : "sessions") · "
        detail += "\(UsageFormat.compact(today.tokens)) tokens"
        if today.cost > 0 { detail += " · " + today.cost.formatted(.currency(code: "USD")) }
        return UsageMeter(window: "Today", detail: detail, note: "Provider limits not available offline")
    }

    /// Sums sessions updated since `since`. Nil if the file is not an
    /// OpenCode database Friday understands.
    static func totals(databaseAt url: URL, since: Date) -> Totals? {
        var db: OpaquePointer?
        // Read-only; if the write-ahead log cannot be shared, read the main file as-is.
        let uris = ["\(url.absoluteString)?mode=ro", "\(url.absoluteString)?immutable=1"]
        for uri in uris {
            if sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
                let totals = query(db, since: since)
            {
                sqlite3_close(db)
                return totals
            }
            sqlite3_close(db)
            db = nil
        }
        return nil
    }

    private static func query(_ db: OpaquePointer?, since: Date) -> Totals? {
        let sql = """
            SELECT COUNT(*),
                   COALESCE(SUM(tokens_input + tokens_output + tokens_reasoning + tokens_cache_write), 0),
                   COALESCE(SUM(cost), 0), MAX(time_updated)
            FROM session_v2 WHERE time_updated >= ?
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let sinceMs = since == .distantPast ? 0 : Int64(since.timeIntervalSince1970 * 1000)
        sqlite3_bind_int64(statement, 1, sinceMs)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        var totals = Totals(
            sessions: Int(sqlite3_column_int64(statement, 0)),
            tokens: Int(sqlite3_column_int64(statement, 1)),
            cost: sqlite3_column_double(statement, 2))
        if sqlite3_column_type(statement, 3) != SQLITE_NULL {
            totals.lastUpdated = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1000)
        }
        return totals
    }
}
