import Foundation
import ConnorGraphStore

public struct AppGraphExtractionTracePresentation: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var outcome: GraphExtractionTraceOutcome
    public var admissionAction: GraphWriteAdmissionDecisionAction?
    public var createdAt: Date
    public var promptText: String?
    public var rawResponseJSON: String?
    public var normalizedJSON: String?
    public var decoderErrorKind: String?
    public var decoderErrorMessage: String?

    public init(trace: GraphExtractionTrace, payload: GraphExtractionTracePayload? = nil) {
        self.id = trace.id
        self.outcome = trace.outcome
        self.admissionAction = trace.admissionAction
        self.createdAt = trace.createdAt
        self.promptText = payload?.promptText
        self.rawResponseJSON = payload?.rawResponseJSON
        self.normalizedJSON = payload?.normalizedJSON
        self.decoderErrorKind = payload?.decoderErrorKind
        self.decoderErrorMessage = payload?.decoderErrorMessage
        self.title = "\(trace.outcome.rawValue) · \(trace.sourceType.rawValue) · \(trace.sourceID)"
        let reasons = trace.admissionReasons.map(\.rawValue).joined(separator: ", ")
        let counts = "extracted e/s: \(trace.extractedEntityCount)/\(trace.extractedStatementCount), committed e/s: \(trace.committedEntityCount)/\(trace.committedStatementCount), anomalies: \(trace.anomalyCount)"
        let action = trace.admissionAction?.rawValue ?? "none"
        let error = trace.errorMessage.map { " · error: \($0)" } ?? ""
        self.detail = "job: \(trace.jobID) · admission: \(action) · reasons: \(reasons.isEmpty ? "none" : reasons) · \(counts)\(error)"
    }
}

public struct AppGraphExtractionTraceRepository: @unchecked Sendable {
    public let store: SQLiteGraphKernelStore
    public var graphID: String

    public init(store: SQLiteGraphKernelStore, graphID: String = "default") {
        self.store = store
        self.graphID = graphID
    }

    public func loadRecentTraces(limit: Int = 100) throws -> [AppGraphExtractionTracePresentation] {
        try store.extractionTraces(graphID: graphID, limit: limit).map { trace in
            let payload = try store.extractionTracePayload(traceID: trace.id)
            return AppGraphExtractionTracePresentation(trace: trace, payload: payload)
        }
    }
}
