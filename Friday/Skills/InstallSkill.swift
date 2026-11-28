// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Answers "what can I install" / "list dmgs" by listing disk images in Downloads.
struct InstallSkill: Skill {
    let name = "Install"
    let example = "what can I install"

    /// Folder to scan. Defaults to the real Downloads folder (needs the Downloads read entitlement).
    var downloads: @Sendable () -> URL? = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func canHandle(_ command: Command) -> Bool {
        let text = command.normalized
        return text.contains("what can i install") || text.contains("what could i install")
            || text == "list dmgs" || text == "list dmg" || text == "list dmg files"
            || text == "show dmgs" || text == "show dmg files"
    }

    func handle(_ command: Command) async -> String {
        guard let folder = downloads() else { return "I cannot find your Downloads folder." }
        return Self.reply(for: Self.listDMGs(in: folder))
    }

    struct Entry: Equatable {
        let name: String
        let size: Int64
        let modified: Date
    }

    /// Lists `*.dmg` files directly inside `folder`, newest first.
    static func listDMGs(in folder: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return
            urls
            .filter { $0.pathExtension.lowercased() == "dmg" }
            .compactMap { url -> Entry? in
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                    values.isRegularFile == true
                else { return nil }
                return Entry(
                    name: url.lastPathComponent,
                    size: Int64(values.fileSize ?? 0),
                    modified: values.contentModificationDate ?? .distantPast)
            }
            .sorted { $0.modified > $1.modified }
    }

    static func reply(for entries: [Entry]) -> String {
        guard !entries.isEmpty else { return "There are no DMG files in your Downloads folder." }
        let noun = entries.count == 1 ? "1 DMG" : "\(entries.count) DMGs"
        let lines = entries.map { "\($0.name) (\(formatted(size: $0.size)))" }
        return "You can install from \(noun) in Downloads, newest first:\n" + lines.joined(separator: "\n")
    }

    static func formatted(size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
