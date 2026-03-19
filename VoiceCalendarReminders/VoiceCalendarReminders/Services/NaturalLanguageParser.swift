import Foundation
import NaturalLanguage

final class NaturalLanguageParser {
    static let shared = NaturalLanguageParser()

    private let calendar = Calendar.current
    private let dateDetector: NSDataDetector?

    private init() {
        dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }

    func parse(_ text: String) -> [ParsedEvent] {
        let sentences = splitIntoEventSentences(text)
        return sentences.compactMap { parseSingleEvent($0, fullText: text) }
    }

    private func splitIntoEventSentences(_ text: String) -> [String] {
        let delimiters = [" and then ", " also ", " and also ", " plus "]
        var segments = [text]

        for delimiter in delimiters {
            segments = segments.flatMap { segment in
                segment.components(separatedBy: delimiter).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        return segments.filter { !$0.isEmpty }
    }

    private func parseSingleEvent(_ text: String, fullText: String) -> ParsedEvent? {
        var event = ParsedEvent()
        let lowered = text.lowercased()

        let dates = extractDates(from: text)
        if let firstDate = dates.first {
            event.date = firstDate
            if dates.count > 1 {
                event.endDate = dates[1]
            }
        }

        event.hasAlarm = detectAlarmRequest(lowered)
        event.alarmOffset = extractAlarmOffset(lowered)
        event.isAllDay = detectAllDay(lowered)
        event.destination = determineDestination(for: lowered, hasDate: event.date != nil)
        event.title = extractTitle(from: text)

        if event.title.isEmpty {
            return nil
        }

        if event.destination == .calendarAndReminder, event.date == nil {
            return nil
        }

        return event
    }

    private func determineDestination(for text: String, hasDate: Bool) -> TaskDestination {
        let reminderOnlyKeywords = [
            "remind me",
            "remember to",
            "todo",
            "to do",
            "task",
            "buy ",
            "pick up",
            "call ",
            "text ",
            "email "
        ]

        if reminderOnlyKeywords.contains(where: { text.contains($0) }) && !hasDate {
            return .reminderOnly
        }

        return .calendarAndReminder
    }

    private func extractDates(from text: String) -> [Date] {
        var dates: [Date] = []

        let range = NSRange(text.startIndex..., in: text)
        let matches = dateDetector?.matches(in: text, options: [], range: range) ?? []

        for match in matches {
            if let date = match.date {
                dates.append(normalizeDate(date))
            }
        }

        if dates.isEmpty {
            if let date = parseRelativeDate(text) {
                dates.append(date)
            }
        }

        return dates
    }

    private func parseRelativeDate(_ text: String) -> Date? {
        let lowered = text.lowercased()
        let now = Date()

        if lowered.contains("today") {
            return extractTimeOrDefault(from: lowered, on: now)
        }

        if lowered.contains("tomorrow") {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                return extractTimeOrDefault(from: lowered, on: tomorrow)
            }
        }

        let dayNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for (index, dayName) in dayNames.enumerated() {
            if lowered.contains(dayName) {
                let targetWeekday = index + 2
                let currentWeekday = calendar.component(.weekday, from: now)
                var daysAhead = targetWeekday - currentWeekday
                if daysAhead <= 0 { daysAhead += 7 }
                if lowered.contains("next") { daysAhead += 7 }
                if let targetDate = calendar.date(byAdding: .day, value: daysAhead, to: now) {
                    return extractTimeOrDefault(from: lowered, on: targetDate)
                }
            }
        }

        if lowered.contains("next week") {
            return calendar.date(byAdding: .weekOfYear, value: 1, to: now)
        }

        return nil
    }

    private func extractTimeOrDefault(from text: String, on date: Date) -> Date {
        let lowered = text.lowercased()

        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})\\s*(?::|\\.)\\s*(\\d{2})\\s*(am|pm)\\b", options: .caseInsensitive) {
            let range = NSRange(lowered.startIndex..., in: lowered)
            if let match = regex.firstMatch(in: lowered, range: range) {
                if let hourRange = Range(match.range(at: 1), in: lowered),
                   let minuteRange = Range(match.range(at: 2), in: lowered),
                   let periodRange = Range(match.range(at: 3), in: lowered) {
                    var hour = Int(lowered[hourRange]) ?? 0
                    let minute = Int(lowered[minuteRange]) ?? 0
                    let period = String(lowered[periodRange])
                    if period == "pm" && hour != 12 { hour += 12 }
                    if period == "am" && hour == 12 { hour = 0 }
                    return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
                }
            }
        }

        if let regex = try? NSRegularExpression(pattern: "\\b(\\d{1,2})\\s*(am|pm)\\b", options: .caseInsensitive) {
            let range = NSRange(lowered.startIndex..., in: lowered)
            if let match = regex.firstMatch(in: lowered, range: range) {
                if let hourRange = Range(match.range(at: 1), in: lowered),
                   let periodRange = Range(match.range(at: 2), in: lowered) {
                    var hour = Int(lowered[hourRange]) ?? 0
                    let period = String(lowered[periodRange])
                    if period == "pm" && hour != 12 { hour += 12 }
                    if period == "am" && hour == 12 { hour = 0 }
                    return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
                }
            }
        }

        if lowered.contains("noon") {
            return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        }
        if lowered.contains("morning") {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        if lowered.contains("afternoon") {
            return calendar.date(bySettingHour: 14, minute: 0, second: 0, of: date) ?? date
        }
        if lowered.contains("evening") {
            return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        }
        if lowered.contains("night") {
            return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: date) ?? date
        }
        if lowered.contains("midnight") {
            return calendar.date(bySettingHour: 0, minute: 0, second: 0, of: date) ?? date
        }

        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }

    private func normalizeDate(_ date: Date) -> Date {
        if date < Date() {
            if let adjusted = calendar.date(byAdding: .year, value: 1, to: date), adjusted > Date() {
                return adjusted
            }
        }
        return date
    }

    private func detectAlarmRequest(_ text: String) -> Bool {
        let alarmKeywords = [
            "alarm", "alert", "remind me", "set a reminder",
            "set an alarm", "notify me", "notification",
            "wake me", "buzz", "ring"
        ]
        return alarmKeywords.contains { text.contains($0) }
    }

    private func extractAlarmOffset(_ text: String) -> TimeInterval {
        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:minute|min)s?\\s*(?:before|early|earlier)", options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let minuteRange = Range(match.range(at: 1), in: text),
               let minutes = Int(text[minuteRange]) {
                return TimeInterval(-minutes * 60)
            }
        }

        if let regex = try? NSRegularExpression(pattern: "(\\d+)\\s*(?:hour|hr)s?\\s*(?:before|early|earlier)", options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let hourRange = Range(match.range(at: 1), in: text),
               let hours = Int(text[hourRange]) {
                return TimeInterval(-hours * 3600)
            }
        }

        return -900
    }

    private func detectAllDay(_ text: String) -> Bool {
        let allDayKeywords = ["all day", "whole day", "entire day", "full day"]
        return allDayKeywords.contains { text.contains($0) }
    }

    private func extractTitle(from text: String) -> String {
        var title = text

        let removalPatterns = [
            "\\b(?:set an? )?(?:alarm|alert|reminder|notification)\\s*(?:for)?\\b",
            "\\b(?:remind me (?:to|about))\\b",
            "\\b(?:remember to)\\b",
            "\\b(?:at|on|for)\\s+\\d{1,2}\\s*(?::|\\.)\\s*\\d{2}\\s*(?:am|pm)\\b",
            "\\b(?:at|on|for)\\s+\\d{1,2}\\s*(?:am|pm)\\b",
            "\\b(?:today|tomorrow|tonight)\\b",
            "\\b(?:next\\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\\b",
            "\\b(?:in the\\s+)?(?:morning|afternoon|evening|night)\\b",
            "\\bat\\s+(?:noon|midnight)\\b",
            "\\b\\d+\\s*(?:minute|min|hour|hr)s?\\s*(?:before|early|earlier)\\b",
            "\\b(?:all|whole|entire|full)\\s+day\\b",
            "\\bplease\\b",
            "\\bI need to\\b",
            "\\bI have to\\b",
            "\\bI want to\\b",
            "\\bI have\\b",
            "\\bI need\\b"
        ]

        for pattern in removalPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(title.startIndex..., in: title)
                title = regex.stringByReplacingMatches(in: title, range: range, withTemplate: "")
            }
        }

        title = title.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:-"))
        title = title.trimmingCharacters(in: .whitespaces)

        if let first = title.first {
            title = first.uppercased() + title.dropFirst()
        }

        return title
    }
}
