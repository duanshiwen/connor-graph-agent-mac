import Foundation

public struct GetCurrentTimeTool: AgentTool {
    public var name: String { "get_current_time" }
    public var description: String { "Get the current system date and time. Use this instead of guessing whenever the user asks about the current date, current time, today, now, or time-sensitive information." }
    public var permission: AgentPermissionCapability { .readSession }
    public var inputSchema: AgentToolInputSchema {
        .closedObject(properties: [
            "time_zone": .string(description: "Optional IANA time zone identifier, for example Asia/Shanghai. Defaults to the system time zone.")
        ], required: [])
    }

    private let fixedNow: Date?
    private let defaultTimeZoneIdentifier: String

    public init(now: Date? = nil, defaultTimeZone: TimeZone = .current) {
        self.fixedNow = now
        self.defaultTimeZoneIdentifier = defaultTimeZone.identifier
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        let now = fixedNow ?? Date()
        let requestedTimeZoneIdentifier = arguments.string("time_zone")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeZoneIdentifier = requestedTimeZoneIdentifier?.isEmpty == false ? requestedTimeZoneIdentifier! : defaultTimeZoneIdentifier
        guard let timeZone = TimeZone(identifier: timeZoneIdentifier) else {
            throw AgentToolError.invalidArguments("Invalid IANA time zone identifier: \(timeZoneIdentifier)")
        }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        isoFormatter.timeZone = timeZone
        let iso8601 = isoFormatter.string(from: now)

        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: "en_US_POSIX")
        displayFormatter.calendar = Calendar(identifier: .gregorian)
        displayFormatter.timeZone = timeZone
        displayFormatter.dateFormat = "EEEE, yyyy-MM-dd HH:mm:ss zzz"
        let display = displayFormatter.string(from: now)

        let contentJSON = LocalToolJSON.encode([
            "iso8601": iso8601,
            "unix_timestamp": now.timeIntervalSince1970,
            "time_zone": timeZone.identifier,
            "time_zone_seconds_from_gmt": timeZone.secondsFromGMT(for: now),
            "display": display
        ])

        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Current time: \(display)",
            contentJSON: contentJSON
        )
    }
}

public extension AgentToolRegistry {
    mutating func registerCurrentTimeTool(now: Date? = nil, defaultTimeZone: TimeZone = .current) {
        register(GetCurrentTimeTool(now: now, defaultTimeZone: defaultTimeZone))
    }
}
