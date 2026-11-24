// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// A single instruction typed (or later, spoken) by the user.
///
/// `raw` keeps the user's original text so skills can preserve casing
/// (e.g. a fact to remember). `normalized` is lowercased, trimmed, and has
/// trailing punctuation removed, which is what skills match against.
struct Command: Sendable, Equatable {
    let raw: String
    let normalized: String
    let words: [String]

    init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        raw = trimmed
        normalized =
            trimmed
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!.,").union(.whitespaces))
        words =
            normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    var isEmpty: Bool { raw.isEmpty }

    func contains(word: String) -> Bool { words.contains(word) }

    /// Returns the user's original text that follows `prefix` (case-insensitive),
    /// with surrounding whitespace and trailing punctuation removed.
    func argument(after prefix: String) -> String? {
        guard let range = raw.range(of: prefix, options: [.caseInsensitive, .anchored]) else {
            return nil
        }
        let rest = raw[range.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "?!.").union(.whitespaces))
        return rest.isEmpty ? nil : rest
    }
}
