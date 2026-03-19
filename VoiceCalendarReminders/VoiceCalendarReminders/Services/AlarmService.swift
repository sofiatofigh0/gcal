import Foundation
import UserNotifications

final class AlarmService: NSObject {
    static let shared = AlarmService()
    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
    }

    func configure() {
        center.delegate = self
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            if #available(iOS 15.0, *) {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
            }

            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleAlarm(for task: VoiceTask) async throws -> String {
        guard task.hasExplicitDate else {
            return ""
        }

        let alarmDate = task.date.addingTimeInterval(task.alarmOffset)
        let fireDate = max(alarmDate, Date().addingTimeInterval(1))

        let content = UNMutableNotificationContent()
        content.title = "Upcoming: \(task.title)"
        content.body = alarmBody(for: task)
        content.sound = .default
        content.categoryIdentifier = "TASK_ALARM"
        content.userInfo = ["taskId": task.id.uuidString]

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: fireDate
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "alarm-\(task.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)
        return identifier
    }

    func cancelAlarm(identifier: String) {
        guard !identifier.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func cancelAllAlarms() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    private func alarmBody(for task: VoiceTask) -> String {
        guard task.hasExplicitDate else {
            return task.title
        }

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

extension AlarmService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == "SNOOZE_ACTION" else { return }

        let content = UNMutableNotificationContent()
        content.title = response.notification.request.content.title
        content.body = response.notification.request.content.body
        content.sound = .default
        content.categoryIdentifier = response.notification.request.content.categoryIdentifier
        content.userInfo = response.notification.request.content.userInfo

        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(response.notification.request.identifier)-snooze-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }
}
