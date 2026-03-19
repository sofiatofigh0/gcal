import SwiftUI

@main
struct VoiceCalendarRemindersApp: App {
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

@MainActor
final class AppState: ObservableObject {
    @Published var isGoogleSignedIn = false
    @Published var permissionsGranted = false

    private let reminderService = ReminderService.shared
    private let alarmService = AlarmService.shared

    func requestPermissions() {
        AlarmSoundManager.shared.generateAllSounds()

        Task {
            let remindersGranted = await reminderService.requestAccess()
            let notificationsGranted = await alarmService.requestAuthorization()
            permissionsGranted = remindersGranted || notificationsGranted
        }
    }
}
