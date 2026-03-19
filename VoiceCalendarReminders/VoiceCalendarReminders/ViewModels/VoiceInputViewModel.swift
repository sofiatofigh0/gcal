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
    private var cancellables = Set<AnyCancellable>()

    init() {
        speechService.$isRecording
            .receive(on: RunLoop.main)
            .assign(to: &$isRecording)

        speechService.$transcribedText
            .receive(on: RunLoop.main)
            .assign(to: &$transcribedText)

        speechService.$errorMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] message in
                self?.errorMessage = message
                self?.showError = true
            }
            .store(in: &cancellables)

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
        var errors: [String] = []

        for event in parsedEvents {
            guard var task = event.toVoiceTask(rawTranscription: transcribedText) else {
                errors.append("Could not parse event.")
                continue
            }

            var taskErrors: [String] = []

            // Google Calendar — independent, skip if not signed in
            if googleCalendar.isSignedIn {
                do {
                    let eventId = try await googleCalendar.createEvent(task: task)
                    task.googleCalendarEventId = eventId
                } catch {
                    taskErrors.append("Google Calendar: \(error.localizedDescription)")
                }
            }

            // iPhone Calendar via EventKit — creates a native calendar event with alarm
            do {
                let calEventId = try reminderService.createCalendarEvent(from: task)
                task.calendarEventIdentifier = calEventId
            } catch {
                taskErrors.append("Calendar: \(error.localizedDescription)")
            }

            // iPhone Reminders
            do {
                let reminderId = try reminderService.createReminder(from: task)
                task.reminderIdentifier = reminderId
            } catch {
                taskErrors.append("Reminders: \(error.localizedDescription)")
            }

            // Local notification alarm (backup alarm)
            if task.hasAlarm {
                do {
                    let alarmId = try await alarmService.scheduleAlarm(for: task)
                    task.alarmNotificationId = alarmId
                } catch {
                    taskErrors.append("Notification alarm: \(error.localizedDescription)")
                }
            }

            if taskErrors.isEmpty {
                task.status = .synced
                successCount += 1
            } else if task.calendarEventIdentifier != nil || task.reminderIdentifier != nil {
                // Partial success — at least one integration worked
                task.status = .synced
                successCount += 1
                errors.append(contentsOf: taskErrors)
            } else {
                task.status = .failed
                errors.append(contentsOf: taskErrors)
            }

            tasks.append(task)
        }

        persistence.saveTasks(tasks)

        if errors.isEmpty {
            statusMessage = "Successfully added \(successCount) event\(successCount == 1 ? "" : "s")!"
        } else if successCount > 0 {
            statusMessage = "Added \(successCount) event\(successCount == 1 ? "" : "s"). Some issues: \(errors.joined(separator: "; "))"
        } else {
            statusMessage = "Failed: \(errors.joined(separator: "; "))"
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
