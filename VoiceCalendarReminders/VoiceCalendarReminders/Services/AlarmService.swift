import Foundation
import UserNotifications

final class AlarmService {
    static let shared = AlarmService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    func requestAuthorization() async -> Bool {
        do {
            // .timeSensitive lets alarms break through Focus modes (requires entitlement)
            var options: UNAuthorizationOptions = [.alert, .sound, .badge]
            if #available(iOS 15.0, *) {
                options.insert(.timeSensitive)
            }
            return try await center.requestAuthorization(options: options)
        } catch {
            return false
        }
    }

    func scheduleAlarm(for task: VoiceTask) async throws -> String {
        let content = UNMutableNotificationContent()
        content.title = "Alarm: \(task.title)"
        content.body = alarmBody(for: task)
        content.sound = .defaultCritical
        content.categoryIdentifier = "TASK_ALARM"
        content.userInfo = ["taskId": task.id.uuidString]

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

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

    /// Reschedule a notification 10 minutes from now (snooze).
    func snoozeAlarm(for request: UNNotificationRequest) async {
        guard let mutableContent = request.content.mutableCopy() as? UNMutableNotificationContent else { return }

        let snoozeDate = Date().addingTimeInterval(600)
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: snoozeDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "snooze-\(request.identifier)-\(Int(Date().timeIntervalSince1970))"
        let snoozeRequest = UNNotificationRequest(identifier: identifier, content: mutableContent, trigger: trigger)
        try? await center.add(snoozeRequest)
    }

    func cancelAlarm(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllAlarms() {
        center.removeAllPendingNotificationRequests()
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
            options: [.customDismissAction]
        )

        center.setNotificationCategories([category])
    }

    // MARK: - Private

    private func alarmBody(for task: VoiceTask) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let timeStr = formatter.string(from: task.date)
        return "\(task.title) at \(timeStr)"
    }
}
