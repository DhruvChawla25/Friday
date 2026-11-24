# Roadmap

Each phase ships as its own tested, reviewed change.

| Phase | Scope | Key Apple frameworks |
|---|---|---|
| **1. Foundation** ✅ | Menu bar app, ⌃⌥Space panel, skill system, time/date, open apps, opt-in `memory.txt`, DMG, CI | SwiftUI, AppKit, Carbon hot keys |
| **2. Brain + voice** | On-device LLM to understand free-form requests and pick skills; push-to-talk; spoken replies | Foundation Models, Speech (SpeechAnalyzer), AVSpeechSynthesizer |
| **3. Memory v2** | The model reads `memory.txt` as context and proposes edits; import/export UI | Foundation Models |
| **4. Screen + WhatsApp** | Open WhatsApp, read the chat list, report **senders with unread messages only** | ScreenCaptureKit, Vision (OCR) |
| **5. Gmail, all accounts** | Open each account (`mail.google.com/mail/u/N`) in Chrome and report **senders only**, per account | ScreenCaptureKit, Vision, Apple Events |
| **6. Calendar & schedule** | Read, create and move events; reminders; daily briefing | EventKit |
| **7. Claude commands** | "Ask Claude to …": Friday types the prompt into Claude.app or the `claude` CLI | Accessibility / Apple Events |
| **8. Release polish** | Styled DMG, app icon, onboarding for permissions, Developer ID notarization | notarytool |

Out of scope: Instagram and other private social apps, and Android phone linking, because it would need the internet.

## Open design question

Phases 4, 5 and 7 need Accessibility and Apple Events access, which the App Sandbox restricts. Before phase 4 we decide between scoped sandbox exceptions and running unsandboxed while keeping the CI no-network check.
