import Foundation

struct VoiceTask: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var notes: String?
    var date: Date
    var endDate: Date?
    var hasAlarm: Bool
    var alarmOffset: TimeInterval
    var isAllDay: Bool
    var rawTranscription: String
    var status: TaskStatus
    var destination: TaskDestination
    var hasExplicitDate: Bool

    var googleCalendarEventId: String?
    var reminderIdentifier: String?
    var alarmNotificationId: String?

    enum TaskStatus: String, Codable {
        case pending
        case synced
        case failed
    }

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        date: Date,
        endDate: Date? = nil,
        hasAlarm: Bool = false,
        alarmOffset: TimeInterval = -900,
        isAllDay: Bool = false,
        rawTranscription: String = "",
        status: TaskStatus = .pending,
        destination: TaskDestination = .calendarAndReminder,
        hasExplicitDate: Bool = true
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.date = date
        self.endDate = endDate
        self.hasAlarm = hasAlarm
        self.alarmOffset = alarmOffset
        self.isAllDay = isAllDay
        self.rawTranscription = rawTranscription
        self.status = status
        self.destination = destination
        self.hasExplicitDate = hasExplicitDate
    }
}

extension VoiceTask {
    var formattedDate: String {
        if destination == .reminderOnly && !hasExplicitDate {
            return "No due date"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = isAllDay ? .none : .short
        return formatter.string(from: date)
    }

    var formattedAlarmOffset: String {
        let minutes = Int(abs(alarmOffset) / 60)
        if minutes < 60 {
            return "\(minutes) min before"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) hr before"
        }
        return "\(hours) hr \(remainingMinutes) min before"
    }

    var sortDate: Date {
        hasExplicitDate ? date : .distantFuture
    }
}
