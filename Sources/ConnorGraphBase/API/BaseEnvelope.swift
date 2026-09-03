import Foundation

/// M1-K6：统一返回信封 `{ok, data, error, traceId, site, sync}`（§3.3 契约）。
public struct BaseEnvelope: Codable, Equatable, Sendable {
    public var ok: Bool
    public var data: JSONValue?
    public var error: BaseError?
    public var traceId: String
    /// 执行点：local（端侧子库）/ remote（服务端 RPC，M4）。
    public var site: String
    public var sync: BaseSyncState

    public init(
        ok: Bool,
        data: JSONValue? = nil,
        error: BaseError? = nil,
        traceId: String = BaseEnvelope.newTraceID(),
        site: String = "local",
        sync: BaseSyncState = BaseSyncState()
    ) {
        self.ok = ok
        self.data = data
        self.error = error
        self.traceId = traceId
        self.site = site
        self.sync = sync
    }

    public static func success(
        data: Any?,
        traceId: String = BaseEnvelope.newTraceID(),
        site: String = "local",
        sync: BaseSyncState = BaseSyncState()
    ) -> BaseEnvelope {
        BaseEnvelope(
            ok: true,
            data: data.flatMap { JSONValue(json: $0) },
            error: nil,
            traceId: traceId,
            site: site,
            sync: sync
        )
    }

    public static func failure(
        _ error: BaseError,
        traceId: String = BaseEnvelope.newTraceID(),
        site: String = "local"
    ) -> BaseEnvelope {
        BaseEnvelope(ok: false, data: nil, error: error, traceId: traceId, site: site, sync: BaseSyncState())
    }

    public static func newTraceID() -> String {
        String(UUID().uuidString.prefix(12))
    }

    /// 序列化为 JSON 字典（envelope 的传输形态）。
    public func asDictionary() -> [String: Any] {
        var out: [String: Any] = [
            "ok": ok,
            "traceId": traceId,
            "site": site,
            "sync": [
                "pending": sync.pending,
                "pendingPkgVersion": sync.pendingPkgVersion as Any,
                "lastSync": sync.lastSync as Any
            ]
        ]
        if let data {
            out["data"] = data.jsonObject
        }
        if let error {
            out["error"] = [
                "code": error.code,
                "message": error.message,
                "hint": error.hint,
                "retryable": error.retryable
            ]
        }
        return out
    }
}

/// 同步状态（§3.3 envelope.sync）：本地先写离线可用，M3 起填充。
public struct BaseSyncState: Codable, Equatable, Sendable {
    /// 待同步变更数。
    public var pending: Int
    /// 待同步包版本（包写乐观并发）。
    public var pendingPkgVersion: Int?
    /// 最近同步时间（ISO8601）。
    public var lastSync: String?

    public init(pending: Int = 0, pendingPkgVersion: Int? = nil, lastSync: String? = nil) {
        self.pending = pending
        self.pendingPkgVersion = pendingPkgVersion
        self.lastSync = lastSync
    }
}
