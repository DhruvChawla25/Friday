// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import SQLite3

/// Reads unread counts straight from WhatsApp for Mac's own database on this
/// Mac (`ChatStorage.sqlite` in WhatsApp's group container).
///
/// - Read-only: the file is opened with `SQLITE_OPEN_READONLY`; Friday can
///   never send, post, mark as read or change anything in WhatsApp.
/// - No internet, no screen recording, no AI.
/// - Only chat names (when "show names" is on), unread counts, mute state and
///   the time of the last message are queried. Message text is never queried.
enum WhatsAppDatabase {
    static let relativePath = "Library/Group Containers/group.net.whatsapp.WhatsApp.shared/ChatStorage.sqlite"

    /// One chat session row as stored by WhatsApp.
    struct Row: Equatable, Sendable {
        var name: String?
        /// WhatsApp's unread number. -1 means "marked as unread".
        var unread: Int
        /// 0 person, 1 group, 3 channel; 2 (broadcast) and 4 (community) are skipped.
        var kind: Int
        var archived: Bool
        var mutedUntil: Date?
        var lastMessage: Date?
    }

    struct Chat: Equatable, Sendable, Identifiable {
        enum Kind: Equatable, Sendable { case person, group, channel }
        var id: Int
        var name: String?
        /// Unread messages; 0 for a chat only marked as unread.
        var count: Int
        var kind: Kind
        var muted: Bool
        var lastMessage: Date?
    }

    struct Report: Equatable, Sendable {
        /// Unread chats outside the archive, newest first.
        var chats: [Chat]
        /// Unread chats inside the archive (WhatsApp lists them separately).
        var archivedUnreadChats: Int

        var unreadChats: Int { chats.count }
        var mutedChats: Int { chats.filter(\.muted).count }
        var unreadMessages: Int { chats.reduce(0) { $0 + $1.count } }
    }

    enum Failure: Error, Equatable {
        /// WhatsApp for Mac has never stored chats on this Mac.
        case notFound
        /// macOS refused to open the file (the "data from other apps" permission).
        case blocked
        /// The file opened but did not look like WhatsApp's database.
        case unreadable
    }

    /// Only these columns are read. `ZLASTMESSAGETEXT` and message tables are never touched.
    static func query(readsNames: Bool) -> String {
        """
        SELECT \(readsNames ? "s.ZPARTNERNAME" : "NULL"), s.ZUNREADCOUNT, s.ZSESSIONTYPE, s.ZARCHIVED,
               (SELECT MAX(p.ZMUTEDUNTIL) FROM ZWACHATPUSHCONFIG p WHERE p.ZJID = s.ZCONTACTJID),
               s.ZLASTMESSAGEDATE
        FROM ZWACHATSESSION s
        WHERE s.ZUNREADCOUNT != 0 AND IFNULL(s.ZREMOVED, 0) = 0 AND IFNULL(s.ZHIDDEN, 0) = 0
              AND s.ZSESSIONTYPE NOT IN (2, 4)
        """
    }

    /// Builds the report from raw rows. Pure, so it is unit tested.
    static func report(rows: [Row], now: Date) -> Report {
        var chats: [Chat] = []
        var archived = 0
        for row in rows where row.unread != 0 {
            let kind: Chat.Kind
            switch row.kind {
            case 0: kind = .person
            case 1: kind = .group
            case 3: kind = .channel
            default: continue
            }
            if row.archived {
                archived += 1
                continue
            }
            let muted = row.mutedUntil.map { $0 > now } ?? false
            chats.append(
                Chat(
                    id: chats.count, name: row.name, count: max(0, row.unread), kind: kind, muted: muted,
                    lastMessage: row.lastMessage))
        }
        chats.sort { ($0.lastMessage ?? .distantPast) > ($1.lastMessage ?? .distantPast) }
        for index in chats.indices { chats[index].id = index }
        return Report(chats: chats, archivedUnreadChats: archived)
    }

    static func url(home: URL) -> URL { home.appending(path: relativePath) }

    /// Reads the database. Runs in well under a second; call it off the main thread.
    static func read(home: URL, readsNames: Bool, now: Date = .now) -> Result<Report, Failure> {
        let file = url(home: home)
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(.notFound) }
        var db: OpaquePointer?
        let uri = file.absoluteString + "?mode=ro"
        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return .failure(.blocked)
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)

        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(db, query(readsNames: readsNames), -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            // A sandbox or privacy refusal shows up here, when the file is first read.
            return .failure(status == SQLITE_CANTOPEN || status == SQLITE_AUTH ? .blocked : .unreadable)
        }
        defer { sqlite3_finalize(statement) }

        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else { return .failure(step == SQLITE_CANTOPEN ? .blocked : .unreadable) }
            rows.append(
                Row(
                    name: sqlite3_column_text(statement, 0).map { String(cString: $0) },
                    unread: Int(sqlite3_column_int64(statement, 1)),
                    kind: Int(sqlite3_column_int64(statement, 2)),
                    archived: sqlite3_column_int64(statement, 3) != 0,
                    mutedUntil: date(statement, 4),
                    lastMessage: date(statement, 5)))
        }
        return .success(report(rows: rows, now: now))
    }

    /// WhatsApp stores Core Data dates: seconds since 1 January 2001.
    private static func date(_ statement: OpaquePointer, _ column: Int32) -> Date? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL else { return nil }
        return Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, column))
    }
}
