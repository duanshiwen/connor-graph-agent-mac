import Foundation
import JavaScriptCore

/// Offline RFC 5545 evaluation. Each call owns an isolated JS VM; ICS is passed as data.
enum ICalendarOccurrenceEvaluator {
    static func evaluate(_ text: String, start: Date, end: Date, expanded: Bool = true) throws -> [ICalendarEvent] {
        guard text.utf8.count <= 10_000_000, end > start else { throw EvaluationError.invalid("日历内容过大或时间范围无效。") }
        guard let resource = Bundle.module.url(forResource: "ical.es5.min", withExtension: "cjs", subdirectory: "Calendar"),
              let bridge = Bundle.module.url(forResource: "occurrences", withExtension: "js", subdirectory: "Calendar"),
              let context = JSContext() else { throw EvaluationError.invalid("无法载入日历解析器。") }
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        let offset: @convention(block) (String, Int, Int, Int, Int, Int, Int) -> Double = { identifier, year, month, day, hour, minute, second in
            guard let zone = TimeZone(identifier: identifier) else { return .nan }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) else { return .nan }
            return Double(zone.secondsFromGMT(for: date))
        }
        context.setObject(offset, forKeyedSubscript: "connorZoneOffset" as NSString)
        context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
        context.evaluateScript(try String(contentsOf: resource, encoding: .utf8))
        context.evaluateScript(try String(contentsOf: bridge, encoding: .utf8))
        guard failure == nil, let function = context.objectForKeyedSubscript(expanded ? "connorOccurrences" : "connorSeries"),
              let json = function.call(withArguments: [text, start.timeIntervalSince1970, end.timeIntervalSince1970])?.toString(), failure == nil else {
            throw EvaluationError.invalid(failure ?? "日历重复实例无法解析。")
        }
        let rows = try JSONDecoder().decode([Row].self, from: Data(json.utf8))
        return rows.map { row in
            var event = ICalendarEvent(uid: row.uid, summary: row.summary,
                start: .init(date: Date(timeIntervalSince1970: row.start), timeZoneIdentifier: row.zone),
                end: .init(date: Date(timeIntervalSince1970: row.end), timeZoneIdentifier: row.zone),
                isAllDay: row.allDay, location: row.location, description: row.notes, url: row.url.flatMap(URL.init(string:)),
                recurrenceRule: row.rule, lastModified: row.modified.map(Date.init(timeIntervalSince1970:)), status: row.status,
                organizer: row.organizer.map(\.person), attendees: row.attendees.map(\.person))
            event.recurrenceIdentifier = row.recurrenceID
            return event
        }
    }

    static func mergeSeries(original: String, replacement: String, clearRecurrence: Bool = false) throws -> String {
        guard original.utf8.count <= 10_000_000, replacement.utf8.count <= 10_000_000,
              let resource = Bundle.module.url(forResource: "ical.es5.min", withExtension: "cjs", subdirectory: "Calendar"),
              let bridge = Bundle.module.url(forResource: "occurrences", withExtension: "js", subdirectory: "Calendar"),
              let context = JSContext() else { throw EvaluationError.invalid("无法载入日历解析器。") }
        var failure: String?
        context.exceptionHandler = { _, exception in failure = exception?.toString() }
        let offset: @convention(block) (String, Int, Int, Int, Int, Int, Int) -> Double = { identifier, year, month, day, hour, minute, second in
            guard let zone = TimeZone(identifier: identifier) else { return .nan }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) else { return .nan }
            return Double(zone.secondsFromGMT(for: date))
        }
        context.setObject(offset, forKeyedSubscript: "connorZoneOffset" as NSString)
        context.evaluateScript("var module = { exports: {} }; var exports = module.exports;")
        context.evaluateScript(try String(contentsOf: resource, encoding: .utf8))
        context.evaluateScript(try String(contentsOf: bridge, encoding: .utf8))
        guard failure == nil, let result = context.objectForKeyedSubscript("connorMergeSeries")?.call(withArguments: [original, replacement, clearRecurrence])?.toString(), failure == nil else {
            throw EvaluationError.invalid(failure ?? "无法保留原日历的重复例外。")
        }
        return result
    }
    private struct Person: Decodable {
        var name: String?; var email: String?; var role: String?; var status: String?
        var person: ICalendarEvent.Person { .init(name: name, email: email, role: role, participationStatus: status) }
    }
    private struct Row: Decodable {
        var uid: String; var summary: String; var start: Double; var end: Double; var allDay: Bool
        var zone: String?; var location: String?; var notes: String?; var url: String?; var rule: String?
        var modified: Double?; var status: String?; var recurrenceID: String?; var organizer: Person?; var attendees: [Person]
    }
    enum EvaluationError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
}
