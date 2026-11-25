// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Darwin

/// Lists running processes (PID and short name only) with `sysctl`, the same
/// call Activity Monitor uses. Used to tell whether a command-line tool such
/// as Claude Code is running. Never reads arguments, memory or environment.
enum ProcessList {
    struct Snapshot: Sendable, Equatable {
        /// PID → short process name (at most 16 characters, as macOS stores it).
        var names: [Int32: String]

        func isAlive(_ pid: Int32) -> Bool { names[pid] != nil }

        func contains(name: String) -> Bool { names.values.contains(name) }
    }

    /// The current processes, or nil if macOS refuses to list them.
    static func current() -> Snapshot? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        // Leave room for processes started between the two calls.
        size += size / 8
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, u_int(mib.count), &procs, &size, nil, 0) == 0 else { return nil }
        var names: [Int32: String] = [:]
        for proc in procs.prefix(size / stride) {
            let pid = proc.kp_proc.p_pid
            guard pid > 0 else { continue }
            names[pid] = withUnsafeBytes(of: proc.kp_proc.p_comm) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        return names.isEmpty ? nil : Snapshot(names: names)
    }
}
