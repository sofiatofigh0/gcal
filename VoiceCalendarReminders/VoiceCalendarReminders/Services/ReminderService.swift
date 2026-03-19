import Foundation
import EventKit

final class ReminderService {
    static let shared = ReminderService()
    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        let remindersGranted = await requestRemindersAccess()
        let calendarGranted = await requestCalendarAccess()
        return remindersGranted || calendarGranted
    }

    private func requestRemindersAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            if #available(iOS 17.0, *) {
                return (try? await eventStore.requestFullAccessToReminders()) ?? false
            } else {
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        default:
            return false
        }
    }

    private func requestCalendarAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        switch status {
        case .authorized, .fullAccess:
            return true
        case .notDetermined:
            if #available(iOS 17.0, *) {
                return (try? await eventStore.requestFullAccessToEvents()) ?? false
            } else {
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, _ in
                        continuation.resume(returning: granted)
                    }
                }
            }
        default:
            return false
        }
    }

    // MARK: - Reminders

    func createReminder(from task: VoiceTask) async throws -> String {
        let hasAccess = await requestRemindersAccess()
        guard hasAccess else {
            throw EventKitError.noRemindersAccess
        }

        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw EventKitError.noDefaultCalendar
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = task.title
        reminder.notes = task.notes ?? "Created by Voice Calendar Reminders"
        reminder.calendar = calendar

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: task.date
        )
        reminder.dueDateComponents = components

        let atTimeAlarm = EKAlarm(relativeOffset: 0)
        reminder.addAlarm(atTimeAlarm)

        if task.hasAlarm && task.alarmOffset < 0 {
            let earlyAlarm = EKAlarm(relativeOffset: task.alarmOffset)
            reminder.addAlarm(earlyAlarm)
        }

        reminder.priority = Int(EKReminderPriority.high.rawValue)

        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    // MARK: - Calendar Events

    func createCalendarEvent(from task: VoiceTask) async throws -> String {
        let hasAccess = await requestCalendarAccess()
        guard hasAccess else {
            throw EventKitError.noCalendarAccess
        }

        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw EventKitError.noDefaultCalendar
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = task.title
        event.notes = task.notes ?? "Created by Voice Calendar Reminders"
        event.startDate = task.date
        event.endDate = task.endDate ?? task.date.addingTimeInterval(3600)
        event.isAllDay = task.isAllDay
        event.calendar = calendar

        let atTimeAlarm = EKAlarm(relativeOffset: 0)
        event.addAlarm(atTimeAlarm)

        if task.hasAlarm && task.alarmOffset < 0 {
            let earlyAlarm = EKAlarm(relativeOffset: task.alarmOffset)
            event.addAlarm(earlyAlarm)
        }

        try eventStore.save(event, span: .thisEvent)
        return event.calendarItemIdentifier
    }

    // MARK: - Deletion

    func deleteReminder(identifier: String) throws {
        let predicate = eventStore.predicateForReminders(in: nil)

        let semaphore = DispatchSemaphore(value: 0)
        var foundReminder: EKReminder?

        eventStore.fetchReminders(matching: predicate) { reminders in
            foundReminder = reminders?.first { $0.calendarItemIdentifier == identifier }
            semaphore.signal()
        }
        semaphore.wait()

        if let reminder = foundReminder {
            try eventStore.remove(reminder, commit: true)
        }
    }

    func deleteCalendarEvent(identifier: String) {
        guard let event = eventStore.calendarItem(withIdentifier: identifier) as? EKEvent else { return }
        try? eventStore.remove(event, span: .thisEvent)
    }

    // MARK: - Errors

    enum EventKitError: LocalizedError {
        case noRemindersAccess
        case noCalendarAccess
        case noDefaultCalendar

        var errorDescription: String? {
            switch self {
            case .noRemindersAccess:
                return "No access to Reminders. Go to Settings > Privacy & Security > Reminders and enable this app."
            case .noCalendarAccess:
                return "No access to Calendar. Go to Settings > Privacy & Security > Calendars and enable this app."
            case .noDefaultCalendar:
                return "No default calendar found on this device."
            }
        }
    }
}
