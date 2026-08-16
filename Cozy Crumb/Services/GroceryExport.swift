//
//  GroceryExport.swift
//  Cozy Crumb
//
//  Getting the list out of the app (§5.5): real Reminders checkboxes, a
//  checklist for Notes via the share sheet, and plain text on the clipboard.
//
//  A grocery list that can't leave the app isn't much use in a supermarket, so
//  all three routes are first-class rather than a share sheet afterthought.
//

import EventKit
import Foundation
import UIKit
import os

enum GroceryExport {

    // MARK: - Text

    /// One line per item, in the same supermarket-walk order the screen uses.
    nonisolated static func lines(for items: [GroceryLineItem]) -> [String] {
        items.map { item in
            let amount = FractionFormatter.quantityString(quantity: item.quantity, unit: item.unit)
            return amount.isEmpty ? item.name : "\(amount) \(item.name)"
        }
    }

    /// Notes turns `- [ ] ` into a real tickable checklist when you paste or
    /// share into it.
    nonisolated static func checklistText(for items: [GroceryLineItem]) -> String {
        lines(for: items)
            .map { "- [ ] \($0)" }
            .joined(separator: "\n")
    }

    nonisolated static func plainText(for items: [GroceryLineItem]) -> String {
        lines(for: items).joined(separator: "\n")
    }

    static func copyToClipboard(_ items: [GroceryLineItem]) {
        UIPasteboard.general.string = plainText(for: items)
    }
}

// MARK: - Reminders

/// EventKit access and writes, kept on the main actor: `EKEventStore` is not
/// `Sendable`, and hopping it between actors is exactly the kind of thing
/// strict concurrency is right to complain about.
@MainActor
enum RemindersExport {

    /// Sends every item to a Reminders list of the same name, creating that
    /// list the first time. Returns how many reminders were written.
    static func send(_ items: [GroceryLineItem], toListNamed listName: String) async throws -> Int {
        guard !items.isEmpty else { return 0 }

        let store = EKEventStore()

        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw CozyError.remindersDenied }

        let calendar = try calendar(named: listName, in: store)

        for line in GroceryExport.lines(for: items) {
            let reminder = EKReminder(eventStore: store)
            reminder.title = line
            reminder.calendar = calendar
            try store.save(reminder, commit: false)
        }

        try store.commit()
        return items.count
    }

    /// Reuses the user's existing list if they already have one by this name,
    /// so exporting twice doesn't leave them with "Groceries 2".
    private static func calendar(named name: String, in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == name }) {
            return existing
        }

        // A new calendar needs a source to live in. The account that already
        // holds the user's reminders is the right home; local storage is the
        // fallback when there's no iCloud account signed in.
        let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first { $0.sourceType == .local }
            ?? store.sources.first

        guard let source else { throw CozyError.remindersUnavailable }

        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = name
        calendar.source = source

        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            Log.data.error(
                "Could not create the Reminders list: \(error.localizedDescription, privacy: .public)"
            )
            // Better to drop the items into whatever list exists than to fail
            // the export outright.
            guard let fallback = store.defaultCalendarForNewReminders() else {
                throw CozyError.remindersUnavailable
            }
            return fallback
        }

        return calendar
    }
}
