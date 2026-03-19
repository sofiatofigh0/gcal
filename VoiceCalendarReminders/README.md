# Voice Calendar Reminders

An iOS app that lets you add events to Google Calendar and iPhone Reminders using your voice. Speak naturally — the app understands dates, times, and alarm requests, then syncs everything automatically.

## Features

- **Voice Input** — Tap the mic and speak naturally. The app uses Apple's Speech framework for on-device speech recognition.
- **Smart Parsing** — Understands natural phrases like "Meeting with Sarah tomorrow at 3pm", "Dentist appointment next Tuesday morning", or "Grocery run on Friday, set an alarm 30 minutes before".
- **Google Calendar Sync** — Automatically creates events in your Gmail/Google Calendar via OAuth2.
- **iPhone Reminders** — Adds tasks to the built-in Reminders app with due dates and alarms.
- **Alarm Notifications** — Schedules local notifications as alarms when you ask (e.g., "set an alarm", "remind me").
- **Edit Before Saving** — Review and adjust parsed events (title, date, time, alarm) before syncing.
- **Task Management** — View, filter by date, and delete synced tasks.

## Requirements

- iOS 16.0+
- Xcode 15.0+
- A physical iPhone (microphone + speech recognition don't work on the Simulator)
- A Google Cloud project with Calendar API enabled (for Google Calendar sync)

## Setup

### 1. Clone & Generate Xcode Project

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to manage the Xcode project file.

```bash
# Install XcodeGen if you don't have it
brew install xcodegen

# Navigate to the project directory
cd VoiceCalendarReminders

# Generate the Xcode project
xcodegen generate

# Open in Xcode
open VoiceCalendarReminders.xcodeproj
```

**Alternative (without XcodeGen):** Create a new Xcode project manually and drag in the `VoiceCalendarReminders/` source folder.

### 2. Configure Google Calendar API

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable the **Google Calendar API**
4. Go to **Credentials** → **Create Credentials** → **OAuth 2.0 Client ID**
5. Select **iOS** as the application type
6. Enter your app's Bundle ID: `com.voicecalendar.app`
7. Copy the **Client ID**

### 3. Update Info.plist

Open `VoiceCalendarReminders/App/Info.plist` and replace all instances of `YOUR_GOOGLE_CLIENT_ID` with your actual Google OAuth Client ID:

- `GOOGLE_CLIENT_ID` — Your full client ID (e.g., `123456789.apps.googleusercontent.com`)
- `GOOGLE_REDIRECT_URI` — `com.googleusercontent.apps.123456789:/oauthredirect`
- `GOOGLE_REDIRECT_SCHEME` — `com.googleusercontent.apps.123456789`
- `CFBundleURLSchemes` — `com.googleusercontent.apps.123456789`

### 4. Configure Signing

In Xcode:
1. Select the project in the navigator
2. Go to **Signing & Capabilities**
3. Select your development team
4. The bundle identifier should be `com.voicecalendar.app` (or change it to match your Google OAuth config)

### 5. Build & Run

1. Connect a physical iPhone
2. Select it as the build target
3. Build and run (⌘R)

## How to Use

### Adding Events by Voice

1. Open the app and go to the **Voice** tab
2. Tap the **microphone button** to start recording
3. Speak your events naturally:
   - "Doctor appointment tomorrow at 2pm"
   - "Team standup every Monday at 9am, set an alarm"
   - "Pick up groceries on Saturday afternoon"
   - "Call mom on March 25th at 6pm, remind me 30 minutes before"
4. Tap the mic again to stop recording
5. Review the parsed events — edit titles, dates, or toggle alarms
6. Tap **Add to Calendar & Reminders** to sync

### Managing Tasks

- Go to the **Tasks** tab to see all your synced events
- Filter by date using the filter icon
- Swipe left to delete individual tasks
- Use the menu to clear past tasks

### Google Calendar

- Go to **Settings** to connect your Google account
- Once connected, all new events are automatically added to your primary Google Calendar
- Events include proper time zones and alarm/reminder overrides

## Architecture

```
VoiceCalendarReminders/
├── App/
│   ├── VoiceCalendarRemindersApp.swift  — App entry point & permissions
│   └── Info.plist                       — Privacy descriptions & OAuth config
├── Models/
│   ├── VoiceTask.swift                  — Core task data model
│   └── ParsedEvent.swift                — Intermediate parsed event
├── Services/
│   ├── SpeechRecognitionService.swift   — Apple Speech framework wrapper
│   ├── NaturalLanguageParser.swift      — NLP date/time/alarm extraction
│   ├── GoogleCalendarService.swift      — Google OAuth2 + Calendar API
│   ├── ReminderService.swift            — EventKit reminders integration
│   ├── AlarmService.swift               — Local notification alarms
│   ├── KeychainHelper.swift             — Secure token storage
│   └── TaskPersistenceService.swift     — JSON file persistence
├── ViewModels/
│   ├── VoiceInputViewModel.swift        — Voice recording & sync orchestration
│   └── TaskListViewModel.swift          — Task list management
├── Views/
│   ├── ContentView.swift                — Tab-based main view
│   ├── VoiceInputView.swift             — Voice recording UI with live transcription
│   ├── TaskListView.swift               — Task list with filtering
│   └── SettingsView.swift               — Google account & preferences
└── Resources/
    └── Assets.xcassets                  — App icon & accent color
```

## Privacy & Permissions

The app requests the following permissions (all with clear usage descriptions):

| Permission | Purpose |
|---|---|
| Microphone | Record voice input |
| Speech Recognition | Convert speech to text |
| Reminders | Create iPhone Reminders |
| Notifications | Schedule alarm notifications |

All speech recognition is performed on-device when available. Google Calendar tokens are stored in the iOS Keychain.

## Supported Voice Phrases

The natural language parser understands a wide variety of phrases:

| Category | Examples |
|---|---|
| **Dates** | "tomorrow", "next Tuesday", "March 25th", "in 3 days" |
| **Times** | "at 3pm", "at 9:30am", "in the morning", "at noon" |
| **Alarms** | "set an alarm", "remind me", "alert me", "notify me" |
| **Alarm offsets** | "30 minutes before", "1 hour earlier", "10 min early" |
| **All day** | "all day", "whole day", "entire day" |
| **Multiple events** | "Meeting at 2pm and then dentist at 4pm" |

## License

MIT
