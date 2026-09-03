import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K6：统一信封与错误码。
final class BaseEnvelopeTests: XCTestCase {

    func testErrorCodesMatchContract() {
        let codes = BaseErrorCode.allCases.map { $0.rawValue }
        XCTAssertEqual(codes, [
            "VALIDATION_FAILED", "NOT_FOUND", "PERMISSION_DENIED", "CAPABILITY_REQUIRED",
            "GUIDE_OUT_OF_SYNC", "VERSION_MISMATCH", "MIGRATION_FAILED", "CONFLICT",
            "QUOTA_EXCEEDED", "RATE_LIMITED", "INTERNAL"
        ])
    }

    func testRetryableFlags() {
        XCTAssertFalse(BaseErrorCode.validationFailed.retryable)
        XCTAssertFalse(BaseErrorCode.notFound.retryable)
        XCTAssertFalse(BaseErrorCode.permissionDenied.retryable)
        XCTAssertTrue(BaseErrorCode.versionMismatch.retryable)
        XCTAssertTrue(BaseErrorCode.conflict.retryable)
        XCTAssertTrue(BaseErrorCode.rateLimited.retryable)
    }

    func testSuccessEnvelopeCarriesDataAndTraceId() throws {
        let env = BaseEnvelope.success(data: ["applied": 1, "ids": ["a", "b"]])
        XCTAssertTrue(env.ok)
        XCTAssertNil(env.error)
        XCTAssertEqual(env.site, "local")
        XCTAssertFalse(env.traceId.isEmpty)
        let dict = env.asDictionary()
        XCTAssertEqual(dict["ok"] as? Bool, true)
        XCTAssertNotNil(dict["traceId"])
        XCTAssertNotNil(dict["sync"])
        XCTAssertNotNil(dict["data"])
        // 可 JSON 序列化（传输形态）
        let payload = try JSONSerialization.data(withJSONObject: dict)
        XCTAssertNotNil(payload)
    }

    func testFailureEnvelopeCarriesError() {
        let err = BaseError(code: .guideOutOfSync, message: "指南漂移", hint: "签名级变更须同批改指南")
        let env = BaseEnvelope.failure(err)
        XCTAssertFalse(env.ok)
        XCTAssertNil(env.data)
        XCTAssertEqual(env.error?.code, "GUIDE_OUT_OF_SYNC")
        XCTAssertFalse(env.error?.retryable ?? true)
        let dict = env.asDictionary()
        let errorDict = dict["error"] as? [String: Any]
        XCTAssertEqual(errorDict?["code"] as? String, "GUIDE_OUT_OF_SYNC")
    }

    func testEnvelopeRoundTripJSON() throws {
        let env = BaseEnvelope.success(data: ["n": 5])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(env)
        let decoded = try decoder.decode(BaseEnvelope.self, from: data)
        XCTAssertEqual(decoded, env)
    }
}
