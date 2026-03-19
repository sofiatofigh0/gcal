# AGENTS.md

## Cursor Cloud specific instructions

This is a native **iOS/Swift** project (Voice Calendar Reminders). It **cannot** be fully built or run on Linux — it requires macOS with Xcode 15.0+ and a physical iPhone for end-to-end testing.

### What works on Linux (Cloud Agent VM)

- **Swift syntax checking**: `swiftc -parse <file.swift>` validates syntax for all 16 source files. The Swift 6.0.3 toolchain is installed at `/opt/swift/usr/bin`.
- **SwiftLint**: Installed at `/usr/local/bin/swiftlint`. Run from `VoiceCalendarReminders/` directory: `swiftlint lint`.
- **Model compilation**: Files that only import `Foundation` (e.g., `Models/VoiceTask.swift`, `Models/ParsedEvent.swift`) can be fully compiled and executed on Linux.
- **JSON round-trip tests**: The `VoiceTask` model supports `Codable`; you can write and run Swift scripts that exercise serialization logic.

### What does NOT work on Linux

- **Full iOS build** (`xcodegen generate` + `xcodebuild`): Requires macOS + Xcode + iOS SDK.
- **Apple-only framework imports** (`SwiftUI`, `Speech`, `EventKit`, `NaturalLanguage`, `UserNotifications`, `AuthenticationServices`, `AVFoundation`): These are unavailable on Linux. Files importing them pass `swiftc -parse` (syntax-only) but cannot be compiled to object code.
- **Running the app**: Requires a physical iPhone with iOS 16.0+.

### Key commands

| Task | Command | Working directory |
|------|---------|-------------------|
| Lint | `swiftlint lint` | `VoiceCalendarReminders/` |
| Syntax-check a file | `swiftc -parse <file.swift>` | any |
| Syntax-check all files | `for f in **/*.swift; do swiftc -parse "$f"; done` | `VoiceCalendarReminders/VoiceCalendarReminders/` |

### Project structure

- `VoiceCalendarReminders/project.yml` — XcodeGen project definition (generates `.xcodeproj`)
- `VoiceCalendarReminders/VoiceCalendarReminders/` — All Swift source files (16 files across App, Models, Services, ViewModels, Views)
- No third-party dependencies, no `Package.swift`, no `Podfile`
- No automated test target exists in the project

### Gotchas

- The project has zero third-party dependencies — all frameworks are Apple system frameworks.
- There is no test target defined in `project.yml`. Automated unit tests would need to be added manually.
- SwiftLint reports 31 warnings (no errors) on the current codebase; these are all style warnings (trailing commas, line length, etc.).
- PATH must include `/opt/swift/usr/bin` for `swift`/`swiftc` commands.
