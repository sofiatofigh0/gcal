import Foundation
import UserNotifications
import UIKit

final class AlarmService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlarmService()
    private let center = UNUserNotificationCenter.current()

    override private init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleAlarm(for task: VoiceTask) async throws -> String {
        // Schedule at the event time itself
        let atTimeId = try await scheduleNotification(
            for: task,
            at: task.date,
            identifier: "alarm-\(task.id.uuidString)",
            title: task.title,
            body: alarmBody(for: task)
        )

        // If user asked for an early alarm, schedule that too
        if task.hasAlarm && task.alarmOffset < 0 {
            let earlyDate = task.date.addingTimeInterval(task.alarmOffset)
            _ = try? await scheduleNotification(
                for: task,
                at: earlyDate,
                identifier: "alarm-early-\(task.id.uuidString)",
                title: "Coming up: \(task.title)",
                body: "\(task.title) in \(Int(abs(task.alarmOffset) / 60)) minutes"
            )
        }

        return atTimeId
    }

    private func scheduleNotification(
        for task: VoiceTask,
        at date: Date,
        identifier: String,
        title: String,
        body: String
    ) async throws -> String {
        guard date > Date() else {
            return "alarm-past-\(task.id.uuidString)"
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = AlarmSoundManager.shared.notificationSound()
        content.categoryIdentifier = "TASK_ALARM"
        content.userInfo = ["taskId": task.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)
        return identifier
    }

    func cancelAlarm(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier, "alarm-early-\(identifier)"])
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

    private func registerCategories() {
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

    // Show notification banner + sound even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
        AlarmSoundManager.shared.triggerHaptic()
    }

    // Handle snooze/dismiss actions
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "SNOOZE_ACTION" {
            let content = response.notification.request.content
            let snoozeContent = UNMutableNotificationContent()
            snoozeContent.title = content.title
            snoozeContent.body = content.body
            snoozeContent.sound = AlarmSoundManager.shared.notificationSound()
            snoozeContent.categoryIdentifier = "TASK_ALARM"

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)
            let request = UNNotificationRequest(
                identifier: "snooze-\(UUID().uuidString)",
                content: snoozeContent,
                trigger: trigger
            )
            center.add(request)
        }
        completionHandler()
    }
}
