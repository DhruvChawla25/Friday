# Friday

**A local-first assistant for macOS. No internet. No accounts. No emotions.**

Friday is a native Swift menu bar app that runs entirely on your Mac. You type a command and it carries the command out, then reports back in one or two factual lines. It has no network access: macOS blocks it through the App Sandbox. It needs no sign-in, and it stores nothing unless you turn memory on.

> Status: **v0.2.0 (Phase 2 — UI/UX).** Next: [planned updates](docs/PLANNED_UPDATES.md) and [open issues](../../issues). Contributions welcome — see [CONTRIBUTING](CONTRIBUTING.md).

## Features

| | |
|---|---|
| **The orb** | A small rotating 3D ribbon that floats in a screen corner. Drag it anywhere and Friday remembers the spot per app. Otherwise it avoids toolbars and desktop icons, follows your cursor between screens, and moves away or hides when a screen is full screen. |
| **Dashboard** | Click the orb, press **⌃⌥Space**, or click the Dock icon. It shows **Connected** apps with unread numbers and has the command bar. |
| **Connected** | WhatsApp (the Mac app) shows its unread **number only**, read from its Dock badge. Calendar shows today's remaining events. Mail is coming soon. |
| **AI usage** | A loading bar per AI tool: Claude (Code + desktop app), Antigravity, Qwen Code, Qoder, Wispr Flow, OpenCode. Shows how much of the current limit is used, when it resets, local usage, and **LIVE** while the tool runs. Read only from files these tools already write on your Mac; limits Friday cannot know offline are labelled so, never guessed. |
| **Time & date** | `what time is it`, `what's the date` |
| **Open apps** | `open WhatsApp`, `launch Chrome`. Some apps are blocked by policy (Instagram). |
| **Screenshot & snip** | `screenshot` (or `ss`) saves the screen under the pointer; `snip` (or `snipping tool`, `capture area`) lets you drag out an area, Esc cancels. Both save a PNG to your Desktop, e.g. `Friday Snip 2026-11-26 at 10.15.03.png`, and copy it to the clipboard. Also two buttons in the command bar. Needs Screen Recording permission. |
| **Opt-in memory** | `remember …`, `what do you remember`, `forget everything`. Memory is one plain `memory.txt` file you can read, edit, export or delete. |
| **Offline by design** | No network entitlement. CI fails if any networking API is added. |

## Install

1. Download `Friday.dmg` and open it. Drag **Friday** into **Applications**.
2. The first time you launch it, **right-click Friday → Open**. You only need to do this once, because the build is not notarized yet.
3. The orb appears in a corner of your screen. Click it, or press **⌃⌥Space**.
4. WhatsApp connects automatically while the app is open. For Calendar, click **Connect**; macOS asks once.

Requires macOS 26 or later on Apple silicon.

### Claude limits (optional)

Claude's real 5-hour and weekly percentages are only on Anthropic's servers. Friday can show them in two ways, and neither gives Friday network access:

1. **Friday Online app** (separate, optional): a companion app that is the only networked part. Friday asks it over local XPC while the dashboard is open. The first time, macOS asks whether Friday Online may read Claude Code's sign-in from the Keychain. Choose **Always Allow**.
2. **Status line file**: Claude Code passes the limits to its status line. Add this to `~/.claude/settings.json` (use the full path to your copy of the repo):

```json
"statusLine": { "type": "command", "command": "/path/to/Friday/Scripts/friday-statusline.sh" }
```

The script saves only the limit numbers to `~/.claude/friday/rate-limits.json` and prints `5h 23% · 7d 41%` as your status line. If you already have a status line, set `FRIDAY_STATUSLINE_NEXT` to its command and the script will run it too. It needs `jq` (built into macOS 15+). A status line file less than 5 minutes old takes precedence. Otherwise Friday uses Friday Online's numbers. With neither, Friday still shows local Claude Code usage and an estimated reset time.

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make project   # generate Friday.xcodeproj from project.yml
make run       # build and launch (Debug)
make check     # lint + tests + no-network check (what CI runs)
make dmg       # Release build → build/Friday.dmg
Scripts/make-icon.sh   # regenerate the app icon from the ribbon renderer
```

Or open `Friday.xcodeproj` in Xcode and press ⌘R.

## Project layout

```
Friday/
  App/          entry point, app delegate, global hot key, entitlements
  Design/       Theme tokens, procedural 3D ribbon renderer (orb, dashboard, app icon)
  Orb/          orb window, placement rules, per-app positions, screen tracking
  Dashboard/    centred dashboard, connector tiles, command bar
  Connections/  Dock badge reader, Calendar (EventKit), live counts, AIUsage/ (offline AI limit readers)
  Core/      Command parsing, Skill protocol + registry, Persona, Assistant
  Skills/    one file per skill
  Capture/   screenshot + snip: command phrases, file naming, rect maths, ScreenCaptureKit, snip overlay
  Memory/    MemoryStore (memory.txt)
  UI/        SwiftUI views, floating panel
FridayTests/ Swift Testing unit tests
Scripts/     build-dmg.sh, check-no-network.sh
docs/        PRIVACY.md, ROADMAP.md
```

### Adding a skill

1. Create `Friday/Skills/YourSkill.swift` conforming to `Skill` (`canHandle` + `handle`).
2. Register it in `Assistant.makeDefault()`.
3. Add tests in `FridayTests/`.

## Privacy

See [docs/PRIVACY.md](docs/PRIVACY.md). In short, nothing leaves your Mac, and Friday never reads message contents.

## Contributing

Issues are small, step-by-step tasks; start with [`good first issue`](../../issues?q=is%3Aopen+label%3A%22good+first+issue%22). See [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Found a privacy or security problem? Please email privately. See [SECURITY.md](SECURITY.md).

## Author

**Dhruv Chawla**: [@dhruvchawla2511](https://github.com/dhruvchawla2511) · dhruvchawla2511@gmail.com

## License

Friday is released under the [MIT License](LICENSE).
Copyright (c) 2026 Dhruv Chawla. You may use, copy, modify and distribute it, including commercially, as long as the copyright notice and license text are kept. The software is provided "as is", without warranty.
