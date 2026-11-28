// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import os

/// Structured logging, viewable in Console.app (filter by subsystem).
/// Log events and counts only. Never log message text, chat names or memory
/// contents; mark any user-derived value `privacy: .private`.
enum Log {
    static let subsystem = "com.dhruvchawla.friday"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let skills = Logger(subsystem: subsystem, category: "skills")
    static let connections = Logger(subsystem: subsystem, category: "connections")
    static let memory = Logger(subsystem: subsystem, category: "memory")
    static let capture = Logger(subsystem: subsystem, category: "capture")
}
