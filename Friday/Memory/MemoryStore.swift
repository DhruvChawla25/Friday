// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Friday's optional memory: a single plain-text file the user owns.
///
/// - Off by default. Nothing is written until the user enables it.
/// - One fact per line: `2026-11-25 01:10 | fact`.
/// - Lines starting with `#` are comments and are ignored.
/// - The user can open, edit, export, or delete the file at any time.
struct MemoryStore: Sendable {
    static let enabledKey = "memoryEnabled"

    static let header = """
        # Friday memory file
        # Plain text, stored only on this Mac. One fact per line: "date | fact".
        # Friday reads this file and adds to it when you say "remember ...".
        # You can edit, copy, move or delete this file at any time.

        """

    let fileURL: URL
    /// `nil` means the app's standard defaults. Stored as a name (not a
    /// `UserDefaults` instance) so the store stays `Sendable`.
    private let defaultsSuite: String?

    init(fileURL: URL, defaultsSuite: String? = nil) {
        self.fileURL = fileURL
        self.defaultsSuite = defaultsSuite
    }

    private var defaults: UserDefaults { UserDefaults(suiteName: defaultsSuite) ?? .standard }

    static var standard: MemoryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return MemoryStore(
            fileURL: support.appending(path: "Friday/memory.txt")
        )
    }

    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    /// All stored facts, oldest first, without timestamps.
    func facts() -> [String] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return
            text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .map { line in
                guard let bar = line.range(of: " | ") else { return line }
                return String(line[bar.upperBound...])
            }
    }

    func append(_ fact: String, at date: Date = .now) throws {
        let clean = fact.replacingOccurrences(of: "\n", with: " ")
        let stamp = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let time = date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        try ensureFile()
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(stamp) \(time) | \(clean)\n".utf8))
    }

    /// Removes every fact but keeps the explanatory header.
    func wipe() throws {
        try ensureDirectory()
        try Data(Self.header.utf8).write(to: fileURL, options: .atomic)
    }

    func ensureFile() throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try wipe()
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
}
