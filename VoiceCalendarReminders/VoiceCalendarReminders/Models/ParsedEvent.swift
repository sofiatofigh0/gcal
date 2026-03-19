import Foundation

enum TaskDestination: String, Codable {
    case calendarAndReminder
    case reminderOnly
}

struct ParsedEvent {
    var title: String
    var date: Date?
    var endDate: Date?
    var hasAlarm: Bool
    var alarmOffset: TimeInterval
    var isAllDay: Bool
    var notes: String?
    var destination: TaskDestination

    init(
        title: String = "",
        date: Date? = nil,
        endDate: Date? = nil,
        hasAlarm: Bool = false,
        alarmOffset: TimeInterval = -900,
        isAllDay: Bool = false,
        notes: String? = nil,
        destination: TaskDestination = .calendarAndReminder
    ) {
        self.title = title
        self.date = date
        self.endDate = endDate
        self.hasAlarm = hasAlarm
        self.alarmOffset = alarmOffset
        self.isAllDay = isAllDay
        self.notes = notes
        self.destination = destination
    }

    var needsDatePrompt: Bool {
        destination == .reminderOnly && date == nil
    }

    func toVoiceTask(rawTranscription: String) -> VoiceTask? {
        guard !title.isEmpty else { return nil }

        let effectiveDate = date ?? Date()

        return VoiceTask(
            title: title,
            notes: notes,
            date: effectiveDate,
            endDate: endDate ?? (date != nil ? effectiveDate.addingTimeInterval(3600) : nil),
            hasAlarm: hasAlarm,
            alarmOffset: alarmOffset,
            isAllDay: isAllDay,
            rawTranscription: rawTranscription,
            destination: destination,
            hasExplicitDate: date != nil
        )
    }
}
