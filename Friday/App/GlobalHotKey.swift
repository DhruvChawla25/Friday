// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Carbon.HIToolbox
import os

/// A system-wide keyboard shortcut using the Carbon hot key API.
/// Works inside the App Sandbox and needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private static let log = Logger(subsystem: "com.dhruvchawla.friday", category: "hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    fileprivate let action: @MainActor () -> Void

    /// The result of `RegisterEventHotKey`. Anything but `noErr` means the
    /// shortcut does nothing, usually because another app already owns it.
    private(set) var status: OSStatus = noErr

    /// True when the shortcut is live.
    var isRegistered: Bool { status == noErr && hotKeyRef != nil }

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot key events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard handlerStatus == noErr else {
            status = handlerStatus
            Self.log.error("Could not install the hot key handler (OSStatus \(handlerStatus))")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4652_4459), id: 1)  // "FRDY"
        status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            Self.log.error("Could not register the shortcut, another app may own it (OSStatus \(self.status))")
            unregister()
        }
    }

    isolated deinit {
        unregister()
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
