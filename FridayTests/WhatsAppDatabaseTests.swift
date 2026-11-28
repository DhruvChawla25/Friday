// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import SQLite3
import Testing

@testable import Friday

struct WhatsAppDatabaseTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func row(
        _ name: String?, unread: Int, kind: Int = 0, archived: Bool = false, mutedFor: TimeInterval? = nil,
        last: TimeInterval = 0
    ) -> WhatsAppDatabase.Row {
        .init(
            name: name, unread: unread, kind: kind, archived: archived,
            mutedUntil: mutedFor.map { now.addingTimeInterval($0) }, lastMessage: now.addingTimeInterval(last))
    }

    @Test func countsUnreadOutsideTheArchiveNewestFirst() {
        let report = WhatsAppDatabase.report(
            rows: [
                row("Old", unread: 2, last: -500),
                row("New group", unread: 5, kind: 1, last: -10),
                row("Archived", unread: 9, archived: true),
                row("Marked", unread: -1, last: -100),
                row("Read", unread: 0),
                row("Broadcast", unread: 4, kind: 2),
                row("Community", unread: 4, kind: 4),
            ], now: now)
        #expect(report.chats.map(\.name) == ["New group", "Marked", "Old"])
        #expect(report.chats.map(\.id) == [0, 1, 2])
        #expect(report.unreadChats == 3)
        #expect(report.unreadMessages == 7)
        #expect(report.archivedUnreadChats == 1)
        #expect(report.chats[1].count == 0)
        #expect(report.chats[0].kind == .group)
    }

    @Test func muteOnlyCountsWhileItLasts() {
        let report = WhatsAppDatabase.report(
            rows: [row("Muted", unread: 1, mutedFor: 3600), row("Expired", unread: 1, mutedFor: -3600)], now: now)
        #expect(report.mutedChats == 1)
        #expect(report.chats.first { $0.name == "Muted" }?.muted == true)
    }

    @Test func queryNeverReadsMessageText() {
        for names in [true, false] {
            let sql = WhatsAppDatabase.query(readsNames: names)
            #expect(!sql.contains("ZLASTMESSAGETEXT"))
            #expect(!sql.contains("ZWAMESSAGE "))
            #expect(sql.contains("ZPARTNERNAME") == names)
        }
    }

    @Test func missingFileIsNotFound() {
        let home = URL(filePath: "/nonexistent/friday-\(UUID().uuidString)")
        #expect(WhatsAppDatabase.read(home: home, readsNames: true) == .failure(.notFound))
    }

    @Test func readsASyntheticDatabaseReadOnly() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "friday-wa-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let file = WhatsAppDatabase.url(home: home)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        #expect(sqlite3_open(file.path, &db) == SQLITE_OK)
        let sql = """
            CREATE TABLE ZWACHATSESSION (ZPARTNERNAME TEXT, ZUNREADCOUNT INTEGER, ZSESSIONTYPE INTEGER,
              ZARCHIVED INTEGER, ZREMOVED INTEGER, ZHIDDEN INTEGER, ZCONTACTJID TEXT, ZLASTMESSAGEDATE REAL,
              ZLASTMESSAGETEXT TEXT);
            CREATE TABLE ZWACHATPUSHCONFIG (ZJID TEXT, ZMUTEDUNTIL REAL);
            INSERT INTO ZWACHATSESSION VALUES ('Rahul', 3, 0, 0, 0, 0, 'a', 10, 'secret');
            INSERT INTO ZWACHATSESSION VALUES ('Team', 7, 1, 0, 0, 0, 'b', 20, 'secret');
            INSERT INTO ZWACHATSESSION VALUES ('Gone', 7, 0, 0, 1, 0, 'c', 30, 'secret');
            INSERT INTO ZWACHATPUSHCONFIG VALUES ('b', 4102444800);
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        let named = try WhatsAppDatabase.read(home: home, readsNames: true, now: now).get()
        #expect(named.chats.map(\.name) == ["Team", "Rahul"])
        #expect(named.mutedChats == 1)
        #expect(named.unreadMessages == 10)
        let hidden = try WhatsAppDatabase.read(home: home, readsNames: false, now: now).get()
        #expect(hidden.chats.allSatisfy { $0.name == nil })
    }
}
