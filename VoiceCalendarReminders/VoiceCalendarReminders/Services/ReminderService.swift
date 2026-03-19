import Foundation
import EventKit

final class ReminderService {
    static let shared = ReminderService()
    private let eventStore = EKEventStore()

    private init() {}

    func requestAccess() async -> Bool {
        let remindersGranted: Bool
        let calendarGranted: Bool

        if #available(iOS 17.0, *) {
            remindersGranted = (try? await eventStore.requestFullAccessToReminders()) ?? false
            calendarGranted = (try? await eventStore.requestFullAccessToEvents()) ?? false
        } else {
            remindersGranted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            calendarGranted = await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }

        return remindersGranted && calendarGranted
    }

    func createReminder(from task: VoiceTask) throws -> String {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = task.title
        reminder.notes = task.notes ?? "Created by Voice Calendar Reminders"
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: task.date
        )
        reminder.dueDateComponents = components

        if task.hasAlarm {
            let alarm = EKAlarm(relativeOffset: task.alarmOffset)
            reminder.addAlarm(alarm)
        }

        reminder.priority = Int(EKReminderPriority.medium.rawValue)

        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    func createCalendarEvent(from task: VoiceTask) throws -> String {
        let event = EKEvent(eventStore: eventStore)
        event.title = task.title
        event.notes = task.notes ?? "Created by Voice Calendar Reminders"
        event.startDate = task.date
        event.endDate = task.endDate ?? task.date.addingTimeInterval(3600)
        event.isAllDay = task.isAllDay
        event.calendar = eventStore.defaultCalendarForNewEvents

        if task.hasAlarm {
            let alarm = EKAlarm(relativeOffset: task.alarmOffset)
            event.addAlarm(alarm)
        }

        try eventStore.save(event, span: .thisEvent)
        return event.calendarItemIdentifier
    }

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
}
