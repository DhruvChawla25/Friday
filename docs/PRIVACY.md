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
- **WhatsApp Web fallback (Automation permission for Chrome):** only if WhatsApp for Mac is not installed, Friday asks Chrome for its tab titles and keeps just the number in a WhatsApp tab's title, such as `(3) WhatsApp`. Every other title is discarded at once. Friday never reads page contents, and it never opens Chrome unless you say "open whatsapp".
- **When it checks:** when you ask ("check whatsapp", "open whatsapp"), when the Dock badge changes, after the Mac wakes, and every 10 minutes. Background checks only read a window that is already visible and never change what is on your screen.
- **Mail:** not connected yet, waiting for your new mail app. It will use the same Dock badge method.
- **Calendar:** Friday reads today's events (count, plus the next event's time and title) through macOS Calendar access. It never changes them.
- **Orb placement** uses only window **positions and sizes** from macOS. It never captures window contents.

## Rules for screen-reading features (planned)

- **WhatsApp:** Friday reports *who* has sent unread messages. It never reads or reports message text.
- **Gmail:** Friday reports the *senders* of unread mail for each account. It never opens emails or reads subjects or bodies.
- Screen captures are processed in memory and discarded right away. They are never written to disk.
- **Blocked:** Instagram, plus any app you add to the block list.
