import Foundation

@MainActor
final class TaskListViewModel: ObservableObject {
    @Published var tasks: [VoiceTask] = []
    @Published var filterDate: Date? = nil
    @Published var showDeleteConfirmation = false
    @Published var taskToDelete: VoiceTask?

    private let persistence = TaskPersistenceService.shared
    private let googleCalendar = GoogleCalendarService.shared
    private let reminderService = ReminderService.shared
    private let alarmService = AlarmService.shared

    var filteredTasks: [VoiceTask] {
        if let filterDate {
            return tasks.filter {
                Calendar.current.isDate($0.date, inSameDayAs: filterDate)
            }
        }
        return tasks.sorted { $0.date < $1.date }
    }

    var upcomingTasks: [VoiceTask] {
        tasks.filter { $0.date > Date() }.sorted { $0.date < $1.date }
    }

    var pastTasks: [VoiceTask] {
        tasks.filter { $0.date <= Date() }.sorted { $0.date > $1.date }
    }

    func loadTasks() {
        tasks = persistence.loadTasks()
    }

    func deleteTask(_ task: VoiceTask) async {
        if let eventId = task.googleCalendarEventId {
            try? await googleCalendar.deleteEvent(eventId: eventId)
        }

        if let reminderId = task.reminderIdentifier {
            try? reminderService.deleteReminder(identifier: reminderId)
        }

        if let alarmId = task.alarmNotificationId {
            alarmService.cancelAlarm(identifier: alarmId)
        }

        tasks.removeAll { $0.id == task.id }
        persistence.saveTasks(tasks)
    }

    func clearAllPast() async {
        for task in pastTasks {
            await deleteTask(task)
        }
    }
}
