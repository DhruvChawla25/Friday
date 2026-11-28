// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// The fixed AppleScript and JavaScript Friday uses for media, plus the pure
/// parsing of their results (unit tested). Scripts are constants; only
/// numeric window and tab IDs are ever put into them.
enum MediaScripts {
    // MARK: Spotify

    static let spotifyID = MediaApp.spotify.bundleID

    /// Returns "closed", "stopped", or "<state>\t<track>\t<artist>".
    static let spotifyRead = """
        if application id "\(spotifyID)" is not running then return "closed"
        set sep to character id 9
        with timeout of 2 seconds
            tell application id "\(spotifyID)"
                set s to player state as text
                if s is "stopped" then return "stopped"
                set n to name of current track
                set a to artist of current track
            end tell
        end timeout
        return s & sep & n & sep & a
        """

    static func spotify(_ control: MediaItem.Control) -> String? {
        let command: String
        switch control {
        case .playPause: command = "playpause"
        case .next: command = "next track"
        case .previous: command = "previous track"
        case .reveal: command = "activate"
        }
        return """
            if application id "\(spotifyID)" is running then
                with timeout of 2 seconds
                    tell application id "\(spotifyID)" to \(command)
                end timeout
            end if
            """
    }

    static func parseSpotify(_ text: String) -> MediaItem? {
        let parts = text.components(separatedBy: "\t")
        guard parts.count >= 3, !parts[1].isEmpty else { return nil }
        let state: MediaItem.State =
            switch parts[0] {
            case "playing": .playing
            case "paused": .paused
            default: .unknown
            }
        return MediaItem(
            id: "spotify", source: .spotify, title: parts[1], subtitle: parts[2].isEmpty ? nil : parts[2],
            state: state, controls: [.playPause, .next, .previous, .reveal])
    }

    // MARK: Chrome (YouTube and YouTube Music tabs)

    static let chromeID = MediaApp.chrome.bundleID

    /// URL prefixes of media tabs. Every other tab is skipped inside the
    /// script, so its title and URL never reach Friday.
    static let mediaPrefixes = [
        "https://www.youtube.com/watch", "https://youtube.com/watch", "https://m.youtube.com/watch",
        "https://www.youtube.com/shorts/", "https://music.youtube.com/",
    ]

    /// Reads playback facts only (paused, Media Session title and artist),
    /// never page text. Single quotes only, so it fits in an AppleScript string.
    static let readJS =
        "(function(){var v=document.querySelector('video');var ms=navigator.mediaSession;var m=ms&&ms.metadata;"
        + "return JSON.stringify({p:v?v.paused:null,s:ms?ms.playbackState:null,"
        + "t:m?m.title:null,a:m?m.artist:null});})()"

    static let toggleJS =
        "(function(){var v=document.querySelector('video');if(!v)return 'none';if(v.paused){v.play();}else{v.pause();}return 'ok';})()"

    static let nextJS =
        "(function(){var b=document.querySelector('.ytp-next-button, ytmusic-player-bar .next-button');"
        + "if(b){b.click();return 'ok';}return 'none';})()"

    static let previousJS =
        "(function(){var b=document.querySelector('ytmusic-player-bar .previous-button');if(b){b.click();return 'ok';}"
        + "var v=document.querySelector('video');if(v){v.currentTime=0;return 'ok';}return 'none';})()"

    /// One line per media tab: window id, tab id, URL, title, JS result (or "!ERR <n>").
    static var chromeRead: String {
        let conditions = mediaPrefixes.map { "u starts with \"\($0)\"" }.joined(separator: " or ")
        return """
            if application id "\(chromeID)" is not running then return ""
            set out to ""
            set sep to character id 9
            with timeout of 3 seconds
                tell application id "\(chromeID)"
                    repeat with w in windows
                        set wid to id of w
                        repeat with t in tabs of w
                            set u to URL of t
                            if \(conditions) then
                                set js to ""
                                try
                                    set js to execute t javascript "\(readJS)"
                                on error number n
                                    set js to "!ERR " & n
                                end try
                                set out to out & wid & sep & (id of t) & sep & u & sep & (title of t) & sep & js & linefeed
                            end if
                        end repeat
                    end repeat
                end tell
            end timeout
            return out
            """
    }

    static func chrome(_ control: MediaItem.Control, window: Int, tab: Int) -> String {
        let target = "tab id \(tab) of window id \(window)"
        switch control {
        case .reveal:
            return """
                tell application id "\(chromeID)"
                    set w to window id \(window)
                    set i to 0
                    repeat with t in tabs of w
                        set i to i + 1
                        if id of t is \(tab) then set active tab index of w to i
                    end repeat
                    set index of w to 1
                    activate
                end tell
                """
        case .playPause, .next, .previous:
            let js =
                control == .playPause ? toggleJS : control == .next ? nextJS : previousJS
            return """
                with timeout of 2 seconds
                    tell application id "\(chromeID)" to execute \(target) javascript "\(js)"
                end timeout
                """
        }
    }

    struct ChromeReading: Equatable, Sendable {
        var items: [MediaItem]
        /// Chrome refused to run JavaScript (View → Developer → Allow JavaScript from Apple Events is off).
        var javaScriptBlocked: Bool
    }

    private struct TabState: Decodable {
        var p: Bool?
        var s: String?
        var t: String?
        var a: String?
    }

    static func parseChrome(_ text: String) -> ChromeReading {
        var items: [MediaItem] = []
        var blocked = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 5, let window = Int(parts[0]), let tab = Int(parts[1]),
                let source = source(forURL: parts[2])
            else { continue }
            var title = cleanTitle(parts[3])
            var subtitle: String?
            var state = MediaItem.State.unknown
            var controls: Set<MediaItem.Control> = [.reveal]
            let js = parts[4...].joined(separator: "\t")
            if js.hasPrefix("!ERR") {
                blocked = true
            } else if let data = js.data(using: .utf8), let facts = try? JSONDecoder().decode(TabState.self, from: data)
            {
                controls.formUnion([.playPause, .next, .previous])
                if let paused = facts.p {
                    state = paused ? .paused : .playing
                } else if facts.s == "playing" {
                    state = .playing
                } else if facts.s == "paused" {
                    state = .paused
                }
                if source == .youtubeMusic, let song = facts.t, !song.isEmpty {
                    title = song
                    subtitle = facts.a
                }
            }
            items.append(
                MediaItem(
                    id: "chrome:\(window):\(tab)", source: source, title: title, subtitle: subtitle, state: state,
                    controls: controls, chromeWindowID: window, chromeTabID: tab))
        }
        return ChromeReading(items: items, javaScriptBlocked: blocked)
    }

    static func source(forURL url: String) -> MediaItem.Source? {
        guard mediaPrefixes.contains(where: url.hasPrefix) else { return nil }
        return url.hasPrefix("https://music.youtube.com/") ? .youtubeMusic : .youtube
    }

    /// "(3) Song name - YouTube" → "Song name".
    static func cleanTitle(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("("), let close = text.firstIndex(of: ")"),
            Int(text[text.index(after: text.startIndex)..<close]) != nil
        {
            text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }
        for suffix in [" - YouTube Music", " - YouTube"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
            break
        }
        return text.isEmpty ? "YouTube" : text
    }

    /// Playing first, then Spotify, then tabs in window order.
    static func sorted(_ items: [MediaItem]) -> [MediaItem] {
        items.enumerated().sorted { lhs, rhs in
            let l = lhs.element.state == .playing ? 0 : 1
            let r = rhs.element.state == .playing ? 0 : 1
            return l != r ? l < r : lhs.offset < rhs.offset
        }.map(\.element)
    }
}
