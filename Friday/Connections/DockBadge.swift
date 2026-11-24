import AppKit

/// Reads the badge on an app's Dock icon (the red unread number), using
/// macOS's own `lsappinfo` tool. Works for any app that badges its icon,
/// needs no permissions, and never touches the app's data or messages.
enum DockBadge {
    /// The badge as a count: `"5"` → 5, no badge → 0, a non-numeric badge
    /// such as `"•"` → 1. Returns nil if the output has no StatusLabel at all.
    static func count(fromLSAppInfo output: String) -> Int? {
        guard output.contains("StatusLabel") else { return nil }
        guard let match = output.firstMatch(of: /"label"="([^"]*)"/) else { return 0 }
        let label = match.1.trimmingCharacters(in: .whitespaces)
        if label.isEmpty { return 0 }
        let digits = label.filter(\.isNumber)
        return digits.isEmpty ? 1 : Int(digits) ?? 0
    }

    /// The running app's badge count, or nil if it is not running or unreadable.
    static func count(forBundleID bundleID: String) async -> Int? {
        guard
            let app = await MainActor.run(body: {
                NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            })
        else { return nil }
        let pid = app.processIdentifier
        return await Task.detached(priority: .utility) {
            guard let output = run("/usr/bin/lsappinfo", ["info", "-only", "StatusLabel", String(pid)]) else {
                return nil
            }
            return count(fromLSAppInfo: output)
        }.value
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
