import SwiftUI
import UserNotifications
import UIKit

@main
struct VoiceCalendarRemindersApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.requestPermissions()
                }
        }
    }
}

// MARK: - App Delegate (notification delegate + startup setup)

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Register snooze / dismiss actions so they appear on lock-screen banners
        AlarmService.shared.registerCategories()
        return true
    }

    // Show alarm banners even when the app is in the foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle Snooze / Dismiss taps from the lock screen or notification centre
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "SNOOZE_ACTION" {
            Task {
                await AlarmService.shared.snoozeAlarm(for: response.notification.request)
            }
        }
        completionHandler()
    }
}

// MARK: - App State

@MainActor
final class AppState: ObservableObject {
    @Published var isGoogleSignedIn = false
    @Published var permissionsGranted = false

    private let reminderService = ReminderService.shared
    private let alarmService = AlarmService.shared

    func requestPermissions() {
        Task {
            let remindersGranted  = await reminderService.requestAccess()
            let calendarGranted   = await reminderService.requestCalendarAccess()
            let notificationsGranted = await alarmService.requestAuthorization()
            permissionsGranted = remindersGranted && calendarGranted && notificationsGranted
        }
    }
}
