// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import ServiceManagement

/// Minimal surface of `SMAppService` so the toggle logic is testable.
protocol LoginItemService {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

struct MainAppLoginItem: LoginItemService {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
}

struct LaunchAtLogin {
    var service: LoginItemService = MainAppLoginItem()

    var isEnabled: Bool { service.isEnabled }

    /// Applies the wanted state and returns the state actually in effect.
    @discardableResult
    func set(_ enabled: Bool) -> Bool {
        if enabled != service.isEnabled {
            do {
                if enabled { try service.register() } else { try service.unregister() }
            } catch {
                // Fall through; the returned value reflects reality.
            }
        }
        return service.isEnabled
    }
}
