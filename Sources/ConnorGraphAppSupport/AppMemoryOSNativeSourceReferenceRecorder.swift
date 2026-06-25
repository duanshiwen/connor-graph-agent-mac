import Foundation
import ConnorGraphAgent

public struct AppMemoryOSNativeSourceReferenceRecorder: NativeSourceReferenceRecording, Sendable {
    public var facade: AppMemoryOSFacade

    public init(facade: AppMemoryOSFacade) {
        self.facade = facade
    }

    public func record(_ references: [NativeSourceReference]) async {
        for reference in references where !reference.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            do {
                _ = try facade.ingestSourceEvent(
                    sourceID: reference.deduplicationKey,
                    title: reference.title,
                    content: reference.content,
                    occurredAt: reference.occurredAt,
                    sourceKind: reference.sourceKind.rawValue,
                    accountID: reference.accountID,
                    sessionID: reference.sessionID,
                    metadata: reference.baseMetadata
                )
            } catch {
                // Source reference capture must not break the read-only native source tool path.
                // The foreground tool result is still useful to the LLM; failed memory capture can be
                // inspected through Memory OS operational diagnostics in future hardening stages.
                continue
            }
        }
    }
}
