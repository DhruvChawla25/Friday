import SwiftUI

/// The main Friday surface: a log of exchanges and a command field.
struct CommandView: View {
    let assistant: Assistant
    /// Provided when shown in the floating panel; nil in the menu bar popover.
    var onMinimize: (() -> Void)? = nil
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            log
            Divider()
            input
        }
        .onAppear { fieldFocused = true }
    }

    private var header: some View {
        HStack {
            Image(systemName: "circle.hexagongrid.fill")
                .foregroundStyle(.tint)
            Text("FRIDAY")
                .font(.system(.headline, design: .monospaced))
                .tracking(3)
            Spacer()
            Text("offline")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Menu {
                if let onMinimize {
                    Button("Minimize", action: onMinimize)
                        .keyboardShortcut("m", modifiers: .command)
                }
                Button("Clear log") { assistant.clearLog() }
                    .disabled(assistant.exchanges.isEmpty)
                SettingsLink { Text("Settings…") }
                Divider()
                Button("Quit Friday") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if assistant.exchanges.isEmpty {
                        Text(Persona.greeting)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(assistant.exchanges) { exchange in
                        ExchangeRow(exchange: exchange).id(exchange.id)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: assistant.exchanges.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var input: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
            TextField("Command", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .focused($fieldFocused)
                .onSubmit(send)
            if assistant.isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(14)
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await assistant.submit(text) }
    }
}

private struct ExchangeRow: View {
    let exchange: Assistant.Exchange

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("› \(exchange.request)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(exchange.reply)
                .textSelection(.enabled)
        }
    }
}
