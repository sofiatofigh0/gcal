import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
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
    }
}
