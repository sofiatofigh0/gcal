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
        var failureCount = 0

        for event in parsedEvents {
            guard var task = event.toVoiceTask(rawTranscription: speechService.transcribedText) else {
                failureCount += 1
                continue
            }

            do {
                if googleCalendar.isSignedIn {
                    let eventId = try await googleCalendar.createEvent(task: task)
                    task.googleCalendarEventId = eventId
                }

                let reminderId = try await reminderService.createReminder(from: task)
                task.reminderIdentifier = reminderId

                if task.hasAlarm {
                    let alarmId = try await alarmService.scheduleAlarm(for: task)
                    task.alarmNotificationId = alarmId
                }

                task.status = .synced
                tasks.append(task)
                successCount += 1
            } catch {
                task.status = .failed
                tasks.append(task)
                failureCount += 1
            }
        }

        persistence.saveTasks(tasks)

        if failureCount == 0 {
            statusMessage = "Successfully added \(successCount) event\(successCount == 1 ? "" : "s")!"
        } else {
            statusMessage = "Added \(successCount), failed \(failureCount)."
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
