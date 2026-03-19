import Foundation
import UserNotifications
import AVFoundation
import AudioToolbox
import UIKit

final class AlarmService: NSObject, ObservableObject {
    static let shared = AlarmService()
    private let center = UNUserNotificationCenter.current()
    private var audioPlayer: AVAudioPlayer?
    private var alarmTimer: Timer?
    @Published var activeAlarmTask: VoiceTask?

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
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            let granted = await requestAuthorization()
            guard granted else { throw AlarmError.notAuthorized }
        }

        let content = UNMutableNotificationContent()
        content.title = task.title
        content.body = alarmBody(for: task)
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "TASK_ALARM"
        content.userInfo = ["taskId": task.id.uuidString, "taskTitle": task.title]
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let alarmDate = task.date.addingTimeInterval(task.alarmOffset)

        guard alarmDate > Date() else {
            return "alarm-past-\(task.id.uuidString)"
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: alarmDate
        )

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "alarm-\(task.id.uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try await center.add(request)

        scheduleInAppAlarm(for: task, at: alarmDate)

        return identifier
    }

    // In-app alarm for when the app is in the foreground
    private func scheduleInAppAlarm(for task: VoiceTask, at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { return }

        DispatchQueue.main.async {
            self.alarmTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.triggerInAppAlarm(for: task)
                }
            }
        }
    }

    func triggerInAppAlarm(for task: VoiceTask) {
        playAlarmSound()
        activeAlarmTask = task
    }

    func dismissAlarm() {
        stopAlarmSound()
        activeAlarmTask = nil
    }

    func snoozeAlarm(minutes: Int = 10) {
        guard let task = activeAlarmTask else { return }
        stopAlarmSound()
        activeAlarmTask = nil

        let snoozeDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        scheduleInAppAlarm(for: task, at: snoozeDate)

        let content = UNMutableNotificationContent()
        content.title = "Snoozed: \(task.title)"
        content.body = "Will remind you again in \(minutes) minutes"
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "TASK_ALARM"
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: false)
        let request = UNNotificationRequest(identifier: "snooze-\(task.id.uuidString)", content: content, trigger: trigger)
        center.add(request)
    }

    private func playAlarmSound() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)

            // Use system alarm sound
            if let url = getSoundURL() {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer?.numberOfLoops = 10
                audioPlayer?.volume = 1.0
                audioPlayer?.play()
            } else {
                // Fallback: use system sound
                AudioServicesPlayAlertSound(SystemSoundID(1005))
            }
        } catch {
            AudioServicesPlayAlertSound(SystemSoundID(1005))
        }
    }

    private func getSoundURL() -> URL? {
        // Try system alarm sounds
        let paths = [
            "/System/Library/Audio/UISounds/alarm.caf",
            "/System/Library/Audio/UISounds/nano/alarm_nightstand_haptic.caf",
            "/System/Library/Audio/UISounds/New/Alarm.caf",
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func stopAlarmSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func cancelAlarm(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllAlarms() {
        center.removeAllPendingNotificationRequests()
        alarmTimer?.invalidate()
        alarmTimer = nil
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
            options: .foreground
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
            options: [.allowAnnouncement]
        )

        center.setNotificationCategories([category])
    }

    enum AlarmError: LocalizedError {
        case notAuthorized

        var errorDescription: String? {
            return "Notification permission denied. Go to Settings > Notifications and enable this app."
        }
    }
}

extension AlarmService: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show the notification even when the app is in the foreground
        completionHandler([.banner, .sound, .badge])

        let userInfo = notification.request.content.userInfo
        if let taskTitle = userInfo["taskTitle"] as? String {
            DispatchQueue.main.async {
                self.playAlarmSound()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "SNOOZE_ACTION":
            if let taskIdString = response.notification.request.content.userInfo["taskId"] as? String {
                let tasks = TaskPersistenceService.shared.loadTasks()
                if let task = tasks.first(where: { $0.id.uuidString == taskIdString }) {
                    snoozeAlarm(minutes: 10)
                }
            }
        case "DISMISS_ACTION":
            dismissAlarm()
        default:
            break
        }
        completionHandler()
    }
}
