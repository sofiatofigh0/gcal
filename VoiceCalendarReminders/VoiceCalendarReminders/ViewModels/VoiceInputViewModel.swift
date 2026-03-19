import Foundation
import Combine

@MainActor
final class VoiceInputViewModel: ObservableObject {
    @Published var parsedEvents: [ParsedEvent] = []
    @Published var isProcessing = false
    @Published var statusMessage = ""
    @Published var showError = false
    @Published var errorMessage = ""

    let speechService = SpeechRecognitionService.shared
    private let parser = NaturalLanguageParser.shared
    private let googleCalendar = GoogleCalendarService.shared
    private let reminderService = ReminderService.shared
    private let alarmService = AlarmService.shared
    private let persistence = TaskPersistenceService.shared

    var isRecording: Bool { speechService.isRecording }
    var transcribedText: String { speechService.transcribedText }

    func toggleRecording() {
        if speechService.isRecording {
            speechService.stopRecording()
            processTranscription()
        } else {
            Task {
                _ = await speechService.requestAuthorization()
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
        guard !speechService.transcribedText.isEmpty else { return }
        parsedEvents = parser.parse(speechService.transcribedText)

        if parsedEvents.isEmpty {
            statusMessage = "Couldn't understand the events. Try including a title, or say 'remind me to…' for a reminder."
            return
        }

        let count = parsedEvents.count
        if parsedEvents.contains(where: \.needsDatePrompt) {
            statusMessage = "Found \(count) item\(count == 1 ? "" : "s"). Reminder-only items can be saved now, or you can add a date to turn them into scheduled reminders."
        } else {
            statusMessage = "Found \(count) item\(count == 1 ? "" : "s"). Review and confirm to add."
        }
    }

    func confirmAndSync() async {
        isProcessing = true
        statusMessage = "Syncing items..."

        var tasks = persistence.loadTasks()
        var successCount = 0
        var failureCount = 0
        var errors: [String] = []

        for event in parsedEvents {
            guard var task = event.toVoiceTask(rawTranscription: speechService.transcribedText) else {
                failureCount += 1
                continue
            }

            do {
                if googleCalendar.isSignedIn,
                   task.destination == .calendarAndReminder,
                   task.hasExplicitDate {
                    let eventId = try await googleCalendar.createEvent(task: task)
                    task.googleCalendarEventId = eventId
                }

                let reminderId = try await reminderService.createReminder(from: task)
                task.reminderIdentifier = reminderId

                if task.hasAlarm, task.hasExplicitDate {
                    let alarmId = try await alarmService.scheduleAlarm(for: task)
                    task.alarmNotificationId = alarmId.isEmpty ? nil : alarmId
                }

                task.status = .synced
                tasks.append(task)
                successCount += 1
            } catch {
                task.status = .failed
                tasks.append(task)
                failureCount += 1
                errors.append(error.localizedDescription)
            }
        }

        persistence.saveTasks(tasks)

        if failureCount == 0 {
            statusMessage = "Successfully saved \(successCount) item\(successCount == 1 ? "" : "s") to Calendar/Reminders."
        } else {
            let details = errors.first.map { " First error: \($0)" } ?? ""
            statusMessage = "Saved \(successCount), failed \(failureCount).\(details)"
        }

        parsedEvents = []
        isProcessing = false
    }

    func updateParsedEvent(at index: Int, title: String?, date: Date?, hasAlarm: Bool?) {
        guard index < parsedEvents.count else { return }
        if let title { parsedEvents[index].title = title }
        if let date {
            parsedEvents[index].date = date
            if parsedEvents[index].destination == .reminderOnly {
                parsedEvents[index].endDate = nil
            }
        }
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
