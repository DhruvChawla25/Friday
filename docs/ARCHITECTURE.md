# How Friday works: developer guide

This guide explains what Friday is made of, how the parts fit together, what every file and folder does, and what has been built so far. It uses no code, so you can read it without knowing the programming language.

---

## 1. The big picture

Friday is a **native Mac app**: it is built with Apple's own tools and runs directly on macOS, not in a browser. It has three visible parts:

| Part | What you see | What it does |
|---|---|---|
| **The orb** | A small rotating orange 3D ribbon floating in a corner of the screen | A shortcut. Click it to open the dashboard. It shows a red number when you have unread messages. |
| **The dashboard** | A dark window in the middle of the screen | Shows your connected apps (WhatsApp, Mail, Calendar) with their numbers, your latest command and reply, your history, and a box to type commands. |
| **Settings** | A normal Mac settings window | Turns memory on or off, chooses whether WhatsApp names are shown, resets the orb's position. |

Behind them are a few "engines":

```
          you type a command
                  │
                  ▼
   ┌──────────────────────────────┐
   │ Assistant  (the coordinator) │── keeps the Latest + History log
   └──────────────┬───────────────┘
                  ▼
   ┌──────────────────────────────┐
   │ Skill registry               │── asks each skill "is this yours?"
   └──┬──────┬──────┬──────┬──────┘
      ▼      ▼      ▼      ▼
  WhatsApp  Time  OpenApp  Memory   ← skills (one job each)
      │
      ▼
   ┌──────────────────────────────┐
   │ Connections                  │── live numbers: WhatsApp, Calendar
   └──┬───────────┬───────────┬───┘
      ▼           ▼           ▼
  Dock badge   Screen      Chrome tab
  (WhatsApp    reader      titles
   app icon)   (WhatsApp   (WhatsApp Web)
               window)
```

### The most important rule: Friday is offline
Friday has **no internet access**, and macOS enforces that, not just a promise. The app runs in Apple's **App Sandbox**, a locked box that only grants the abilities an app explicitly asks for. Friday never asks for network access. On top of that, a script (`Scripts/check-no-network.sh`) scans the code on every change and **fails the build** if anyone adds networking code. Apps that Friday opens, such as Chrome and WhatsApp, do their own networking; Friday never does.

### What "the model" is (and is not) today
Friday does **not use an AI model yet**. Today it understands commands with **fixed phrases**: each skill has a list of phrases it recognises ("check whatsapp", "who messaged me", "what time is it", "open Chrome"). That is why anything else gets "Command not recognised" (issue #12).

The plan for Phase 4 is **Apple Foundation Models**, the small language model built into macOS 26 that runs **on your Mac with no internet**. It would turn free-form sentences into the right skill. `docs/PLANNED_UPDATES.md` explains why we chose it over Python.

---

## 2. Tools and frameworks

A **framework** is a ready-made toolbox from Apple (or someone else) that the app uses instead of writing everything from scratch.

### Apple frameworks used inside the app

| Framework | What Friday uses it for |
|---|---|
| **SwiftUI** | Drawing the interface: the dashboard, tiles, settings, and the 3D ribbon (drawn by hand, frame by frame, on a canvas). |
| **AppKit** | Classic Mac window control: the floating orb and dashboard windows, the Dock icon and badge, menus, opening other apps. |
| **Carbon (HotKey part)** | Registering the global shortcut **⌃⌥Space**, which works from any app. |
| **EventKit** | Reading today's events from the Calendar app (with your permission). |
| **ScreenCaptureKit** | Taking a picture of **only WhatsApp's window**, kept in memory, to find the unread bubbles. |
| **Vision** | Apple's on-device text recognition, used to read **chat names only** beside unread bubbles. |
| **CoreText / CoreGraphics** | Drawing digits in the system font, so Friday can compare the shapes inside WhatsApp's green bubbles against them (our own tiny "digit reader"). |
| **Apple Events (NSAppleScript)** | Asking Chrome for its **tab titles**, to read WhatsApp Web's "(70) WhatsApp" number. |
| **Observation** | Making the screen update automatically when a number changes. |
| **Swift Testing** | Writing and running the automated tests. |

### Developer tools (used to build it, not shipped in the app)

| Tool | Role |
|---|---|
| **Xcode** | Apple's app-building program: compiles the code and runs the tests. |
| **XcodeGen** | Generates the Xcode project file from a short, readable recipe (`project.yml`). Running `make project` regenerates it, which avoids messy conflicts in the giant project file. |
| **swift-format** | Automatically lays out the code consistently. `make lint` fails if anything is laid out wrongly. |
| **make** (the `Makefile`) | Short commands for common jobs (see §5). |
| **GitHub Actions** | A Mac in the cloud that builds, tests and packages Friday on every pull request (the "CI" check). |
| **gh** | GitHub's command-line tool, used to create issues, PRs and releases. |
| **hdiutil / codesign** | Built-in Mac tools that package the app into a `.dmg` and sign it. |

---

## 3. Every folder and file

### Top level of the repository

| File / folder | Meaning |
|---|---|
| `README.md` | The front page on GitHub: what Friday is, how to install and build it, links to everything else. |
| `LICENSE` | The **MIT License**: anyone may use, copy, change and sell Friday as long as they keep the copyright notice. It comes with no warranty. |
| `CONTRIBUTING.md` | How other people can help: pick an issue, make a branch, run `make check`, open a PR. |
| `CODE_OF_CONDUCT.md` | Rules for respectful behaviour in issues and PRs. |
| `SECURITY.md` | How to report a privacy or security problem privately (by email, not in a public issue). |
| `project.yml` | **The recipe for the Xcode project**: app name, version number (`MARKETING_VERSION`), minimum macOS (26), permissions (entitlements), and permission explanations shown by macOS. Edit this, then run `make project`. |
| `Friday.xcodeproj/` | The Xcode project **generated** from `project.yml`. It is committed so you can double-click it to open in Xcode. Don't edit it by hand. |
| `Makefile` | The shortcut commands (`make run`, `make check`, `make dmg`, and so on). |
| `.swift-format` | Settings for the code formatter (line length, indentation). |
| `.gitignore` | Files Git should **never** upload: build output, `.dmg` files, Xcode user settings, and the old `legacy-jarvis/` folder. |
| `.github/` | GitHub configuration (see below). |
| `Friday/` | **The app itself**: all its source files. |
| `FridayTests/` | **Automated tests** for the app. |
| `Scripts/` | Helper programs for building and checking. |
| `docs/` | Documentation. |

### `.github/`: GitHub settings

| File | Meaning |
|---|---|
| `workflows/ci.yml` | The **CI pipeline**. On every PR, a cloud Mac runs: the no-network check, then lint, then the tests, then builds the DMG and keeps it for 14 days as a downloadable file. A PR shows a green tick only if all of these pass. |
| `ISSUE_TEMPLATE/bug.md` | The form shown when someone reports a bug. |
| `ISSUE_TEMPLATE/feature.md` | The form shown when someone suggests a feature. |
| `pull_request_template.md` | The checklist pre-filled in every new PR. |

### `Friday/App/`: start-up and wiring

| File | What it does |
|---|---|
| `FridayApp.swift` | The app's entry point. Declares the Settings window and the "Open Friday" (⌘O) menu command. |
| `AppDelegate.swift` | **The switchboard.** At launch it: makes sure only one Friday runs, creates the Assistant and Connections, builds the dashboard and orb, starts the live counters, keeps the orb badge and Dock badge in sync, and registers ⌃⌥Space. It also handles clicking the Dock icon and the right-click menus. |
| `GlobalHotKey.swift` | Registers the system-wide shortcut ⌃⌥Space. |
| `Friday.entitlements` | **The list of permissions the sandbox grants**: sandbox on; open files you choose; read Calendar; talk to Google Chrome only. No network. (Generated from `project.yml`.) |
| `Info.plist` | App identity card: name, version, and the sentences macOS shows when it asks you for Calendar or Chrome permission. (Generated from `project.yml`.) |

### `Friday/Core/`: the brain's skeleton

| File | What it does |
|---|---|
| `Command.swift` | Turns what you typed into a tidy form: lower-case, no trailing "?" or "!", split into words, so skills can match it reliably while still keeping your original wording. |
| `Skill.swift` | Defines what a **skill** is: something with a name, an example phrase, a "can I handle this?" check, and a "handle it" action. Also contains the **skill registry**, which asks each skill in turn and falls back to "Command not recognised" plus examples. |
| `Persona.swift` | All of Friday's fixed replies in one place: short, factual, no emotion (for example "Saved to memory.", "Memory is off…"). |
| `Assistant.swift` | **The coordinator.** Receives a command, sends it to the registry, and stores the result as **Latest** plus **History**. History is kept in memory only (never saved to disk) and items older than **24 hours** are deleted automatically. |

### `Friday/Skills/`: one job per file

| Skill | Phrases | What it does |
|---|---|---|
| `WhatsAppSkill.swift` | "check whatsapp", "who messaged me", "open whatsapp"… | Asks Connections to read WhatsApp and replies with the number of unread chats and (optionally) who they're from. "open…" keeps WhatsApp in front; "check…" puts you back where you were. |
| `TimeSkill.swift` | "what time is it", "what's the date" | Answers with the time or date. |
| `OpenAppSkill.swift` | "open Chrome", "launch Notes" | Finds and opens an installed app. **Instagram is blocked** by policy. |
| `MemorySkill.swift` | "remember …", "what do you remember", "forget everything" | Uses opt-in memory (below). Refuses if memory is off. |

### `Friday/Memory/`

| File | What it does |
|---|---|
| `MemoryStore.swift` | Opt-in memory. **Off by default.** When on, each fact is one line in a plain text file, `~/Library/Containers/com.dhruvchawla.friday/Data/Library/Application Support/Friday/memory.txt`, which you can open, export or wipe from Settings. |

### `Friday/Connections/`: where the live numbers come from

| File | What it does |
|---|---|
| `Connections.swift` | **The live data hub.** Every 5 s it reads the WhatsApp Dock badge and checks Calendar, every 15 s it asks Chrome, and it rechecks the WhatsApp screen every 10 minutes, after the Mac wakes, and when the badge changes. It combines the WhatsApp sources: the **WhatsApp Web number wins** when available (it counts every unread chat and is live), otherwise the larger of the screen reading and the Dock badge. |
| `DockBadge.swift` | Reads the red number on WhatsApp's Dock icon using macOS's built-in `lsappinfo` tool. (On your Mac this badge is switched off in Notification settings, which is why it reads 0.) |
| `CalendarSource.swift` | Asks for Calendar permission and counts today's remaining events and the next one. |
| `ChromeTabs.swift` | Asks Chrome for its **tab titles only** (never page contents), with a 2-second limit so a frozen Chrome can't freeze Friday. Also opens web.whatsapp.com in Chrome when asked. |
| `TabTitleParser.swift` | Finds "(70) WhatsApp" among tab titles and keeps **only the number**. Every other title is thrown away immediately. |
| `WhatsAppWebFallback.swift` | Decides the WhatsApp Web state: Chrome missing, closed, needs permission, denied, no tab, or "N unread". Also writes Friday's reply for each case. |
| `WhatsApp/WhatsAppScreenReader.swift` | Takes a picture of **only WhatsApp's window** (needs Screen Recording permission), opening WhatsApp briefly if needed and then returning you to your app. The picture stays in memory for under a second and is never saved. |
| `WhatsApp/WhatsAppChatListAnalyzer.swift` | Looks at that picture: finds the **green unread bubbles** by colour and shape, reads the number in each, and reads the **chat name line** next to it (never message previews). |
| `WhatsApp/BadgeGlyphReader.swift` | Our own small digit reader. Apple's text recognition can't read tiny single digits in green bubbles, so this compares each digit's shape with digits drawn in the system font, and also recognises "@" (you were mentioned). |

### `Friday/Dashboard/`: the main window

| File | What it does |
|---|---|
| `DashboardPanel.swift` | The floating window and its open/close animation. It **stays open while commands run**, even if another app comes to the front. Close it with the **–** button, Esc, ⌘W/⌘M, the orb or ⌃⌥Space. |
| `DashboardView.swift` | The layout: header (logo, status, clock, menu, minimize), **Latest** reply card, Connected tiles, **History** (collapsible), and the command box. |
| `ConnectedSection.swift` | The three tiles: **WhatsApp** (number, names, and a button such as *Connect Chrome* or *Allow screen reading*), **Mail** (coming soon) and **Calendar** (events left today). |

### `Friday/Orb/`: the floating orb

| File | What it does |
|---|---|
| `OrbController.swift` | Runs the orb: checks the screen several times a second, moves it when needed, hides it in full screen, and remembers where you dragged it. |
| `OrbPanel.swift` | The tiny transparent window that holds the orb and lets you drag it. |
| `OrbView.swift` | What the orb looks like: the ribbon plus the red unread badge. |
| `OrbPlacement.swift` | The placement rules (pure geometry, fully tested): try the corners in order, avoid every window's title bar/toolbar strip and the desktop icon column, snap to edges after a drag. |
| `OrbPositionStore.swift` | Remembers a dragged position **per app** (for example a different spot when Chrome is in front). |
| `ScreenEnvironment.swift` | Gathers the facts the rules need: which screens exist, which windows are where (frames only, never their contents), which screens are full screen. |

### `Friday/Design/`: the look

| File | What it does |
|---|---|
| `Theme.swift` | The design tokens: JARVIS-orange colour palette, fonts, spacing, corner radius, and the small section-title style. |
| `RibbonModel.swift` | The maths of the 3D ribbon: an S-shaped spine that twists and tapers. |
| `RibbonView.swift` | Draws the ribbon live, frame by frame, with depth sorting and lighting, plus the starfield background. The **same drawing code makes the app icon**. |

### `Friday/UI/`

| File | What it does |
|---|---|
| `SettingsView.swift` | The Settings window: Memory (on/off, show in Finder, export, wipe), WhatsApp (show names on/off), Orb (reset positions), Privacy summary. |

### `Friday/Assets.xcassets/`
The app icon at every size macOS needs (16 px to 1024 px). These images are **generated** by `Scripts/make-icon.sh`, not drawn by hand.

### `FridayTests/`: automated tests
Each file checks one area automatically. 55 tests in total on the latest branch. `make test` runs them all in a few seconds, and CI runs them on every PR.

| Test file | What it proves |
|---|---|
| `CommandTests` | Typed text is tidied correctly. |
| `SkillRegistryTests` | Commands reach the right skill; unknown ones get help. |
| `AssistantLogTests` | Latest and History order is right; entries older than 24 h are deleted. Uses a fake clock, so the test doesn't wait 24 hours. |
| `TimeSkillTests`, `OpenAppSkillTests`, `MemoryTests`, `WhatsAppSkillTests` | Each skill answers correctly, and Instagram stays blocked. |
| `OrbPlacementTests` | The orb picks free corners and avoids toolbars and icons. |
| `RibbonModelTests` | The ribbon's geometry is sensible. |
| `DockBadgeTests` | Badge text is read correctly. |
| `WhatsAppAnalyzerTests` | Draws **fake** WhatsApp chat lists (light and dark mode, numbers 1–99, "@") and checks Friday reads them. No real chats are used. |
| `WhatsAppWebFallbackTests` | "(70) WhatsApp" gives 70, other tabs are ignored, and the right source wins. |

### `Scripts/`

| File | What it does |
|---|---|
| `build-dmg.sh` | Makes a Release build, verifies its signature, and packages it as `build/Friday.dmg` with an Applications shortcut for drag-to-install. |
| `check-no-network.sh` | **The offline guard**: fails if networking code or a network permission appears. |
| `make-icon.sh` + `IconGen/main.swift` | Renders the ribbon at every icon size into `Assets.xcassets`. |

### `docs/`

| File | What it is |
|---|---|
| `ARCHITECTURE.md` | This guide. |
| `PRIVACY.md` | Exactly what Friday reads, when, and what it never touches. |
| `PLANNED_UPDATES.md` | The living plan: phases, decisions (Swift vs Python), and items marked ✅ when done. |
| `ROADMAP.md` | The shorter, older phase overview. |

---

## 4. How WhatsApp counting works (step by step)

Friday has three sources, from simplest to richest:

1. **WhatsApp Web title (Chrome).** Chrome's tab title says "(70) WhatsApp" when 70 chats are unread. Friday asks Chrome for tab titles every 15 s, keeps only that number, and discards everything else. *Needs: click **Connect Chrome** once (macOS "Automation" permission).*
2. **Screen reading (WhatsApp for Mac).** Friday photographs WhatsApp's window in memory, finds green bubbles, reads their numbers and the chat names beside them. It gives names, but only for chats visible on screen. *Needs: **Screen Recording** permission.*
3. **Dock badge.** It's free and instant, but only works if WhatsApp's Dock badge is turned on (System Settings → Notifications → WhatsApp → Badge application icon). On your Mac it's off.

The tile and the orb show the **WhatsApp Web number when it's available**, and otherwise the larger of the other two. "check whatsapp" combines them: names from the screen, total from WhatsApp Web.

**Why permissions sometimes "forget" you:** Friday is signed **ad-hoc** (no Apple Developer certificate). macOS ties permissions to the exact build, so every rebuild can look like a new app and the permissions reset (issue #3). The fix is a stable signing certificate.

---

## 5. Everyday commands

Run these in Terminal inside the `Friday` folder:

| Command | What it does |
|---|---|
| `make project` | Regenerates the Xcode project (after adding files or changing `project.yml`). |
| `make run` | Builds and opens Friday. |
| `make check` | Everything CI checks: formatting, all tests, no-network guard. **Run before every commit.** |
| `make format` | Fixes code layout automatically. |
| `make dmg` | Builds the installable `build/Friday.dmg`. |
| `make clean` | Deletes build output. |

---

## 6. How the GitHub side is organised

- **Branches and PRs.** Work happens on a branch. Each change goes up as a **pull request (PR)**, CI tests it, and **you** merge it. `main` is protected: nobody, including Claude, can push to it directly or merge without a green check.
- **Stacked PRs.** Some PRs build on each other and must be merged in order. GitHub retargets each to `main` as the one below it merges.
- **Issues.** Every idea or bug is a small numbered issue with *Why / What to do / Where / Done when*. A PR that says "Closes #N" closes that issue automatically when merged.
- **Milestones and releases.** Each phase is a GitHub release named "Phase N — Name (vX.Y.0)" with a tag (v0.1.0, v0.2.0, …). Release tags are protected.
- **Commits.** One commit per fix, each with a clear message and a `Co-Authored-By: Claude` line, so the history shows exactly what changed and why.
- **Licensing.** Every source file starts with a three-line MIT header naming you as copyright holder.

---

## 7. What has been done so far

| When | What | Where |
|---|---|---|
| Phase 1 | Project set up: sandboxed offline app, skills system, opt-in memory, tests, CI, DMG packaging. **Released v0.1.0.** | `main` |
| Phase 2 | 3D ribbon orb (drag, per-app positions, avoids toolbars/icons/full screen), dashboard, Connected tiles, JARVIS orange, app icon, Dock badge. **Released v0.2.0.** | `main` |
| Repo setup | Made public; licence headers, Security/Contributing/Code of Conduct, contact email; planned updates; 44 small issues. | `main` |
| WhatsApp reading | Screen Recording flow, window-only capture, bubble and digit reader, names, rechecks every 10 min / on wake / on badge change. Closes #21–#25. | PR #45 |
| Dashboard | Stays open during commands, minimize button, Latest reply on top, History that clears after 24 h. Closes #46, #47. | PR #48 |
| WhatsApp Web | Chrome tab-title source, used alongside the Mac app (fixes the "shows 0" problem). Freeze-proof 2 s limit. Closes #4. | PR #49 |
| Helper agents | A tester reviewed WhatsApp (3 bugs fixed in #49). A scout filed #50–#54. A solver fixed #50, #53, #54. | PRs #55, #56, #57 |

**Merge order:** #45 → #48 → #49, then #55, #56, #57 in any order. Until they are merged, `main` still holds the v0.2 app. The newest code is on the `whatsapp-chrome-fallback` branch.

### Known open items
- **#3:** permissions reset after rebuilds (needs stable signing).
- **#12 and Phase 4:** free-form commands via the on-device model.
- **#57 caveat:** inside the sandbox, the "user Applications folder" may point to Friday's private container rather than your real `~/Applications`; check before merging.
- Phases 3 (commands for Claude, Antigravity, Stitch, installing DMGs), 5 (voice via double-tap Right Option) and 6 (UI refresh) are planned as issues.
