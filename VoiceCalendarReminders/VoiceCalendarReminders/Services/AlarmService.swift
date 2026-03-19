import Foundation
import UserNotifications

final class AlarmService {
    static let shared = AlarmService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleAlarm(for task: VoiceTask) async throws -> String {
        let content = UNMutableNotificationContent()
        content.title = "Upcoming: \(task.title)"
        content.body = alarmBody(for: task)
        content.sound = .defaultCritical
        content.categoryIdentifier = "TASK_ALARM"
        content.userInfo = ["taskId": task.id.uuidString]

        let alarmDate = task.date.addingTimeInterval(task.alarmOffset)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: alarmDate
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "alarm-\(task.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)
        return identifier
    }

    func cancelAlarm(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllAlarms() {
        center.removeAllPendingNotificationRequests()
    }

    private func alarmBody(for task: VoiceTask) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: task.date)
        return "\(task.title) at \(timeStr)"
    }

    func registerCategories() {
        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_ACTION",
            title: "Snooze 10 min",
            options: []
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ACTION",
            title: "Dismiss",
            options: .destructive
        )

        let category = UNNotificationCategory(
            identifier: "TASK_ALARM",
            actions: [snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category])
    }
}
