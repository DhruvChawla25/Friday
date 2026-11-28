// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation
import Testing

@testable import Friday

struct MediaScriptsTests {
    @Test func parsesSpotify() {
        let item = MediaScripts.parseSpotify("playing\tSong\tArtist")
        #expect(item?.title == "Song")
        #expect(item?.subtitle == "Artist")
        #expect(item?.state == .playing)
        #expect(item?.controls.contains(.next) == true)
        #expect(MediaScripts.parseSpotify("paused\tSong\t")?.subtitle == nil)
        #expect(MediaScripts.parseSpotify("closed") == nil)
        #expect(MediaScripts.parseSpotify("stopped") == nil)
    }

    @Test func classifiesOnlyMediaTabs() {
        #expect(MediaScripts.source(forURL: "https://www.youtube.com/watch?v=abc") == .youtube)
        #expect(MediaScripts.source(forURL: "https://www.youtube.com/shorts/abc") == .youtube)
        #expect(MediaScripts.source(forURL: "https://music.youtube.com/watch?v=abc") == .youtubeMusic)
        #expect(MediaScripts.source(forURL: "https://www.youtube.com/") == nil)
        #expect(MediaScripts.source(forURL: "https://web.whatsapp.com/") == nil)
        #expect(MediaScripts.source(forURL: "https://evil.example/https://www.youtube.com/watch") == nil)
    }

    @Test func cleansTitles() {
        #expect(MediaScripts.cleanTitle("(3) Lo-fi beats - YouTube") == "Lo-fi beats")
        #expect(MediaScripts.cleanTitle("Song - YouTube Music") == "Song")
        #expect(MediaScripts.cleanTitle("(Live) Concert - YouTube") == "(Live) Concert")
        #expect(MediaScripts.cleanTitle("YouTube") == "YouTube")
    }

    @Test func parsesChromeLinesWithAndWithoutJavaScript() {
        let text = [
            "1\t11\thttps://www.youtube.com/watch?v=a\t(2) Video A - YouTube\t{\"p\":false,\"s\":\"playing\",\"t\":\"x\",\"a\":\"y\"}",
            "1\t12\thttps://music.youtube.com/watch?v=b\tYouTube Music\t{\"p\":true,\"s\":\"paused\",\"t\":\"Song\",\"a\":\"Band\"}",
            "2\t21\thttps://www.youtube.com/watch?v=c\tVideo C - YouTube\t!ERR 12",
            "2\t22\thttps://example.com/\tNot media\t",
            "garbage",
        ].joined(separator: "\n")
        let reading = MediaScripts.parseChrome(text)
        #expect(reading.items.map(\.id) == ["chrome:1:11", "chrome:1:12", "chrome:2:21"])
        #expect(reading.items[0].title == "Video A")
        #expect(reading.items[0].state == .playing)
        #expect(reading.items[1].title == "Song")
        #expect(reading.items[1].subtitle == "Band")
        #expect(reading.items[1].state == .paused)
        #expect(reading.items[2].controls == [.reveal])
        #expect(reading.items[2].state == .unknown)
        #expect(reading.javaScriptBlocked)
    }

    @Test func scriptsOnlyEverContainNumbersFromOutside() {
        let script = MediaScripts.chrome(.playPause, window: 5, tab: 9)
        #expect(script.contains("tab id 9 of window id 5"))
        #expect(!MediaScripts.readJS.contains("\""))
        #expect(!MediaScripts.toggleJS.contains("\""))
        #expect(!MediaScripts.nextJS.contains("\""))
        #expect(!MediaScripts.previousJS.contains("\""))
        #expect(!MediaScripts.readJS.contains("innerText"))
    }

    @Test func playingComesFirst() {
        func item(_ id: String, _ state: MediaItem.State) -> MediaItem {
            MediaItem(id: id, source: .youtube, title: id, state: state, controls: [])
        }
        let sorted = MediaScripts.sorted([item("a", .paused), item("b", .playing), item("c", .unknown)])
        #expect(sorted.map(\.id) == ["b", "a", "c"])
    }

    @MainActor @Test func describesNowPlaying() {
        let items = [
            MediaItem(id: "s", source: .spotify, title: "Song", subtitle: "Artist", state: .playing, controls: []),
            MediaItem(id: "y", source: .youtube, title: "Video", state: .paused, controls: []),
        ]
        #expect(MediaCenter.describe(items) == "Playing on Spotify: Song by Artist. Paused on YouTube: Video.")
    }
}

struct MediaSkillTests {
    @Test(arguments: ["what's playing", "pause music", "next song", "Skip", "previous track", "play"])
    func handlesMediaPhrases(_ text: String) {
        #expect(MediaSkill { _ in "" }.canHandle(Command(text)))
    }

    @Test func ignoresOtherCommands() {
        #expect(!MediaSkill { _ in "" }.canHandle(Command("open spotify")))
        #expect(!MediaSkill { _ in "" }.canHandle(Command("play chess")))
    }

    @Test func routesTheAction() async {
        let skill = MediaSkill { action in "\(action)" }
        #expect(await skill.handle(Command("next song")) == "next")
        #expect(await skill.handle(Command("What's playing?")) == "nowPlaying")
    }
}
