import Foundation
import Combine

@MainActor
final class VoiceInputViewModel: ObservableObject {
    @Published var parsedEvents: [ParsedEvent] = []
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var isRecording = false
    @Published var transcribedText = ""

    let speechService = SpeechRecognitionService.shared
    private let parser = NaturalLanguageParser.shared
    private let googleCalendar = GoogleCalendarService.shared
    private let reminderService = ReminderService.shared
    private let alarmService = AlarmService.shared
    private let persistence = TaskPersistenceService.shared

    init() {
        speechService.$isRecording
            .receive(on: RunLoop.main)
            .assign(to: &$isRecording)

        speechService.$transcribedText
            .receive(on: RunLoop.main)
            .assign(to: &$transcribedText)

        speechService.onAutoStop = { [weak self] in
            self?.processTranscription()
        }
    }

    func toggleRecording() {
        if speechService.isRecording {
            speechService.stopRecording()
            processTranscription()
        } else {
            parsedEvents = []
            statusMessage = ""
            Task {
                let authorized = await speechService.requestAuthorization()
                guard authorized else {
                    errorMessage = "Microphone or Speech Recognition permission denied. Enable them in Settings > Privacy."
                    showError = true
                    return
                }
                do {
                    try speechService.startRecording()
                } catch {
                    errorMessage = "Failed to start recording: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }

    func processTranscription() {
        guard !transcribedText.isEmpty else { return }
        parsedEvents = parser.parse(transcribedText)

        if parsedEvents.isEmpty {
            statusMessage = "Couldn't understand the events. Please try again."
        } else {
            let count = parsedEvents.count
            statusMessage = "Found \(count) event\(count == 1 ? "" : "s"). Review and confirm to add."
        }
    }

    func confirmAndSync() async {
        isProcessing = true
        statusMessage = "Syncing events..."

        var tasks = persistence.loadTasks()
        var successCount = 0
        var failCount = 0
        var firstError: String?

        for event in parsedEvents {
            guard var task = event.toVoiceTask(rawTranscription: transcribedText) else {
                failCount += 1
                continue
            }

            var didSomething = false

            // Google Calendar
            if googleCalendar.isSignedIn {
                do {
                    let eventId = try await googleCalendar.createEvent(task: task)
                    task.googleCalendarEventId = eventId
                    didSomething = true
                } catch {
                    if firstError == nil { firstError = "Google Calendar failed" }
                }
            }

            // iPhone Calendar via EventKit
            do {
                let calEventId = try await reminderService.createCalendarEvent(from: task)
                task.calendarEventIdentifier = calEventId
                didSomething = true
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }

            // iPhone Reminders
            do {
                let reminderId = try await reminderService.createReminder(from: task)
                task.reminderIdentifier = reminderId
                didSomething = true
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }

            // In-app alarm + local notification (always scheduled, works independently)
            do {
                let alarmId = try await alarmService.scheduleAlarm(for: task)
                task.alarmNotificationId = alarmId
                didSomething = true
            } catch {
                if firstError == nil { firstError = error.localizedDescription }
            }

            if didSomething {
                task.status = .synced
                successCount += 1
            } else {
                task.status = .failed
                failCount += 1
            }

            tasks.append(task)
        }

        persistence.saveTasks(tasks)

        if failCount == 0 && successCount > 0 {
            statusMessage = "Successfully added \(successCount) event\(successCount == 1 ? "" : "s")!"
        } else if successCount > 0 {
            statusMessage = "Added \(successCount), \(failCount) failed."
        } else if let firstError {
            statusMessage = "Could not save: \(firstError)"
        } else {
            statusMessage = "Could not save events. Check permissions in Settings."
        }

        parsedEvents = []
        isProcessing = false
    }

    func updateParsedEvent(at index: Int, title: String?, date: Date?, hasAlarm: Bool?) {
        guard index < parsedEvents.count else { return }
        if let title { parsedEvents[index].title = title }
        if let date { parsedEvents[index].date = date }
        if let hasAlarm { parsedEvents[index].hasAlarm = hasAlarm }
    }

    func removeParsedEvent(at index: Int) {
        guard index < parsedEvents.count else { return }
        parsedEvents.remove(at: index)
    }

    func reset() {
        speechService.resetTranscription()
        parsedEvents = []
        statusMessage = ""
    }
}
