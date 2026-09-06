import Foundation
import CryptoKit

/// M4-T1 · 跨设备网络传输层内核：1MiB 分块 / 组装（SHA-256 校验）/ 断点续传（端侧状态表）。
///
/// 分层：K4（BaseE2EECrypto）负责 E2EE 加解密，本层负责可靠传输——传的是 K4 加密后的字节
/// （包快照 canonicalData / 行数据导出 canonicalData / 密钥 base64 文本序列化）。
/// 契约口径：25 工具冻结（传输层非 Agent 工具面）、分块上限对齐 `quotas.maxRecordBytes = 1048576`（1MiB）、
/// 错误码复用契约 taxonomy（块缺失/重数/校验失配 → `VALIDATION_FAILED`，不新增错误码）。
///
/// 端侧断点续传：注册库 `base_transfer_payloads`（载荷元信息 + 完成标记）与
/// `base_transfer_chunks`（已收块，payload_id+chunk_index 主键，幂等覆盖）。
/// 对端经 `transferStatus` 拿已收块集合，发送端只补缺失块；组装按 index 升序拼接并整载荷 SHA-256 校验。

/// 单个传输块（1MiB 分块）。`payloadSHA256` 为**整载荷** SHA-256（所有块相同），接收端任一块即可获得组装校验锚点。
public struct BaseTransferChunk: Sendable, Equatable {
    public let payloadID: String
    public let index: Int
    public let totalChunks: Int
    public let payloadSHA256: String
    public let data: Data

    public init(payloadID: String, index: Int, totalChunks: Int, payloadSHA256: String, data: Data) {
        self.payloadID = payloadID
        self.index = index
        self.totalChunks = totalChunks
        self.payloadSHA256 = payloadSHA256
        self.data = data
    }
}

/// 载荷级传输元信息（整载荷 SHA-256 为组装校验锚点）。
public struct BaseTransferMeta: Sendable, Equatable {
    public let payloadID: String
    public let totalChunks: Int
    public let sha256: String

    public init(payloadID: String, totalChunks: Int, sha256: String) {
        self.payloadID = payloadID
        self.totalChunks = totalChunks
        self.sha256 = sha256
    }
}

/// 断点续传状态查询结果。
public struct BaseTransferStatus: Sendable, Equatable {
    public let payloadID: String
    public let totalChunks: Int
    public let sha256: String
    public let receivedChunks: [Int]
    public let complete: Bool

    public init(payloadID: String, totalChunks: Int, sha256: String,
                receivedChunks: [Int], complete: Bool) {
        self.payloadID = payloadID
        self.totalChunks = totalChunks
        self.sha256 = sha256
        self.receivedChunks = receivedChunks
        self.complete = complete
    }

    /// 缺失块集合（断点续传：发送端只补这些）。
    public var missingChunks: [Int] {
        Array(0..<totalChunks).filter { !receivedChunks.contains($0) }
    }
}

extension BaseLibraryStore {

    // MARK: 分块（发送端）

    /// 把载荷按 ≤chunkSize（默认 1MiB，对齐契约 maxRecordBytes）切成块。
    /// 空载荷 = 1 块（data 为空）。返回元信息（totalChunks + 整载荷 SHA-256）与块数组。
    public func chunk(payload: Data, payloadID: String,
                      chunkSize: Int = 1_048_576) throws -> (meta: BaseTransferMeta, chunks: [BaseTransferChunk]) {
        let pid = try validatedPayloadID(payloadID)
        let size = chunkSize > 0 ? chunkSize : 1_048_576
        let sha = Self.sha256Hex(payload)
        let total = max(1, (payload.count + size - 1) / size)
        var chunks: [BaseTransferChunk] = []
        chunks.reserveCapacity(total)
        var offset = 0
        for i in 0..<total {
            let end = min(offset + size, payload.count)
            chunks.append(BaseTransferChunk(payloadID: pid, index: i, totalChunks: total,
                                            payloadSHA256: sha, data: payload.subdata(in: offset..<end)))
            offset = end
        }
        return (BaseTransferMeta(payloadID: pid, totalChunks: total, sha256: sha), chunks)
    }

    // MARK: 组装（接收端，内存态校验）

    /// 按 index 升序拼接全部块并整载荷 SHA-256 校验。
    /// 失败（块数不符/缺块/重复 index/校验失配）→ `VALIDATION_FAILED`。
    public func assemble(_ chunks: [BaseTransferChunk], expectedSHA256: String) throws -> Data {
        guard !chunks.isEmpty else {
            throw BaseError(code: .validationFailed, message: "传输块为空", hint: "assemble 需要至少一块")
        }
        let payloadIDs = Set(chunks.map { $0.payloadID })
        guard payloadIDs.count == 1 else {
            throw BaseError(code: .validationFailed, message: "传输块 payloadID 不一致", hint: "同一载荷的块必须同 payloadID")
        }
        let total = chunks[0].totalChunks
        guard total > 0, chunks.allSatisfy({ $0.totalChunks == total }) else {
            throw BaseError(code: .validationFailed, message: "传输块 totalChunks 不一致", hint: "所有块须声明同一块数")
        }
        guard chunks.allSatisfy({ $0.payloadSHA256 == expectedSHA256 }) else {
            throw BaseError(code: .validationFailed, message: "传输块整载荷指纹不一致", hint: "块声明的 payloadSHA256 与期望不符")
        }
        let indexes = chunks.map { $0.index }.sorted()
        guard indexes == Array(0..<total) else {
            throw BaseError(code: .validationFailed, message: "传输块缺失或重复",
                            hint: "须完整覆盖 0..<totalChunks（缺失块：\(Array(0..<total).filter { !indexes.contains($0) })）")
        }
        var out = Data()
        out.reserveCapacity(chunks.reduce(0) { $0 + $1.data.count })
        for chunk in chunks.sorted(by: { $0.index < $1.index }) {
            out.append(chunk.data)
        }
        guard Self.sha256Hex(out) == expectedSHA256 else {
            throw BaseError(code: .validationFailed, message: "传输载荷校验失配",
                            hint: "组装结果 SHA-256 与声明不一致（内容被篡改或块不完整）")
        }
        return out
    }

    // MARK: 端侧断点续传状态表（注册库）

    /// 确保传输状态表存在：`base_transfer_payloads`（元信息 + 完成标记）+ `base_transfer_chunks`（已收块）。
    public func ensureTransferTables() throws {
        try registryExecuteVoid("""
            CREATE TABLE IF NOT EXISTS base_transfer_payloads (
                payload_id TEXT PRIMARY KEY,
                total_chunks INTEGER NOT NULL,
                sha256 TEXT NOT NULL,
                complete INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
            )
            """)
        try registryExecuteVoid("""
            CREATE TABLE IF NOT EXISTS base_transfer_chunks (
                payload_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                data_b64 TEXT NOT NULL,
                created_at TEXT NOT NULL,
                PRIMARY KEY (payload_id, chunk_index)
            )
            """)
    }

    /// 幂等保存一块（同 payloadID+index 覆盖）+ upsert 载荷元信息。
    public func storeChunk(_ chunk: BaseTransferChunk) throws {
        try ensureTransferTables()
        let pid = try validatedPayloadID(chunk.payloadID)
        guard chunk.index >= 0, chunk.totalChunks > 0 else {
            throw BaseError(code: .validationFailed, message: "传输块参数非法", hint: "index/totalChunks 须非负")
        }
        let dataB64 = chunk.data.base64EncodedString()
        try registryExecuteVoid("""
            INSERT OR REPLACE INTO base_transfer_chunks (payload_id, chunk_index, data_b64, created_at)
            VALUES (?1, ?2, ?3, ?4)
            """, parameters: [pid, chunk.index, dataB64, BaseTime.isoNow()])
        _ = try registryExecute("""
            INSERT INTO base_transfer_payloads (payload_id, total_chunks, sha256, complete, created_at)
            VALUES (?1, ?2, ?3, 0, ?4)
            ON CONFLICT(payload_id) DO UPDATE SET total_chunks = excluded.total_chunks
            """, parameters: [pid, chunk.totalChunks, chunk.payloadSHA256, BaseTime.isoNow()])
    }

    /// 断点续传状态：已收块集合 + 完成标记。payload 未知 → nil。
    public func transferStatus(payloadID: String) throws -> BaseTransferStatus? {
        try ensureTransferTables()
        let pid = try validatedPayloadID(payloadID)
        let rows = try registryExecute(
            "SELECT payload_id, total_chunks, sha256, complete FROM base_transfer_payloads WHERE payload_id = ?1",
            parameters: [pid])
        guard let row = rows.first else { return nil }
        let total = (row["total_chunks"] as? Int64).map(Int.init) ?? 0
        let sha = row["sha256"] as? String ?? ""
        let complete = (row["complete"] as? Int64) == 1
        let chunkRows = try registryExecute(
            "SELECT chunk_index FROM base_transfer_chunks WHERE payload_id = ?1 ORDER BY chunk_index",
            parameters: [pid])
        let received = chunkRows.compactMap { ($0["chunk_index"] as? Int64).map(Int.init) }
        return BaseTransferStatus(payloadID: pid, totalChunks: total, sha256: sha,
                                  receivedChunks: received, complete: complete)
    }

    /// 从状态表组装完整载荷（全块齐 + SHA-256 校验）。缺失/失配 → `VALIDATION_FAILED`。
    public func assembleStored(payloadID: String) throws -> Data {
        guard let status = try transferStatus(payloadID: payloadID) else {
            throw BaseError(code: .validationFailed, message: "传输载荷不存在", hint: "payloadID 未有已收块")
        }
        let rows = try registryExecute(
            "SELECT chunk_index, data_b64 FROM base_transfer_chunks WHERE payload_id = ?1 ORDER BY chunk_index",
            parameters: [status.payloadID])
        let chunks = try rows.map { row -> BaseTransferChunk in
            guard let index = (row["chunk_index"] as? Int64).map(Int.init),
                  let b64 = row["data_b64"] as? String, let data = Data(base64Encoded: b64) else {
                throw BaseError(code: .validationFailed, message: "传输块数据损坏", hint: "块 base64 解码失败")
            }
            return BaseTransferChunk(payloadID: status.payloadID, index: index,
                                     totalChunks: status.totalChunks, payloadSHA256: status.sha256, data: data)
        }
        return try assemble(chunks, expectedSHA256: status.sha256)
    }

    /// 标记载荷完成（组装校验通过后由调用方落标记；对端 K8 重建入口可据此跳断点）。
    public func markTransferComplete(payloadID: String) throws {
        try ensureTransferTables()
        let pid = try validatedPayloadID(payloadID)
        _ = try registryExecute("""
            UPDATE base_transfer_payloads SET complete = 1 WHERE payload_id = ?1
            """, parameters: [pid])
    }

    /// 清理载荷及其块（完成并消费后回收）。
    public func clearTransfer(payloadID: String) throws {
        try ensureTransferTables()
        let pid = try validatedPayloadID(payloadID)
        _ = try registryExecute("DELETE FROM base_transfer_chunks WHERE payload_id = ?1", parameters: [pid])
        _ = try registryExecute("DELETE FROM base_transfer_payloads WHERE payload_id = ?1", parameters: [pid])
    }

    // MARK: 私有

    private func validatedPayloadID(_ payloadID: String) throws -> String {
        let pid = payloadID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pid.isEmpty, pid.count <= 128 else {
            throw BaseError(code: .validationFailed, message: "payloadID 非法", hint: "payloadID 须非空且 ≤128 字符")
        }
        return pid
    }

    /// SHA-256 十六进制（传输载荷校验锚点，与 K1 快照指纹同一算法）。
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
