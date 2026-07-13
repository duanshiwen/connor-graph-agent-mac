import Foundation
import os

/// Privacy-safe performance instrumentation for note import.
///
/// Never pass note content, source paths, prompts, or attachment names as metadata.
/// The stable fields below are limited to phase names, opaque IDs, counts, bytes,
/// and durations so traces can be captured from real imports without leaking data.
public enum NoteImportPerformanceLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ConnorGraphAgentMac"
    private static let logger = Logger(subsystem: subsystem, category: "NoteImport.Performance")
    private static let signposter = OSSignposter(subsystem: subsystem, category: "NoteImport")

    public struct Interval {
        fileprivate let state: OSSignpostIntervalState
        fileprivate let name: StaticString

        fileprivate init(state: OSSignpostIntervalState, name: StaticString) {
            self.state = state
            self.name = name
        }
    }

    public static func begin(
        _ name: StaticString,
        jobID: String,
        itemCount: Int = 0,
        byteCount: Int = 0
    ) -> Interval {
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(
            name,
            id: id,
            "job=\(jobID, privacy: .public) items=\(itemCount) bytes=\(byteCount)"
        )
        return Interval(state: state, name: name)
    }

    public static func end(
        _ interval: Interval,
        jobID: String,
        itemCount: Int = 0,
        byteCount: Int = 0
    ) {
        signposter.endInterval(
            interval.name,
            interval.state,
            "job=\(jobID, privacy: .public) items=\(itemCount) bytes=\(byteCount)"
        )
    }

    public static func event(
        _ name: StaticString,
        jobID: String,
        itemCount: Int = 0,
        byteCount: Int = 0
    ) {
        signposter.emitEvent(
            name,
            "job=\(jobID, privacy: .public) items=\(itemCount) bytes=\(byteCount)"
        )
    }

    public static func slowDatabaseOperation(
        _ operation: StaticString,
        elapsed: Duration,
        rowCount: Int = 0
    ) {
        let milliseconds = elapsed.components.seconds * 1_000
            + Int64(elapsed.components.attoseconds / 1_000_000_000_000_000)
        guard milliseconds >= 5 else { return }
        logger.warning(
            "Slow import database operation operation=\(operation, privacy: .public) elapsed_ms=\(milliseconds) rows=\(rowCount)"
        )
    }
}
