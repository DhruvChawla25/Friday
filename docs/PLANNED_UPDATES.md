# Planned updates

This file lists everything decided but not built yet, in the order we plan to build it. Every item is tracked as one or more small [GitHub issues](../../issues), grouped by milestone. Pick any issue labelled **`good first issue`** to start.

## Release labels

Every published version is named after its phase:

| Phase | Version | Milestone |
|---|---|---|
| Phase 1: Foundation | v0.1.0 ✅ | — |
| Phase 2: UI/UX | v0.2.0 ✅, fixes in v0.2.x | `Phase 2 — UI/UX` |
| Phase 3: Commands (install DMGs, prompt agents) | v0.3.0 | `Phase 3 — Commands` |
| Phase 4: AI & backend | v0.4.0 | `Phase 4 — AI & Backend` |
| Phase 5: Voice | v0.5.0 | `Phase 5 — Voice` |
| Phase 6: UI refresh | v0.6.0 | `Phase 6 — UI Refresh` |
| Release quality (Apple-level polish) | v1.0.0 | `v1.0 — Release Quality` |

## Phase 2 fixes (v0.2.x)

- **Orb never sits at the bottom.** The bottom of the screen belongs to the Dock. The orb should use the top-left, top-right or another open space only.
- **Calendar stays connected.** Today, Calendar asks to connect again after you have connected it.
- **Chrome as a fallback.** If the WhatsApp Mac app is not installed, read WhatsApp Web's unread count from Chrome tab titles, as in the first v0.2 build.

## Phase 3: Commands

- Install DMGs for you: find the `.dmg` in Downloads, copy the app into Applications, eject.
- Send prompts to agents: Claude (app and CLI), Antigravity, Stitch, and other web apps in Chrome.

## Phase 4: AI & backend (the focus now: the backend must work very well)

- **AI understands normal sentences.** Fixes "Command not recognised". Friday maps any phrasing onto its skills.
- **WhatsApp, visually.** When asked, open WhatsApp and read the chat list on screen to count unread chats more reliably than the Dock badge. Only counts and names are kept, never message text.
- **Rechecks by itself.** Every 10 minutes, whenever a badge changes (a notification arrived), and on wake. It pauses while the Mac sleeps.
- **Running apps.** "What's running?" lists open apps. "Close Spotify" quits an app safely.

### Decision: Swift (Apple Foundation Models) vs Python for the AI

| | **Swift + Apple Foundation Models** (recommended) | **Python** (e.g. MLX / llama.cpp / transformers) |
|---|---|---|
| Runs offline | Yes, on-device | Yes, with a downloaded model |
| Already on your Mac | **Yes**: macOS 26 ships the model; `availability: available` was checked on this Mac | No. Must bundle Python (~60–100 MB) plus a model (1–8 GB) inside the DMG |
| "Send the DMG to anyone" | Works on any Apple-Intelligence Mac with nothing to install | Huge download; the sandbox and code signing of a bundled interpreter are hard |
| Speed / battery | Optimised for Apple silicon and the Neural Engine | Good with MLX, heavier with others |
| Calling Friday's skills | Built-in **tool calling**: each Skill becomes a Tool | Must build our own bridge between Python and Swift (process + JSON) |
| Model quality | Small (~3B) model, good at intent → action | Can run bigger models: better open-ended answers |
| Learning curve | One language for the whole app | Two languages, two toolchains |

**Recommendation:** Swift with Apple Foundation Models for Friday's brain. It is what Apple itself would do for an offline assistant: no extra runtime, private, fast, and a simple DMG. Python stays useful for **experiments** (trying bigger models, measuring accuracy). If we later need a bigger model, the natural next step is **MLX Swift**, which runs the same open models as Python's MLX but inside the app.

## Phase 5: Voice

- Push-to-talk like Wispr Flow: **double-tap Right Option** (or hold it) to start listening.
- On-device speech-to-text and spoken replies in a calm, emotionless voice.
- Voice gets its own command and shortcut; ⌃⌥Space stays for typing.

## Phase 6: UI refresh

- Replace the current gold ribbon look with a more seamless orb and dashboard. Design first in Stitch.

## Release quality (v1.0)

Launch at login, first-run onboarding, notarized DMG, accessibility (VoiceOver, Reduce Motion), energy budget, customisable shortcuts, Shortcuts/Spotlight integration, localisation. See the `v1.0 — Release Quality` milestone.
