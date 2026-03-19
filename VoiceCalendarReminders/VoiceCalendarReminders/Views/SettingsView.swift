import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @ObservedObject private var googleCalendar = GoogleCalendarService.shared
    @State private var showGoogleAuth = false
    @State private var showSignOutConfirmation = false
    @State private var defaultAlarmMinutes = 15
    @State private var selectedSound: AlarmSound = AlarmSoundManager.shared.selectedSound

    var body: some View {
        NavigationStack {
            List {
                googleAccountSection
                alarmSoundSection
                defaultsSection
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showGoogleAuth) {
                GoogleAuthView()
            }
            .confirmationDialog(
                "Sign out of Google?",
                isPresented: $showSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    googleCalendar.signOut()
                }
            } message: {
                Text("Events will no longer sync to Google Calendar.")
            }
        }
    }

    private var googleAccountSection: some View {
        Section {
            if googleCalendar.isSignedIn {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading) {
                        Text("Google Calendar Connected")
                            .font(.subheadline.bold())
                        if let email = googleCalendar.userEmail {
                            Text(email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Button("Sign Out", role: .destructive) {
                    showSignOutConfirmation = true
                }
            } else {
                Button(action: { showGoogleAuth = true }) {
                    HStack {
                        Image(systemName: "g.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)

                        VStack(alignment: .leading) {
                            Text("Connect Google Calendar")
                                .font(.subheadline.bold())
                            Text("Sync events to your Gmail calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("Google Account")
        } footer: {
            Text("Connect your Google account to automatically add voice events to Google Calendar.")
        }
    }

    private var alarmSoundSection: some View {
        Section {
            ForEach(AlarmSound.allCases) { sound in
                Button(action: {
                    selectedSound = sound
                    AlarmSoundManager.shared.selectedSound = sound
                    AlarmSoundManager.shared.previewSound(sound)
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sound.rawValue)
                                .foregroundStyle(.primary)
                            Text(soundDescription(sound))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedSound == sound {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.indigo)
                        }
                    }
                }
            }
        } header: {
            Text("Alarm Sound")
        } footer: {
            Text("Tap a sound to preview it and set it as your alarm tone. This plays when your event notification fires.")
        }
    }

    private func soundDescription(_ sound: AlarmSound) -> String {
        switch sound {
        case .radar: return "Fast repeating beeps"
        case .beacon: return "Slow, steady pulse"
        case .pulse: return "Heartbeat rhythm"
        case .chime: return "Ascending notes"
        case .alert: return "Urgent warbling tone"
        case .system: return "iPhone default notification sound"
        }
    }

    private var defaultsSection: some View {
        Section("Defaults") {
            Picker("Default Alarm", selection: $defaultAlarmMinutes) {
                Text("5 minutes before").tag(5)
                Text("10 minutes before").tag(10)
                Text("15 minutes before").tag(15)
                Text("30 minutes before").tag(30)
                Text("1 hour before").tag(60)
            }

            HStack {
                Text("iPhone Reminders")
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Built with")
                Spacer()
                Text("SwiftUI + Speech + EventKit")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

struct GoogleAuthView: View {
    @ObservedObject private var googleCalendar = GoogleCalendarService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isLoading = false
    @State private var error: String?
    private let contextProvider = AuthPresentationContext()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)

                Text("Sign in with Google")
                    .font(.title2.bold())

                Text("Allow Voice Calendar Reminders to access your Google Calendar to create and manage events.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button(action: startOAuth) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("Continue with Google")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoading)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func startOAuth() {
        guard let authURL = googleCalendar.getAuthorizationURL() else {
            error = "Failed to create authorization URL. Check your Google Client ID."
            return
        }

        isLoading = true

        let scheme = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_REDIRECT_SCHEME") as? String ?? ""

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: scheme) { callbackURL, sessionError in
            isLoading = false

            if let sessionError {
                if (sessionError as NSError).code != ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    error = sessionError.localizedDescription
                }
                return
            }

            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                error = "Failed to get authorization code."
                return
            }

            Task {
                do {
                    try await googleCalendar.handleAuthorizationCode(code)
                    await MainActor.run { dismiss() }
                } catch {
                    await MainActor.run {
                        self.error = error.localizedDescription
                    }
                }
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = contextProvider
        session.start()
    }
}
