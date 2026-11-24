# Roadmap

Each phase ships as its own tested GitHub release.

| Phase | Release | Scope |
|---|---|---|
| **1. Foundation** ✅ | v0.1.0 | Skill system, time/date, open apps, opt-in `memory.txt`, offline sandbox, DMG, CI |
| **2. UI/UX** ✅ | v0.2.0 | Rotating 3D ribbon orb (JARVIS orange). Draggable with per-app positions; avoids toolbars and desktop icons; follows the cursor's screen; moves away or hides in full screen. Click to open the centred dashboard with **Connected** tiles: WhatsApp (Mac app, Dock badge), Calendar (EventKit), and Mail (placeholder until the new mail app). App icon in the Dock with an unread badge. |
| **3. Commands** | v0.3.0 | Install DMGs for you. Send prompts to agents: Claude (app/CLI), Antigravity, Stitch and other Chrome web apps. |
| **4. AI & backend** | v0.4.0 | On-device AI understands normal sentences; WhatsApp read visually; self-rechecks every 10 min, on notifications and on wake; list and close running apps. |
| **5. Voice** | v0.5.0 | Double-tap Right Option to talk; on-device speech in and out. |
| **6. UI refresh** | v0.6.0 | A more seamless orb and dashboard design. |
| **v1.0** | v1.0.0 | Release quality: onboarding, notarization, accessibility, energy, launch at login. |

Details and the Swift-vs-Python decision: [PLANNED_UPDATES.md](PLANNED_UPDATES.md).

Out of scope: Instagram and other private social apps, and Android phone linking, because it would need the internet.
