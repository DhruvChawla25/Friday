// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Something playing (or paused) right now. In memory only: never saved,
/// logged or added to Friday's memory.
struct MediaItem: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case spotify, youtube, youtubeMusic

        var label: String {
            switch self {
            case .spotify: "Spotify"
            case .youtube: "YouTube"
            case .youtubeMusic: "YouTube Music"
            }
        }
    }

    enum State: Equatable, Sendable { case playing, paused, unknown }

    enum Control: Equatable, Sendable { case playPause, next, previous, reveal }

    /// "spotify", or "chrome:<window id>:<tab id>".
    var id: String
    var source: Source
    var title: String
    var subtitle: String?
    var state: State
    var controls: Set<Control>

    /// Chrome window and tab, for YouTube items.
    var chromeWindowID: Int?
    var chromeTabID: Int?
}

/// The apps Friday can ask what is playing.
enum MediaApp: Equatable, Sendable {
    case spotify, chrome

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .chrome: "com.google.Chrome"
        }
    }

    var name: String {
        switch self {
        case .spotify: "Spotify"
        case .chrome: "Chrome"
        }
    }
}
