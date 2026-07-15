import Foundation

@MainActor
final class MailHTMLRenderCache {
    private let capacity: Int
    private var entries: [MailHTMLSanitizationRequest: MailPreparedHTMLBodyPresentation] = [:]
    private var keysByRecency: [MailHTMLSanitizationRequest] = []

    init(capacity: Int = 8) {
        self.capacity = max(0, capacity)
    }

    var count: Int { entries.count }
    var cachedRequests: Set<MailHTMLSanitizationRequest> { Set(entries.keys) }

    func value(for request: MailHTMLSanitizationRequest) -> MailPreparedHTMLBodyPresentation? {
        guard let value = entries[request] else { return nil }
        recordUse(of: request)
        return value
    }

    func insert(_ value: MailPreparedHTMLBodyPresentation, for request: MailHTMLSanitizationRequest) {
        guard capacity > 0 else { return }
        entries[request] = value
        recordUse(of: request)
        while entries.count > capacity, let leastRecent = keysByRecency.first {
            keysByRecency.removeFirst()
            entries.removeValue(forKey: leastRecent)
        }
    }

    func removeAll() {
        entries.removeAll()
        keysByRecency.removeAll()
    }

    private func recordUse(of request: MailHTMLSanitizationRequest) {
        keysByRecency.removeAll { $0 == request }
        keysByRecency.append(request)
    }
}
