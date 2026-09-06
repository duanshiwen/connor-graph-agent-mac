import Foundation

/// Connor Base 错误码 taxonomy（M0 契约冻结，枚举含 11 个 code）。
public enum BaseErrorCode: String, Codable, CaseIterable, Sendable {
    case validationFailed = "VALIDATION_FAILED"
    case notFound = "NOT_FOUND"
    case permissionDenied = "PERMISSION_DENIED"
    case capabilityRequired = "CAPABILITY_REQUIRED"
    case guideOutOfSync = "GUIDE_OUT_OF_SYNC"
    case versionMismatch = "VERSION_MISMATCH"
    case migrationFailed = "MIGRATION_FAILED"
    case conflict = "CONFLICT"
    case quotaExceeded = "QUOTA_EXCEEDED"
    case rateLimited = "RATE_LIMITED"
    case `internal` = "INTERNAL"

    public var retryable: Bool {
        switch self {
        case .validationFailed, .notFound, .permissionDenied, .capabilityRequired,
             .guideOutOfSync, .quotaExceeded:
            return false
        case .versionMismatch, .migrationFailed, .conflict, .rateLimited, .internal:
            return true
        }
    }
}

/// 统一的错误结构（envelope.error 载荷）。
public struct BaseError: Error, Codable, Equatable, Sendable {
    public var code: String
    public var message: String
    public var hint: String
    public var retryable: Bool

    public init(code: String, message: String, hint: String, retryable: Bool? = nil) {
        self.code = code
        self.message = message
        self.hint = hint
        self.retryable = retryable ?? (BaseErrorCode(rawValue: code)?.retryable ?? false)
    }

    public init(code: BaseErrorCode, message: String, hint: String) {
        self.init(code: code.rawValue, message: message, hint: hint)
    }

    /// 从 schema 校验错误构造 VALIDATION_FAILED。
    public static func validation(_ reason: BaseSchemaValidator.Reason) -> BaseError {
        BaseError(
            code: .validationFailed,
            message: reason.message,
            hint: reason.hint
        )
    }

    public static func notFound(_ detail: String) -> BaseError {
        BaseError(code: .notFound, message: "App/表/记录/方法不存在", hint: detail)
    }

    public static func `internal`(_ detail: String) -> BaseError {
        BaseError(code: .internal, message: "内部错误", hint: detail)
    }
}
