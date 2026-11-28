// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import Foundation

/// Suggests the closest known command for input no skill recognised.
/// Pure and offline: word-level edit distance against skill examples.
enum CommandSuggester {
    /// Minimum average word similarity (0...1) for a suggestion to be offered.
    static let threshold = 0.6

    /// Returns the best matching example (placeholders such as `<text>` removed), or nil.
    static func suggest(for input: String, examples: [String]) -> String? {
        let words = tokens(input)
        guard !words.isEmpty else { return nil }
        var best: (phrase: String, score: Double)?
        for example in examples {
            let stripped = example.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            let target = tokens(stripped)
            guard !target.isEmpty else { continue }
            let total = target.reduce(0.0) { sum, word in
                sum + (words.map { similarity($0, word) }.max() ?? 0)
            }
            let score = total / Double(target.count)
            if score >= threshold, score > (best?.score ?? 0) {
                best = (target.joined(separator: " "), score)
            }
        }
        return best?.phrase
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(a, b)) / Double(longest)
    }

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var row = [i]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                row.append(min(previous[j] + 1, row[j - 1] + 1, previous[j - 1] + cost))
            }
            previous = row
        }
        return previous[b.count]
    }
}
