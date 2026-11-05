import Foundation

/// Bounds native text layout even for a single multi-megabyte paragraph. Page
/// boundaries preserve surrogate pairs; the original source remains unchanged.
public struct AppLargeTextPage: Equatable, Sendable {
    public static let expansionThreshold = 20_000
    public static let pageSize = 4_000

    public let text: String
    public let index: Int
    public let count: Int

    public init(source: String, index requestedIndex: Int = 0) {
        let units = source.utf16
        count = max(1, (units.count + Self.pageSize - 1) / Self.pageSize)
        index = min(max(0, requestedIndex), count - 1)
        func boundary(_ offset: Int) -> String.UTF16View.Index {
            var position = units.index(units.startIndex, offsetBy: offset)
            if position != units.endIndex, position != units.startIndex,
               (0xDC00...0xDFFF).contains(units[position]) {
                position = units.index(before: position)
            }
            return position
        }
        let start = boundary(index * Self.pageSize)
        let end = boundary(min((index + 1) * Self.pageSize, units.count))
        text = String(decoding: units[start..<end], as: UTF16.self)
    }
}
