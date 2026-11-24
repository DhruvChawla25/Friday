# Privacy

Friday is designed so it cannot leak your data.

## Guarantees

1. **No network access.** Friday runs in the macOS App Sandbox *without* the `com.apple.security.network.client` or `network.server` entitlements, so macOS refuses any connection Friday tries to make. `Scripts/check-no-network.sh` runs in CI and fails the build if networking APIs or entitlements appear.
2. **No accounts.** There is no sign-up, login, analytics or telemetry.
3. **Memory is opt-in and yours.** Memory is off until you enable it in Settings. Once enabled, everything Friday remembers is in one plain-text file:
   `~/Library/Containers/com.dhruvchawla.friday/Data/Library/Application Support/Friday/memory.txt`
   You can open it with **Settings → Show in Finder**, edit it in any text editor, export it, or wipe it.
4. **Other apps do their own networking.** When Friday opens Chrome or WhatsApp, those apps connect to the internet as they normally would. Friday itself only opens them and, in later versions, reads what is on screen.

## Rules for screen-reading features (planned)

- **WhatsApp:** Friday reports *who* has sent unread messages. It never reads or reports message text.
- **Gmail:** Friday reports the *senders* of unread mail for each account. It never opens emails or reads subjects or bodies.
- Screen captures are processed in memory and discarded right away. They are never written to disk.
- **Blocked:** Instagram, plus any app you add to the block list.
