// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// "what's playing", "pause music", "next song" for Spotify and YouTube tabs.
struct MediaSkill: Skill {
    enum Action: Equatable, Sendable { case nowPlaying, playPause, next, previous }

    let name = "Media"
    let example = "what's playing  ·  pause music  ·  next song"

    let perform: @Sendable (Action) async -> String

    static let phrases: [String: Action] = [
        "what's playing": .nowPlaying, "whats playing": .nowPlaying, "what is playing": .nowPlaying,
        "now playing": .nowPlaying, "what song is this": .nowPlaying,
        "pause": .playPause, "pause music": .playPause, "play": .playPause, "play music": .playPause,
        "resume": .playPause, "resume music": .playPause, "play pause": .playPause, "pause video": .playPause,
        "play video": .playPause, "pause youtube": .playPause, "pause spotify": .playPause,
        "play spotify": .playPause,
        "next": .next, "next song": .next, "next track": .next, "skip": .next, "skip song": .next,
        "next video": .next,
        "previous": .previous, "previous song": .previous, "previous track": .previous, "last song": .previous,
        "previous video": .previous,
    ]

    static func action(for command: Command) -> Action? {
        phrases[command.normalized.replacingOccurrences(of: "’", with: "'")]
    }

    func canHandle(_ command: Command) -> Bool { Self.action(for: command) != nil }

    func handle(_ command: Command) async -> String {
        guard let action = Self.action(for: command) else { return "Not recognised." }
        return await perform(action)
    }
}
