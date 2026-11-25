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

- **WhatsApp:** Friday reads the number in the red badge on the WhatsApp Dock icon, using macOS's built-in `lsappinfo` tool. That is the same number you see in the Dock. Friday never opens WhatsApp's data, never sees messages or senders, and needs no extra permission.
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

## Rules for screen-reading features (planned)

- **WhatsApp:** Friday reports *who* has sent unread messages. It never reads or reports message text.
- **Gmail:** Friday reports the *senders* of unread mail for each account. It never opens emails or reads subjects or bodies.
- Screen captures are processed in memory and discarded right away. They are never written to disk.
- **Blocked:** Instagram, plus any app you add to the block list.
