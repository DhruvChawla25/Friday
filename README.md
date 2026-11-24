# Friday

**A local-first assistant for macOS. No internet. No accounts. No emotions.**

Friday is a native Swift menu bar app that runs entirely on your Mac. You type a command and it carries the command out, then reports back in one or two factual lines. It has no network access: macOS blocks it through the App Sandbox. It needs no sign-in, and it stores nothing unless you turn memory on.

> Status: **v0.1.0 (foundation).** The skills in this release are time/date, opening apps and opt-in memory. See the [roadmap](docs/ROADMAP.md).

## Features

| | |
|---|---|
| **Menu bar + floating panel** | Click the menu bar icon, or press **⌃⌥Space** from anywhere. |
| **Time & date** | `what time is it`, `what's the date` |
| **Open apps** | `open WhatsApp`, `launch Chrome`. Some apps are blocked by policy (Instagram). |
| **Opt-in memory** | `remember …`, `what do you remember`, `forget everything`. Memory is one plain `memory.txt` file you can read, edit, export or delete. |
| **Offline by design** | No network entitlement. CI fails if any networking API is added. |

## Install

1. Download `Friday.dmg` and open it. Drag **Friday** into **Applications**.
2. The first time you launch it, **right-click Friday → Open**. You only need to do this once, because the build is not notarized yet.
3. Look for the hexagon icon in the menu bar, or press **⌃⌥Space**.

Requires macOS 26 or later on Apple silicon.

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
make project   # generate Friday.xcodeproj from project.yml
make run       # build and launch (Debug)
make check     # lint + tests + no-network check (what CI runs)
make dmg       # Release build → build/Friday.dmg
```

Or open `Friday.xcodeproj` in Xcode and press ⌘R.

## Project layout

```
Friday/
  App/       entry point, app delegate, global hot key, entitlements
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
