import Foundation

@MainActor
final class MailHTMLRenderCache {
    private let capacity: Int
    private let byteCapacity: Int
    private var entries: [MailHTMLSanitizationRequest: MailPreparedHTMLBodyPresentation] = [:]
    private var entryByteCounts: [MailHTMLSanitizationRequest: Int] = [:]
    private var keysByRecency: [MailHTMLSanitizationRequest] = []
    private(set) var totalByteCount = 0

    init(capacity: Int = 8, byteCapacity: Int = 4 * 1_024 * 1_024) {
        self.capacity = max(0, capacity)
        self.byteCapacity = max(0, byteCapacity)
    }

    var count: Int { entries.count }
    var cachedRequests: Set<MailHTMLSanitizationRequest> { Set(entries.keys) }

    func value(for request: MailHTMLSanitizationRequest) -> MailPreparedHTMLBodyPresentation? {
        guard let value = entries[request] else { return nil }
        recordUse(of: request)
        return value
    }

    func insert(_ value: MailPreparedHTMLBodyPresentation, for request: MailHTMLSanitizationRequest) {
        guard capacity > 0, byteCapacity > 0 else { return }
        let byteCount = value.html.utf8.count
        guard byteCount <= byteCapacity else { return }
        if let previousByteCount = entryByteCounts[request] {
            totalByteCount -= previousByteCount
        }
        entries[request] = value
        entryByteCounts[request] = byteCount
        totalByteCount += byteCount
        recordUse(of: request)
        while entries.count > capacity || totalByteCount > byteCapacity {
            guard let leastRecent = keysByRecency.first else { break }
            remove(leastRecent)
        }
    }

    func removeAll() {
        entries.removeAll()
        entryByteCounts.removeAll()
        keysByRecency.removeAll()
        totalByteCount = 0
    }

    private func remove(_ request: MailHTMLSanitizationRequest) {
        keysByRecency.removeAll { $0 == request }
        entries.removeValue(forKey: request)
        totalByteCount -= entryByteCounts.removeValue(forKey: request) ?? 0
    }

    private func recordUse(of request: MailHTMLSanitizationRequest) {
        keysByRecency.removeAll { $0 == request }
        keysByRecency.append(request)
    }
}
