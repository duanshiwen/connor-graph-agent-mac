import Foundation
import ConnorGraphCore

enum BrowserMediaSnapshotDecoder {
    static func decode(from data: Data) -> BrowserMediaSourceSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = parseISO8601Date(raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported ISO-8601 date: \(raw)")
        }
        return try? decoder.decode(BrowserMediaSourceSnapshot.self, from: data)
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: raw) { return date }

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]
        return withoutFractionalSeconds.date(from: raw)
    }
}
