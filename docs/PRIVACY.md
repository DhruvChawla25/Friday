# Privacy

Friday is designed so it cannot leak your data.

## Guarantees

1. **No network access.** Friday runs in the macOS App Sandbox *without* the `com.apple.security.network.client` or `network.server` entitlements, so macOS refuses any connection Friday tries to make. `Scripts/check-no-network.sh` runs in CI and fails the build if networking APIs or entitlements appear.
2. **No accounts.** There is no sign-up, login, analytics or telemetry.
3. **Memory is opt-in and yours.** Memory is off until you enable it in Settings. Once enabled, everything Friday remembers is in one plain-text file:
   `~/Library/Containers/com.dhruvchawla.friday/Data/Library/Application Support/Friday/memory.txt`
   You can open it with **Settings → Show in Finder**, edit it in any text editor, export it, or wipe it.
4. **Other apps do their own networking.** When Friday opens Chrome or WhatsApp, those apps connect to the internet as they normally would. Friday itself only opens them and, in later versions, reads what is on screen.

## Unread counts (v0.2)

- **WhatsApp, Dock badge:** Friday reads the number in the red badge on the WhatsApp Dock icon, using macOS's built-in `lsappinfo` tool. That is the same number you see in the Dock, and it needs no permission.
- **WhatsApp, chat list (Screen Recording permission):** to see *which* chats are unread, Friday captures **only WhatsApp's own window**, never the whole screen. It finds the green unread bubbles, reads the number inside each one, and reads **only the chat-name line** next to it. Message previews and the open conversation are never passed to text recognition. The capture stays in memory for under a second and is never saved. Names can be turned off in Settings → WhatsApp.
- **WhatsApp, the unread pop-up (Accessibility permission; not available in the sandboxed build yet, see issue #6):** clicking the WhatsApp tile opens a list of unread chats. With Accessibility allowed, Friday reads WhatsApp's chat-list labels and keeps **only the chat name, the unread count, the last-message time and whether it is a group**. The labels also contain message previews; those are cut away while parsing and are never stored, logged or shown. A full scan of every unread chat runs **only when you click "Scan all chats"**: WhatsApp's list switches to its Unread filter and scrolls while Friday reads it, then goes back. Afterwards Friday keeps the list current from WhatsApp's notification banners, taking only the chat name and the time (never the message text). The list lives in memory only. Without Accessibility, the pop-up lists the chats visible in WhatsApp's window (screen reading, above).
- **WhatsApp Web fallback (Automation permission for Chrome):** only if WhatsApp for Mac is not installed, Friday asks Chrome for its tab titles and keeps just the number in a WhatsApp tab's title, such as `(3) WhatsApp`. Every other title is discarded at once. Friday never reads page contents, and it never opens Chrome unless you say "open whatsapp".
- **When it checks:** when you ask ("check whatsapp", "open whatsapp"), when the Dock badge changes, after the Mac wakes, and every 10 minutes. Background checks only read a window that is already visible and never change what is on your screen.
- **Mail:** not connected yet, waiting for your new mail app. It will use the same Dock badge method.
- **Calendar:** Friday reads today's events (count, plus the next event's time and title) through macOS Calendar access. It never changes them.
- **Orb placement** uses only window **positions and sizes** from macOS. It never captures window contents.

## AI usage (v0.3)

Friday shows how much of each AI tool's limit you have used. It never contacts those services; it only reads files the tools already write on this Mac, and only the usage numbers in them.

To read those files from inside the sandbox, Friday has one extra entitlement, `com.apple.security.temporary-exception.files.home-relative-path.read-only`. It is **read-only** and limited to these paths in your home folder:

| Path | Why | What Friday reads |
|---|---|---|
| `~/.claude/projects/` | Claude Code transcripts | Only each reply's time, ID and token counts. Message text is skipped by the decoder and never kept. |
| `~/.claude/sessions/` | Open Claude Code sessions | Only `pid` and `status` (working / idle) from the `*.json` files. The folder also has `*.key` files; Friday never opens them. |
| `~/.claude/friday/` | Claude plan limits from `Scripts/friday-statusline.sh` | 5-hour and weekly used % and reset time. |
| `~/.qoder/projects/` | Qoder transcripts | Only each reply's time, ID, token counts and credits. |
| `~/.gemini/antigravity/conversations/` | Antigravity activity | Only file **dates**, to show "last used". Contents are not read. |
| `~/.qwen/tmp/` | Qwen Code activity | Only file **dates**. |
| `~/.local/share/opencode/opencode.db` (+ `-wal`, `-shm`) | OpenCode usage | Opened read-only. Only per-session token and cost totals; messages are not queried. |
| `~/Library/Application Support/Wispr Flow/config.json` | Wispr Flow usage | Only word counts, plan name, weekly-limit date and Notetaker quota. Name, email and dictionary are not decoded. |

Friday does **not** get access to credentials: not `~/.claude/.credentials.json`, the Keychain, `~/.gemini`'s token file, `~/.config/opencode` (which holds a service password) or Qoder's `.auth` folder.

"Live" comes from the list of running apps (`NSWorkspace`) and running process IDs (`sysctl`, the same call Activity Monitor uses). Friday reads no process arguments, memory or environment.

The optional `Scripts/friday-statusline.sh` runs inside Claude Code, not Friday. It writes only `captured_at` and the `rate_limits` numbers; no prompts, paths or session IDs. Nothing is installed for you: you add it to `~/.claude/settings.json` yourself.

### Friday Online (optional, separate app)

Live Claude limits can also come from **Friday Online**, a separate app with its own repository, signature and permissions. **Friday itself still has no network access.** Friday Online is the only networked component, and it answers only one question: "what are the usage limits for tool X?" It replies with percentages, reset times and a status, nothing else.

To reach it, Friday has a second entitlement, `com.apple.security.temporary-exception.mach-lookup.global-name`, with exactly one name: `com.dhruvchawla.friday.online`. It lets Friday look up that one local XPC service, which is kernel IPC on this Mac. It is not a network entitlement. Friday accepts replies only from a process signed as `com.dhruvchawla.friday.online`.

- Friday contains only a thin connector (`Friday/Connections/AIUsage/FridayOnlineConnector.swift`). None of Friday Online's server, network or credential code is in Friday.
- Friday asks only while the dashboard is open, at most once a minute per tool.
- Friday never sees a token. Friday Online reads Claude Code's sign-in from the Keychain itself, and macOS asks you first.
- If Friday Online isn't installed or running, Friday says "Friday Online app not running" and uses only local data.

## Screenshot and snip

When you type `screenshot` / `snip` (or press the camera / crop buttons), Friday captures the screen with Apple's ScreenCaptureKit and saves **one PNG to your Desktop**. That is the only time Friday writes an image to disk, and only because you asked.

- **Nothing is uploaded.** Friday still has no network entitlement. The image goes to `~/Desktop` and, so you can paste it, to the clipboard. (If you have turned on *Desktop & Documents* in iCloud, macOS itself syncs your Desktop; Friday does not.)
- **Friday is not in the picture.** It hides its dashboard and orb first and also excludes its own windows from the capture.
- **Permission:** macOS asks you to allow Friday under *System Settings → Privacy & Security → Screen & System Audio Recording*. Until you do, Friday replies with that path and shows an **Allow** button that opens the pane. You can turn it off there at any time.
- **Entitlement:** `com.apple.security.temporary-exception.files.home-relative-path.read-write` with exactly one path, `/Desktop/`. It lets the sandboxed app create files in `~/Desktop` and nowhere else in your home folder. Friday only ever creates new files there; it never overwrites one (a clash becomes `… (2).png`) and never reads or deletes other files.

## Rules for screen-reading features (planned)

- **WhatsApp:** Friday reports *who* has sent unread messages. It never reads or reports message text.
- **Gmail:** Friday reports the *senders* of unread mail for each account. It never opens emails or reads subjects or bodies.
- Screen captures for screen reading are processed in memory and discarded right away. They are never written to disk. (Screenshots and snips you ask for are the one exception; see above.)
- **Blocked:** Instagram, plus any app you add to the block list.
