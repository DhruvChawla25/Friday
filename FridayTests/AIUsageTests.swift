// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import SQLite3
import Testing

@testable import Friday

// All data here is synthetic.

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ iso: String) -> Date { TranscriptUsage.parseDate(iso)! }

private func assistantLine(
    _ time: String, id: String, request: String = "r", input: Int = 10, output: Int = 5, cacheWrite: Int = 0,
    cacheRead: Int = 1000, credits: Double? = nil, model: String = "claude-test"
) -> String {
    let creditsField = credits.map { #","credits":\#($0)"# } ?? ""
    return """
        {"type":"assistant","timestamp":"\(time)","requestId":"\(request)","message":{"id":"\(id)","model":"\(model)",\
        "content":[{"type":"text","text":"ignored"}],"usage":{"input_tokens":\(input),"output_tokens":\(output),\
        "cache_creation_input_tokens":\(cacheWrite),"cache_read_input_tokens":\(cacheRead)\(creditsField)}}}
        """
}

private func makeHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "friday-usage-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func write(_ text: String, to relative: String, in home: URL) throws {
    let url = home.appending(path: relative)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

struct TranscriptParsingTests {
    @Test func parsesAssistantUsageAndSkipsEverythingElse() {
        let jsonl = [
            #"{"type":"user","timestamp":"2026-01-01T10:00:00Z","message":{"content":"hi"}}"#,
            assistantLine("2026-01-01T10:00:05.250Z", id: "m1", input: 100, output: 50, cacheWrite: 20),
            "not json at all {",
            #"{"type":"assistant","timestamp":"2026-01-01T10:01:00Z","message":{"id":"m2"}}"#,
            assistantLine("2026-01-01T10:02:00Z", id: "s", model: "<synthetic>"),
            "",
        ].joined(separator: "\n")
        let events = TranscriptUsage.events(fromJSONL: Data(jsonl.utf8))
        #expect(events.count == 1)
        #expect(events.first?.tokens == 170)
        #expect(events.first?.cacheRead == 1000)
        #expect(events.first?.date == date("2026-01-01T10:00:05.250Z"))
    }

    @Test func repeatedContentBlocksCountOnce() {
        let jsonl = [
            assistantLine("2026-01-01T10:00:00Z", id: "m1", output: 1),
            assistantLine("2026-01-01T10:00:01Z", id: "m1", output: 40),
            assistantLine("2026-01-01T10:00:02Z", id: "m1", request: "other", output: 7),
        ].joined(separator: "\n")
        let events = TranscriptUsage.events(fromJSONL: Data(jsonl.utf8))
        #expect(events.count == 2)
        #expect(events.map(\.output).sorted() == [7, 40])
    }

    @Test func readsQoderCredits() {
        let jsonl = [
            assistantLine("2026-01-01T10:00:00Z", id: "a", credits: 0.25),
            assistantLine("2026-01-01T11:00:00Z", id: "b", credits: 1.5),
        ].joined(separator: "\n")
        let events = TranscriptUsage.events(fromJSONL: Data(jsonl.utf8))
        let totals = TranscriptUsage.totals(
            events: events, from: date("2026-01-01T00:00:00Z"), to: date("2026-01-02T00:00:00Z"))
        #expect(totals.credits == 1.75)
        #expect(totals.messages == 2)
    }

    @Test func emptyAndCorruptDataGiveNoEvents() {
        #expect(TranscriptUsage.events(fromJSONL: Data()).isEmpty)
        #expect(TranscriptUsage.events(fromJSONL: Data([0xFF, 0x00, 0x0A, 0x7B])).isEmpty)
    }

    @Test func missingDirectoryGivesNoEvents() {
        let missing = URL(filePath: "/nonexistent/friday-\(UUID().uuidString)")
        #expect(TranscriptUsage.events(inDirectory: missing, modifiedSince: .distantPast).isEmpty)
    }

    @Test func readsNestedFilesInDirectory() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(assistantLine("2026-01-01T10:00:00Z", id: "a"), to: "p/one.jsonl", in: home)
        try write(assistantLine("2026-01-01T09:00:00Z", id: "b"), to: "p/session/subagents/two.jsonl", in: home)
        try write(assistantLine("2026-01-01T09:30:00Z", id: "c"), to: "p/notes.txt", in: home)
        let events = TranscriptUsage.events(inDirectory: home.appending(path: "p"), modifiedSince: .distantPast)
        #expect(events.map(\.date) == [date("2026-01-01T09:00:00Z"), date("2026-01-01T10:00:00Z")])
    }
}

struct FiveHourWindowTests {
    private func events(_ times: [String]) -> [TranscriptUsage.Event] {
        times.map { TranscriptUsage.Event(date: date($0), input: 1, output: 1) }
    }

    @Test func windowStartsOnTheHourAndLastsFiveHours() throws {
        let window = try #require(
            TranscriptUsage.activeWindow(
                events: events(["2026-01-01T10:42:00Z", "2026-01-01T12:00:00Z"]),
                now: date("2026-01-01T13:00:00Z"), calendar: utc))
        #expect(window.start == date("2026-01-01T10:00:00Z"))
        #expect(window.end == date("2026-01-01T15:00:00Z"))
        #expect(window.messages == 2)
        #expect(window.tokens == 4)
    }

    @Test func activityAfterTheWindowEndsStartsANewOne() throws {
        let window = try #require(
            TranscriptUsage.activeWindow(
                events: events(["2026-01-01T08:10:00Z", "2026-01-01T12:59:00Z", "2026-01-01T13:05:00Z"]),
                now: date("2026-01-01T14:00:00Z"), calendar: utc))
        #expect(window.start == date("2026-01-01T13:00:00Z"))
        #expect(window.messages == 1)
    }

    @Test func noWindowOnceItHasExpired() {
        #expect(
            TranscriptUsage.activeWindow(
                events: events(["2026-01-01T08:10:00Z"]), now: date("2026-01-01T13:00:00Z"), calendar: utc) == nil)
        #expect(TranscriptUsage.activeWindow(events: [], now: .now) == nil)
    }

    @Test func futureEventsAreIgnored() {
        #expect(
            TranscriptUsage.activeWindow(
                events: events(["2026-01-01T15:00:00Z"]), now: date("2026-01-01T13:00:00Z"), calendar: utc) == nil)
    }
}

struct StatusLineTests {
    @Test func parsesSnapshotWrittenByTheScript() throws {
        let json = """
            {"captured_at":1738420000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},
            "seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}
            """
        let snapshot = try #require(ClaudeStatusLine.parse(Data(json.utf8)))
        #expect(snapshot.fiveHour?.usedPercent == 23.5)
        #expect(snapshot.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
        #expect(snapshot.sevenDay?.usedPercent == 41.2)
        #expect(snapshot.capturedAt == Date(timeIntervalSince1970: 1_738_420_000))
    }

    @Test func parsesRawStatusLineInputWithOneWindow() throws {
        let json = """
            {"model":{"display_name":"Opus"},"cwd":"/x","rate_limits":{"seven_day":{"used_percentage":5}}}
            """
        let snapshot = try #require(ClaudeStatusLine.parse(Data(json.utf8)))
        #expect(snapshot.fiveHour == nil)
        #expect(snapshot.sevenDay == .init(usedPercent: 5, resetsAt: nil))
    }

    @Test func noLimitsOrCorruptIsNil() {
        #expect(ClaudeStatusLine.parse(Data(#"{"model":{"display_name":"Opus"}}"#.utf8)) == nil)
        #expect(ClaudeStatusLine.parse(Data(#"{"rate_limits":{}}"#.utf8)) == nil)
        #expect(ClaudeStatusLine.parse(Data("{oops".utf8)) == nil)
        #expect(ClaudeStatusLine.parse(Data()) == nil)
    }

    @Test func limitPastItsResetReadsAsFresh() {
        let limit = ClaudeStatusLine.Limit(usedPercent: 80, resetsAt: Date(timeIntervalSince1970: 100))
        #expect(ClaudeStatusLine.current(limit, now: Date(timeIntervalSince1970: 99)) == limit)
        #expect(ClaudeStatusLine.current(limit, now: Date(timeIntervalSince1970: 100)).usedPercent == 0)
    }

    @Test func readsFromHomeAndFallsBackToFileDate() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(ClaudeStatusLine.read(home: home) == nil)
        try write(
            #"{"rate_limits":{"five_hour":{"used_percentage":10}}}"#, to: ClaudeStatusLine.snapshotPath, in: home)
        let snapshot = try #require(ClaudeStatusLine.read(home: home))
        #expect(snapshot.capturedAt != nil)
    }
}

struct UsageFormatTests {
    @Test func percentages() {
        #expect(UsageFormat.percentUsed(0.15) == "15% used")
        #expect(UsageFormat.percentLeft(0.15) == "85% left")
        #expect(UsageFormat.percentUsed(0.999) == "99% used")
        #expect(UsageFormat.percentUsed(0.001) == "1% used")
        #expect(UsageFormat.percentUsed(0) == "0% used")
        #expect(UsageFormat.percentUsed(1.7) == "100% used")
        #expect(UsageFormat.percentLeft(-0.2) == "100% left")
    }

    @Test func clampAndLevel() {
        #expect(UsageFormat.clamp(nil) == nil)
        #expect(UsageFormat.clamp(.nan) == nil)
        #expect(UsageFormat.clamp(2) == 1)
        #expect(UsageFormat.level(0.5) == .normal)
        #expect(UsageFormat.level(0.8) == .warning)
        #expect(UsageFormat.level(0.95) == .critical)
    }

    @Test func resetTimes() {
        let now = date("2026-01-02T09:00:00Z")  // a Friday
        #expect(UsageFormat.resets(at: now + 2 * 3600 + 14 * 60, now: now) == "resets in 2 h 14 m")
        #expect(UsageFormat.resets(at: now + 3 * 3600, now: now) == "resets in 3 h")
        #expect(UsageFormat.resets(at: now + 59, now: now) == "resets in 1 m")
        #expect(UsageFormat.resets(at: now + 600, now: now, estimate: true) == "resets in about 10 m")
        #expect(UsageFormat.resets(at: now - 1, now: now) == "reset")
        let later = UsageFormat.resets(at: now + 7 * 24 * 3600, now: now, calendar: utc)
        #expect(later.hasPrefix("resets Fri"))
        #expect(later.contains("9:00"))
    }

    @Test func activityAndAge() {
        #expect(UsageFormat.activity(messages: 1, tokens: 812) == "1 message · 812 tokens")
        #expect(UsageFormat.activity(messages: 84, tokens: 1_200_000) == "84 messages · 1.2M tokens")
        let now = Date(timeIntervalSince1970: 10_000)
        #expect(UsageFormat.ago(now - 10, now: now) == "just now")
        #expect(UsageFormat.ago(now - 180, now: now) == "3 min ago")
        #expect(UsageFormat.ago(now - 7200, now: now) == "2 h ago")
    }
}

struct ClaudeProviderTests {
    @Test func usesStatusLineLimitsWhenPresent() {
        let now = Date(timeIntervalSince1970: 1000)
        let snapshot = ClaudeStatusLine.Snapshot(
            fiveHour: .init(usedPercent: 15, resetsAt: now + 3600),
            sevenDay: .init(usedPercent: 60, resetsAt: now + 86400), capturedAt: now - 120)
        let meters = ClaudeUsageProvider.meters(snapshot: snapshot, window: nil, now: now)
        #expect(meters.map(\.usedFraction) == [0.15, 0.6])
        #expect(meters[0].resetIsEstimate == false)
        #expect(ClaudeUsageProvider.source(snapshot: snapshot, now: now) == "Claude Code status line · 2 min ago")
    }

    @Test func withoutStatusLineShowsLocalEstimateAndNoFakeLimit() {
        let now = date("2026-01-01T12:00:00Z")
        let window = TranscriptUsage.Window(
            start: date("2026-01-01T10:00:00Z"), end: date("2026-01-01T15:00:00Z"), messages: 3, tokens: 1500,
            credits: 0, lastActivity: now)
        let meters = ClaudeUsageProvider.meters(snapshot: nil, window: window, now: now)
        #expect(meters.allSatisfy { $0.usedFraction == nil })
        #expect(meters[0].resetsAt == window.end)
        #expect(meters[0].resetIsEstimate)
        #expect(meters[0].detail == "3 messages · 1.5K tokens")
        #expect(meters[1].note?.contains("Not available offline") == true)
    }

    @Test func countsOnlySessionsWhoseProcessRuns() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write(#"{"pid":101,"status":"busy","updatedAt":0}"#, to: ".claude/sessions/101.json", in: home)
        try write(#"{"pid":102,"status":"idle","updatedAt":0}"#, to: ".claude/sessions/102.json", in: home)
        try write(#"{"pid":103,"status":"busy"}"#, to: ".claude/sessions/103.json", in: home)
        try write("not json", to: ".claude/sessions/104.json", in: home)
        try write("secret", to: ".claude/sessions/101.key", in: home)
        let processes = ProcessList.Snapshot(names: [101: "2.1.0", 102: "claude"])
        let sessions = ClaudeUsageProvider.codeSessions(home: home, processes: processes, now: .now)
        #expect(sessions == .init(open: 2, working: 1))
        #expect(
            ClaudeUsageProvider.liveDetail(sessions: sessions, desktopOpen: true)
                == "Code: 2 sessions (1 working) · Desktop app open")
        #expect(ClaudeUsageProvider.liveDetail(sessions: .init(), desktopOpen: false) == nil)
    }

    @Test func fallsBackToRecentUpdatesWhenProcessesUnknown() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_000_000)
        try write(#"{"pid":1,"status":"idle","updatedAt":999900000}"#, to: ".claude/sessions/1.json", in: home)
        try write(#"{"pid":2,"status":"idle","updatedAt":1000}"#, to: ".claude/sessions/2.json", in: home)
        #expect(ClaudeUsageProvider.codeSessions(home: home, processes: nil, now: now).open == 1)
    }

    @Test func endToEndWithSyntheticHome() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date.now
        let stamp = (now - 600).formatted(.iso8601)
        try write(assistantLine(stamp, id: "m1", input: 100, output: 100), to: ".claude/projects/p/s.jsonl", in: home)
        let env = UsageEnvironment(home: home, now: now, runningBundleIDs: [], processes: nil)
        let usage = ClaudeUsageProvider().usage(in: env)
        #expect(usage.isInstalled)
        #expect(!usage.isLive)
        #expect(usage.meters.first?.detail == "1 message · 200 tokens")
    }

    @Test func missingEverythingIsNotInstalled() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let env = UsageEnvironment(home: home, now: .now, runningBundleIDs: [], processes: nil)
        for provider in AIUsageMonitor.defaultProviders {
            #expect(provider.usage(in: env).isInstalled == false, "\(provider.tool)")
        }
    }
}

struct WisprFlowProviderTests {
    private let config = """
        {"prefs":{"cache":{"statistics":{"wordsThisWeek":1234,"wordsToday":200,
        "lastTranscriptTimestamp":"2026-01-06T10:00:00.000Z"}},
        "user":{"email":"ignored","subscription":{"plan":"FLOW_BASIC","isSubscribed":false},
        "notetakerQuota":{"counted":5,"limit":50,"weekStartedAt":"2026-01-05T00:00:00Z","resetsAt":"2026-01-12T00:00:00Z"},
        "userStats":{"firstWeeklyLimitHitAt":1}}}}
        """

    @Test func showsWordsAndNotetakerQuota() throws {
        let parsed = try #require(WisprFlowUsageProvider.parse(Data(config.utf8)))
        let meters = WisprFlowUsageProvider.meters(config: parsed, now: date("2026-01-07T00:00:00Z"))
        #expect(meters.count == 2)
        #expect(meters[0].detail == "1,234 words")
        #expect(meters[0].usedFraction == nil)
        #expect(meters[0].resetsAt == date("2026-01-12T00:00:00Z"))
        #expect(meters[1].usedFraction == 0.1)
        #expect(meters[1].detail == "5 of 50 this week")
    }

    @Test func limitHitThisWeekFillsTheBar() throws {
        let hit = config.replacingOccurrences(
            of: #""firstWeeklyLimitHitAt":1"#, with: #""firstWeeklyLimitHitAt":1767610000"#)
        let parsed = try #require(WisprFlowUsageProvider.parse(Data(hit.utf8)))
        let meters = WisprFlowUsageProvider.meters(config: parsed, now: date("2026-01-07T00:00:00Z"))
        #expect(meters[0].usedFraction == 1)
        #expect(meters[0].note == "Weekly word limit reached")
    }

    @Test func lastWeeksCountReadsAsZero() throws {
        let old = config.replacingOccurrences(of: "2026-01-06T10:00:00.000Z", with: "2026-01-01T10:00:00.000Z")
        let parsed = try #require(WisprFlowUsageProvider.parse(Data(old.utf8)))
        #expect(WisprFlowUsageProvider.meters(config: parsed, now: date("2026-01-07T00:00:00Z"))[0].detail == "0 words")
    }

    @Test func planNamesAndCorruptConfig() {
        #expect(WisprFlowUsageProvider.planName("FLOW_BASIC") == "Basic")
        #expect(WisprFlowUsageProvider.planName("FLOW_PRO_TEAM") == "Pro Team")
        #expect(WisprFlowUsageProvider.parse(Data("[1,2".utf8)) == nil)
        let empty = WisprFlowUsageProvider.parse(Data("{}".utf8))!
        #expect(WisprFlowUsageProvider.meters(config: empty, now: .now).isEmpty)
    }
}

struct OpenCodeProviderTests {
    @Test func corruptDatabaseIsUnreadable() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try write("not a database", to: OpenCodeUsageProvider.databasePath, in: home)
        #expect(
            OpenCodeUsageProvider.totals(
                databaseAt: home.appending(path: OpenCodeUsageProvider.databasePath), since: .distantPast) == nil)
        let env = UsageEnvironment(home: home, now: .now, runningBundleIDs: [], processes: nil)
        let usage = OpenCodeUsageProvider().usage(in: env)
        #expect(usage.isInstalled)
        #expect(usage.meters.isEmpty)
    }

    @Test func sumsTodaysSessions() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appending(path: "opencode.db")
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        let sql = """
            CREATE TABLE session_v2 (id TEXT, title TEXT, cost REAL, tokens_input INTEGER, tokens_output INTEGER,
              tokens_reasoning INTEGER, tokens_cache_read INTEGER, tokens_cache_write INTEGER, time_updated INTEGER);
            INSERT INTO session_v2 VALUES ('a', 't', 0.5, 100, 50, 10, 9999, 5, 2000000);
            INSERT INTO session_v2 VALUES ('b', 't', 0.25, 1, 1, 0, 0, 0, 3000000);
            INSERT INTO session_v2 VALUES ('c', 't', 9, 1000, 1000, 0, 0, 0, 10);
            """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let totals = try #require(
            OpenCodeUsageProvider.totals(databaseAt: url, since: Date(timeIntervalSince1970: 1000)))
        #expect(totals.sessions == 2)
        #expect(totals.tokens == 167)
        #expect(totals.cost == 0.75)
        #expect(totals.lastUpdated == Date(timeIntervalSince1970: 3000))
    }

    @Test func meterText() {
        let meter = OpenCodeUsageProvider.meter(today: .init(sessions: 2, tokens: 48_000, cost: 0))
        #expect(meter.detail == "2 sessions · 48K tokens")
        #expect(meter.usedFraction == nil)
    }
}

struct ProcessListTests {
    @Test func listsThisProcess() throws {
        let snapshot = try #require(ProcessList.current())
        #expect(snapshot.isAlive(ProcessInfo.processInfo.processIdentifier))
    }
}
