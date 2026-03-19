import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var alarmService = AlarmService.shared
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                VoiceInputView()
                    .tabItem {
                        Label("Voice", systemImage: "mic.fill")
                    }
                    .tag(0)

                TaskListView()
                    .tabItem {
                        Label("Tasks", systemImage: "list.bullet.clipboard")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(2)
            }
            .tint(.indigo)

            if let task = alarmService.activeAlarmTask {
                AlarmOverlayView(task: task)
            }
        }
    }
}

struct AlarmOverlayView: View {
    let task: VoiceTask
    @ObservedObject private var alarmService = AlarmService.shared
    @State private var scale: CGFloat = 0.8
    @State private var bellRotation: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "alarm.waves.left.and.right.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(bellRotation))
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.15).repeatForever(autoreverses: true)) {
                            bellRotation = 15
                        }
                    }

                VStack(spacing: 8) {
                    Text(task.title)
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(task.formattedDate)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }

                HStack(spacing: 20) {
                    Button(action: {
                        alarmService.snoozeAlarm()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title2)
                            Text("Snooze")
                                .font(.callout)
                        }
                        .frame(width: 120, height: 70)
                        .background(.ultraThinMaterial)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    Button(action: {
                        alarmService.dismissAlarm()
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                            Text("Dismiss")
                                .font(.callout)
                        }
                        .frame(width: 120, height: 70)
                        .background(.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    scale = 1.0
                }
            }
        }
    }
}
