// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Wispr Flow: its `config.json` caches word statistics, the plan name, when
/// the weekly word limit was last hit, and the Notetaker quota (meetings
/// counted / limit / reset). Friday decodes only those fields; the file's
/// other contents (name, email, dictionary) are never read into Friday.
struct WisprFlowUsageProvider: UsageProvider {
    let tool = AITool.wisprFlow
    static let configPath = "Library/Application Support/Wispr Flow/config.json"

    struct Config: Decodable, Equatable {
        struct Prefs: Decodable, Equatable {
            struct Cache: Decodable, Equatable {
                struct Statistics: Decodable, Equatable {
                    var wordsThisWeek: Int?
                    var wordsToday: Int?
                    var lastTranscriptTimestamp: String?
                }
                var statistics: Statistics?
            }
            struct User: Decodable, Equatable {
                struct Subscription: Decodable, Equatable {
                    var plan: String?
                    var isSubscribed: Bool?
                }
                struct Quota: Decodable, Equatable {
                    var counted: Int?
                    var limit: Int?
                    var weekStartedAt: String?
                    var resetsAt: String?
                }
                struct Stats: Decodable, Equatable {
                    var firstWeeklyLimitHitAt: Double?
                }
                var subscription: Subscription?
                var notetakerQuota: Quota?
                var userStats: Stats?
            }
            var cache: Cache?
            var user: User?
        }
        var prefs: Prefs?
    }

    static func parse(_ data: Data) -> Config? {
        try? JSONDecoder().decode(Config.self, from: data)
    }

    func usage(in env: UsageEnvironment) -> ToolUsage {
        let url = env.url(Self.configPath)
        let data = try? Data(contentsOf: url)
        guard data != nil || env.isAppInstalled(tool) else { return .notInstalled(tool) }
        var usage = ToolUsage(
            tool: tool, isInstalled: true, isLive: env.isRunning(tool),
            liveDetail: env.isRunning(tool) ? "App open" : nil, source: "Wispr Flow's local settings file")
        guard let data, let config = Self.parse(data) else {
            usage.source = "No local usage data found"
            return usage
        }
        usage.meters = Self.meters(config: config, now: env.now)
        usage.lastActive = config.prefs?.cache?.statistics?.lastTranscriptTimestamp.flatMap(
            TranscriptUsage.parseDate)
        if let plan = config.prefs?.user?.subscription?.plan {
            usage.source += " · plan \(Self.planName(plan))"
        }
        return usage
    }

    /// "FLOW_BASIC" → "Basic".
    static func planName(_ raw: String) -> String {
        let words = raw.split(separator: "_").filter { $0.uppercased() != "FLOW" }
        return words.isEmpty ? raw : words.map { $0.lowercased().capitalized }.joined(separator: " ")
    }

    static func meters(config: Config, now: Date) -> [UsageMeter] {
        let user = config.prefs?.user
        let quota = user?.notetakerQuota
        let weekStart = quota?.weekStartedAt.flatMap(TranscriptUsage.parseDate)
        let weekReset = quota?.resetsAt.flatMap(TranscriptUsage.parseDate).flatMap { $0 > now ? $0 : nil }
        let inCurrentWeek: (Date?) -> Bool = { date in
            guard let date, let weekStart else { return false }
            return date >= weekStart
        }

        var meters: [UsageMeter] = []
        let stats = config.prefs?.cache?.statistics
        let lastDictation = stats?.lastTranscriptTimestamp.flatMap(TranscriptUsage.parseDate)
        // The cached weekly count is stale once a new week starts.
        let staleWeek = weekStart != nil && lastDictation != nil && !inCurrentWeek(lastDictation)
        if let words = stats?.wordsThisWeek {
            let shown = staleWeek ? 0 : words
            let hitLimit = inCurrentWeek(
                user?.userStats?.firstWeeklyLimitHitAt.map { Date(timeIntervalSince1970: $0) })
            let subscribed = user?.subscription?.isSubscribed == true
            meters.append(
                UsageMeter(
                    window: "Words this week",
                    usedFraction: hitLimit && !subscribed ? 1 : nil,
                    detail: "\(shown.formatted()) words",
                    resetsAt: weekReset,
                    note: subscribed
                        ? "No weekly limit on your plan"
                        : hitLimit ? "Weekly word limit reached" : "Weekly word limit not stored offline"
                ))
        }
        if let quota, let limit = quota.limit, limit > 0 {
            let counted = quota.counted ?? 0
            meters.append(
                UsageMeter(
                    window: "Notetaker meetings",
                    usedFraction: Double(counted) / Double(limit),
                    detail: "\(counted) of \(limit) this week",
                    resetsAt: weekReset
                ))
        }
        return meters
    }
}
