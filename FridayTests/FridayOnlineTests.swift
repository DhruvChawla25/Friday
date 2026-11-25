// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

// Synthetic data only. No real Friday Online app is contacted.

private final class FakeConnector: FridayOnlineConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [FridayOnline.Provider: OnlineLimits]
    private(set) var calls: [FridayOnline.Provider] = []
    var delay: Duration?

    init(_ answers: [FridayOnline.Provider: OnlineLimits]) { self.answers = answers }

    var callCount: Int { lock.withLock { calls.count } }

    func usageLimits(for provider: FridayOnline.Provider) async -> OnlineLimits {
        lock.withLock { calls.append(provider) }
        if let delay { try? await Task.sleep(for: delay) }
        return lock.withLock { answers[provider] } ?? .report(.init(provider: provider, status: .unsupported))
    }
}

private let now = Date(timeIntervalSince1970: 2_000_000_000)

private func okReport(fetched: Date = now - 30) -> FridayOnline.Report {
    FridayOnline.Report(
        provider: .claude, status: .ok,
        windows: [
            .init(window: .fiveHour, usedPercent: 42, resetsAt: now + 3600),
            .init(window: .weekly, usedPercent: 10, resetsAt: now + 5 * 86400),
            .init(window: .weeklyOpus, usedPercent: 3, resetsAt: now + 5 * 86400),
        ], fetchedAt: fetched)
}

private func snapshot(age: TimeInterval) -> ClaudeStatusLine.Snapshot {
    ClaudeStatusLine.Snapshot(
        fiveHour: .init(usedPercent: 15, resetsAt: now + 1800), sevenDay: .init(usedPercent: 60, resetsAt: nil),
        capturedAt: now - age)
}

private let window = TranscriptUsage.Window(
    start: now - 3600, end: now + 4 * 3600, messages: 12, tokens: 34_000, credits: 0, lastActivity: now - 60)

struct LimitsPrecedenceTests {
    @Test func freshStatusLineWinsOverFridayOnline() throws {
        let limits = try #require(
            LimitsMerge.claudeLimits(statusLine: snapshot(age: 60), online: .report(okReport()), now: now))
        #expect(limits.origin == .statusLine)
        #expect(limits.fiveHour?.usedPercent == 15)
    }

    @Test func fridayOnlineWinsOverStaleStatusLine() throws {
        let limits = try #require(
            LimitsMerge.claudeLimits(statusLine: snapshot(age: 3600), online: .report(okReport()), now: now))
        #expect(limits.origin == .fridayOnline)
        #expect(limits.fiveHour?.usedPercent == 42)
        #expect(limits.weeklyOpus?.usedPercent == 3)
        #expect(limits.updatedAt == now - 30)
    }

    @Test func staleStatusLineIsUsedWhenFridayOnlineHasNothing() throws {
        for online in [
            OnlineLimits.notRunning, .invalidReply, .report(.init(provider: .claude, status: .upstreamError)),
        ] {
            let limits = try #require(
                LimitsMerge.claudeLimits(statusLine: snapshot(age: 3600), online: online, now: now))
            #expect(limits.origin == .statusLine)
        }
    }

    @Test func nothingFromEitherIsNil() {
        #expect(LimitsMerge.claudeLimits(statusLine: nil, online: .notRunning, now: now) == nil)
        #expect(LimitsMerge.claudeLimits(statusLine: nil, online: nil, now: now) == nil)
        let empty = FridayOnline.Report(provider: .claude, status: .ok, windows: [])
        #expect(LimitsMerge.claudeLimits(statusLine: nil, online: .report(empty), now: now) == nil)
    }
}

struct ClaudeBarMergeTests {
    @Test func barShowsOnlineLimitAndLocalUsage() throws {
        let limits = LimitsMerge.claudeLimits(statusLine: nil, online: .report(okReport()), now: now)
        let meters = ClaudeUsageProvider.meters(limits: limits, window: window, now: now)
        #expect(meters.map(\.window) == ["5-hour session", "Weekly", "Weekly · Opus"])
        #expect(meters[0].usedFraction == 0.42)
        #expect(meters[0].resetsAt == now + 3600)
        #expect(meters[0].resetIsEstimate == false)
        #expect(meters[0].detail == "12 messages · 34K tokens")
        #expect(meters[1].usedFraction == 0.1)
        let source = ClaudeUsageProvider.source(limits: limits, online: .report(okReport()), now: now)
        #expect(source == "Friday Online app · just now")
    }

    @Test func appNotRunningFallsBackQuietly() {
        let meters = ClaudeUsageProvider.meters(limits: nil, window: window, now: now)
        #expect(meters.allSatisfy { $0.usedFraction == nil })
        #expect(meters[0].resetIsEstimate)
        #expect(
            ClaudeUsageProvider.source(limits: nil, online: .notRunning, now: now)
                == "Local Claude Code transcripts · Friday Online app not running")
    }

    @Test func statusLineSourceMentionsFridayOnlineProblem() {
        let limits = LimitsMerge.claudeLimits(statusLine: snapshot(age: 120), online: .notRunning, now: now)
        #expect(
            ClaudeUsageProvider.source(limits: limits, online: .notRunning, now: now)
                == "Claude Code status line · 2 min ago · Friday Online app not running")
        #expect(
            ClaudeUsageProvider.source(limits: limits, online: nil, now: now) == "Claude Code status line · 2 min ago")
    }

    @Test func everyStatusHasAnHonestLabel() {
        func problem(_ status: FridayOnline.Status) -> String? {
            LimitsMerge.problem(.report(.init(provider: .claude, status: status)))
        }
        #expect(problem(.credentialsExpired) == "Friday Online: credentials expired · open Claude Code to refresh")
        #expect(problem(.credentialsMissing)?.contains("sign in to Claude Code") == true)
        #expect(problem(.upstreamError) == "Friday Online: upstream error")
        #expect(problem(.unreachable) == "Friday Online: can't reach the provider")
        #expect(problem(.unsupported) == "Friday Online: unsupported for this tool")
        #expect(problem(.ok) == "Friday Online returned no limits")
        #expect(LimitsMerge.problem(.report(okReport())) == nil)
        #expect(LimitsMerge.problem(.notRunning) == "Friday Online app not running")
        #expect(LimitsMerge.problem(.invalidReply) == "Friday Online app sent an unexpected reply")
        #expect(LimitsMerge.problem(nil) == nil)
    }

    @Test func endToEndThroughTheEnvironment() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "friday-online-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appending(path: ".claude/projects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        var env = UsageEnvironment(home: home, now: now, runningBundleIDs: [], processes: nil)
        env.online = [.claude: .report(okReport())]
        let usage = ClaudeUsageProvider().usage(in: env)
        #expect(usage.meters.first?.usedFraction == 0.42)
        #expect(usage.source.hasPrefix("Friday Online app"))
    }
}

struct OtherToolsMergeTests {
    private let local = ToolUsage(
        tool: .qoder, isInstalled: true, meters: [UsageMeter(window: "Today", detail: "3 credits")],
        source: "Local Qoder transcripts")

    @Test func unsupportedLeavesLocalReadingAlone() {
        let unsupported = OnlineLimits.report(.init(provider: .qoder, status: .unsupported))
        #expect(LimitsMerge.apply(unsupported, to: local, now: now) == local)
        #expect(LimitsMerge.apply(.notRunning, to: local, now: now) == local)
        #expect(LimitsMerge.apply(nil, to: local, now: now) == local)
    }

    @Test func okReportAddsBarsOnTop() {
        var report = okReport()
        report.provider = .qoder
        let merged = LimitsMerge.apply(.report(report), to: local, now: now)
        #expect(merged.meters.map(\.window) == ["5-hour session", "Weekly", "Today"])
        #expect(merged.source == "Friday Online app · just now")
    }

    @Test func notInstalledToolStaysHidden() {
        let missing = ToolUsage.notInstalled(.qoder)
        #expect(LimitsMerge.apply(.report(okReport()), to: missing, now: now) == missing)
    }
}

struct FridayOnlineProviderTests {
    @Test func asksAtMostOncePerMinute() async {
        let fake = FakeConnector([.claude: .report(okReport())])
        let provider = FridayOnlineProvider(makeConnector: { fake })
        let first = await provider.limits(for: [.claude], now: now)
        _ = await provider.limits(for: [.claude], now: now + 30)
        #expect(fake.callCount == 1)
        #expect(first[.claude] == .report(okReport()))
        _ = await provider.limits(for: [.claude], now: now + 61)
        #expect(fake.callCount == 2)
    }

    @Test func mapsEveryToolToItsProvider() async {
        let fake = FakeConnector([:])
        let provider = FridayOnlineProvider(makeConnector: { fake })
        let result = await provider.limits(for: AITool.allCases, now: now)
        #expect(Set(fake.calls) == [.claude, .antigravity, .qwenCode, .qoder, .wisprFlow, .openCode])
        #expect(result[.wisprFlow] == .report(.init(provider: .wisprFlow, status: .unsupported)))
    }

    @Test func noServiceReportsNotRunning() async {
        let fake = FakeConnector([.claude: .notRunning])
        let provider = FridayOnlineProvider(makeConnector: { fake })
        #expect(await provider.limits(for: [.claude], now: now)[.claude] == .notRunning)
    }

    @Test func slowConnectorTimesOutAsNotRunning() async {
        let fake = FakeConnector([.claude: .report(okReport())])
        fake.delay = .seconds(30)
        let provider = FridayOnlineProvider(makeConnector: { fake }, timeout: .milliseconds(50))
        #expect(await provider.limits(for: [.claude], now: now)[.claude] == .notRunning)
    }
}

struct FridayOnlineWireTests {
    @Test func decodesToolCallReply() throws {
        let json = """
            {"jsonrpc":"2.0","id":2,"result":{"isError":false,"content":[],"structuredContent":{
            "provider":"claude","status":"ok","source":"anthropic-oauth-usage","fetchedAt":"2033-05-18T03:33:00Z",
            "windows":[{"window":"5h","usedPercent":42.5,"resetsAt":"2033-05-18T05:00:00Z"},
            {"window":"weekly-sonnet","usedPercent":1}]}}}
            """
        let report = try #require(FridayOnlineConnector.report(fromReply: Data(json.utf8), id: 2))
        #expect(report.status == .ok)
        #expect(report.windows.count == 2)
        #expect(report.windows[0].usedPercent == 42.5)
        #expect(report.windows[1].resetsAt == nil)
    }

    @Test func rejectsWrongIDErrorsAndUnknownValues() {
        let ok = """
            {"jsonrpc":"2.0","id":2,"result":{"isError":false,"structuredContent":{"provider":"claude","status":"ok","windows":[]}}}
            """
        #expect(FridayOnlineConnector.report(fromReply: Data(ok.utf8), id: 3) == nil)
        let error = #"{"jsonrpc":"2.0","id":2,"error":{"code":-32602,"message":"x"}}"#
        #expect(FridayOnlineConnector.report(fromReply: Data(error.utf8), id: 2) == nil)
        let unknown = ok.replacingOccurrences(of: #""status":"ok""#, with: #""status":"maybe""#)
        #expect(FridayOnlineConnector.report(fromReply: Data(unknown.utf8), id: 2) == nil)
        let isError = ok.replacingOccurrences(of: #""isError":false"#, with: #""isError":true"#)
        #expect(FridayOnlineConnector.report(fromReply: Data(isError.utf8), id: 2) == nil)
        #expect(FridayOnlineConnector.report(fromReply: Data("garbage".utf8), id: 2) == nil)
    }
}
