# Friday

**A local-first assistant for macOS. No internet. No accounts. No emotions.**

Friday is a native Swift menu bar app that runs entirely on your Mac. You type a command and it carries the command out, then reports back in one or two factual lines. It has no network access: macOS blocks it through the App Sandbox. It needs no sign-in, and it stores nothing unless you turn memory on.

> Status: **v0.2.0 in progress (UI/UX).** See the [roadmap](docs/ROADMAP.md).

## Features

| | |
|---|---|
| **The orb** | A small rotating 3D ribbon that floats in a screen corner. Drag it anywhere and Friday remembers the spot per app. Otherwise it avoids toolbars and desktop icons, follows your cursor between screens, and moves away or hides when a screen is full screen. |
| **Dashboard** | Click the orb, press **⌃⌥Space**, or click the Dock icon. It shows **Connected** apps with unread numbers and has the command bar. |
| **Connected** | WhatsApp (the Mac app) shows its unread **number only**, read from its Dock badge. Calendar shows today's remaining events. Mail is coming soon. |
| **Time & date** | `what time is it`, `what's the date` |
| **Open apps** | `open WhatsApp`, `launch Chrome`. Some apps are blocked by policy (Instagram). |
| **Opt-in memory** | `remember …`, `what do you remember`, `forget everything`. Memory is one plain `memory.txt` file you can read, edit, export or delete. |
| **Offline by design** | No network entitlement. CI fails if any networking API is added. |

## Install

1. Download `Friday.dmg` and open it. Drag **Friday** into **Applications**.
2. The first time you launch it, **right-click Friday → Open**. You only need to do this once, because the build is not notarized yet.
3. The orb appears in a corner of your screen. Click it, or press **⌃⌥Space**.
4. WhatsApp connects automatically while the app is open. For Calendar, click **Connect**; macOS asks once.

Requires macOS 26 or later on Apple silicon.

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
  Connections/  Dock badge reader, Calendar (EventKit), live counts
  Core/      Command parsing, Skill protocol + registry, Persona, Assistant
  Skills/    one file per skill
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

## License

[MIT](LICENSE) © 2026 Dhruv Chawla
