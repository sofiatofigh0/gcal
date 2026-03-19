import Foundation

struct ParsedEvent {
    var title: String
    var date: Date?
    var endDate: Date?
    var hasAlarm: Bool
    var alarmOffset: TimeInterval
    var isAllDay: Bool
    var notes: String?

    init(
        title: String = "",
        date: Date? = nil,
        endDate: Date? = nil,
        hasAlarm: Bool = false,
        alarmOffset: TimeInterval = -900,
        isAllDay: Bool = false,
        notes: String? = nil
    ) {
        self.title = title
        self.date = date
        self.endDate = endDate
        self.hasAlarm = hasAlarm
        self.alarmOffset = alarmOffset
        self.isAllDay = isAllDay
        self.notes = notes
    }

    func toVoiceTask(rawTranscription: String) -> VoiceTask? {
        guard !title.isEmpty, let date = date else { return nil }
        return VoiceTask(
            title: title,
            notes: notes,
            date: date,
            endDate: endDate ?? date.addingTimeInterval(3600),
            hasAlarm: hasAlarm,
            alarmOffset: alarmOffset,
            isAllDay: isAllDay,
            rawTranscription: rawTranscription
        )
    }
}
