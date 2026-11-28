// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import FoundationModels

/// Whether Apple's on-device model can be used, in plain language.
enum AIStatus: Equatable {
    case ready
    case notEnabled
    case deviceNotEligible
    case modelNotReady
    case unknown

    /// Short label for the dashboard header.
    var label: String {
        switch self {
        case .ready: "AI: READY"
        case .notEnabled: "AI: NOT ENABLED"
        case .deviceNotEligible: "AI: DEVICE NOT ELIGIBLE"
        case .modelNotReady: "AI: MODEL DOWNLOADING"
        case .unknown: "AI: UNAVAILABLE"
        }
    }

    /// One-sentence explanation, for tooltips.
    var detail: String {
        switch self {
        case .ready: "Apple Intelligence is ready on this Mac."
        case .notEnabled: "Turn on Apple Intelligence in System Settings."
        case .deviceNotEligible: "This Mac does not support Apple Intelligence."
        case .modelNotReady: "The on-device model is still downloading. Try again later."
        case .unknown: "Apple Intelligence is unavailable for an unknown reason."
        }
    }

    var isReady: Bool { self == .ready }

    /// Pure mapping, kept separate from the framework call so it can be tested.
    static func map(_ availability: SystemLanguageModel.Availability) -> AIStatus {
        switch availability {
        case .available: .ready
        case .unavailable(.appleIntelligenceNotEnabled): .notEnabled
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .unknown
        }
    }

    static var current: AIStatus { map(SystemLanguageModel.default.availability) }
}
