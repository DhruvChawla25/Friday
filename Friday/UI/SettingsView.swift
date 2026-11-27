// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let memory: MemoryStore
    var shortcutAvailable = true
    var onResetOrb: () -> Void = {}
    @AppStorage(MemoryStore.enabledKey) private var memoryEnabled = false
    @State private var exporting = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                Toggle("Remember facts I tell Friday", isOn: $memoryEnabled)
                Text("Stored as plain text in memory.txt on this Mac only. Off by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Memory")
            }

            Section {
                HStack {
                    Button("Show in Finder") {
                        try? memory.ensureFile()
                        NSWorkspace.shared.activateFileViewerSelecting([memory.fileURL])
                    }
                    Button("Export…") { exporting = true }
                    Spacer()
                    Button("Wipe", role: .destructive) {
                        status = (try? memory.wipe()) != nil ? "Memory wiped." : "Wipe failed."
                    }
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Position", value: "Drag the orb; Friday remembers it per app")
                Button("Reset orb positions", action: onResetOrb)
            } header: {
                Text("Orb")
            }

            Section {
                LabeledContent("Network access", value: "None (blocked by macOS sandbox)")
                LabeledContent("Account", value: "Not required")
                LabeledContent("WhatsApp", value: "Reads the Dock badge number only")
                LabeledContent("Shortcut", value: shortcutAvailable ? "⌃⌥Space" : "⌃⌥Space (unavailable)")
                if !shortcutAvailable {
                    Text("Another app is using ⌃⌥Space. Quit it and reopen Friday, or click the orb.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fileExporter(
            isPresented: $exporting,
            document: MemoryDocument(text: memoryText()),
            contentType: .plainText,
            defaultFilename: "friday-memory.txt"
        ) { result in
            if case .success = result { status = "Exported." }
        }
    }

    private func memoryText() -> String {
        (try? String(contentsOf: memory.fileURL, encoding: .utf8)) ?? MemoryStore.header
    }
}

private struct MemoryDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
