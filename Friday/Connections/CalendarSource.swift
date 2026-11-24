// Friday — local-first macOS assistant
// Copyright (c) 2026 Dhruv Chawla
// SPDX-License-Identifier: MIT

import EventKit

/// Today's schedule from the macOS Calendar database (includes any Google
/// calendars added in System Settings → Internet Accounts). Read-only.
@MainActor
final class CalendarSource {
    struct Summary: Equatable {
        let remainingToday: Int
        let nextTitle: String?
        let nextStart: Date?
    }

    private let store = EKEventStore()

    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func summary(now: Date = .now) -> Summary? {
        guard isAuthorized else { return nil }
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return nil
        }
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        let next = events.first { $0.startDate >= now } ?? events.first
        return Summary(remainingToday: events.count, nextTitle: next?.title, nextStart: next?.startDate)
    }
}
