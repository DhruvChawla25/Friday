import Foundation

/// Friday's voice: factual, brief, no emotion, no small talk.
/// All user-facing fixed strings live here so the tone stays consistent.
enum Persona {
    static let greeting = "Friday online. Type a command or say \"help\"."
    static let emptyCommand = "No command received."

    static func help(examples: [String]) -> String {
        "Available commands:\n" + examples.map { "• \($0)" }.joined(separator: "\n")
    }

    static func unrecognised(examples: [String]) -> String {
        "Command not recognised. " + help(examples: examples)
    }

    static let memoryDisabled = "Memory is off. Enable it in Settings to store facts."
    static let memorySaved = "Saved to memory."
    static let memoryEmpty = "Memory is empty."
    static let memoryWiped = "Memory wiped."
    static let memoryWriteFailed = "Could not write to the memory file."
    static let rememberWhat = "Specify what to remember, e.g. \"remember my work email is the one ending in .co\"."

    static func blocked(_ app: String) -> String {
        "\(app) is blocked by Friday's privacy rules."
    }
}
