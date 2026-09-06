import Foundation
import CryptoKit

/// M3-K4 · E2EE 层：base_keys 密钥生成 + 同步载荷 AES-256-GCM 加解密（Mac CryptoKit）。
///
/// 同步对象④ `base_keys` 承载 E2EE 密钥材料：master 密钥（设备锚点，kind=master, app_id=""）
/// 与每 App 密钥（kind=app, app_id=<appID>）。同步载荷（包快照 canonicalData / 行数据导出 canonicalData）
/// 以对应 App 密钥 AES-256-GCM 加密传输：对端拉密钥后解密还原，再以明文指纹做 golden 对账。
///
/// 密钥按 base64 存 payload_json；生成幂等（已存在即返回既有，不重复落库）。
/// envelope 载荷：{"algorithm":"AES-256-GCM", "nonce", "ciphertext", "tag", "createdAt"}（base64）。
/// 解密鉴权失败（密钥不符/篡改）由 AES.GCM.open 抛错，不产生可用的明文（E2EE 完整性保证）。
extension BaseLibraryStore {

    // MARK: 密钥生成（幂等）

    /// 生成或取回设备 master 密钥（kind=master, app_id=""）。返回 base64 载荷。
    @discardableResult
    public func ensureMasterKey() throws -> String {
        try ensureKeysTable()
        if let existing = try syncKeyPayload(kind: "master", appID: "") { return existing }
        let key = SymmetricKey(size: .bits256)
        let b64 = key.withUnsafeBytes { Data($0).base64EncodedString() }
        try saveSyncKey(keyID: "master_key", kind: "master", appID: "", payloadJSON: b64)
        return b64
    }

    /// 生成或取回某 App 的 E2EE 密钥（kind=app, app_id=<appID>）。返回 base64 载荷。
    @discardableResult
    public func syncAppKey(appID: String) throws -> String {
        try ensureKeysTable()
        if let existing = try syncKeyPayload(kind: "app", appID: appID) { return existing }
        let key = SymmetricKey(size: .bits256)
        let b64 = key.withUnsafeBytes { Data($0).base64EncodedString() }
        try saveSyncKey(keyID: "app_key_\(appID)", kind: "app", appID: appID, payloadJSON: b64)
        return b64
    }

    // MARK: 同步载荷加密 / 解密

    /// 用某 App 密钥加密同步载荷（包/行数据 canonicalData）→ E2EE envelope。
    /// 密钥缺失时自动生成（属主引导：加密即建钥，对端经 K8「拉包状态/密钥」取同钥）。
    public func encryptSyncPayload(_ data: Data, for appID: String) throws -> [String: Any] {
        let payload = try syncAppKey(appID: appID)
        guard let keyData = Data(base64Encoded: payload) else {
            throw BaseError.internal("E2EE 密钥载荷非法（base64 解码失败）")
        }
        let box = try AES.GCM.seal(data, using: SymmetricKey(data: keyData))
        return [
            "algorithm": "AES-256-GCM",
            "nonce": box.nonce.withUnsafeBytes { Data($0).base64EncodedString() },
            "ciphertext": box.ciphertext.base64EncodedString(),
            "tag": box.tag.base64EncodedString(),
            "createdAt": BaseTime.isoNow(),
        ]
    }

    /// 解密同步载荷（envelope → 原始 Data）。鉴权失败（密钥不符/篡改）抛错。
    public func decryptSyncPayload(_ envelope: [String: Any], for appID: String) throws -> Data {
        guard (envelope["algorithm"] as? String) == "AES-256-GCM" else {
            throw BaseError(code: .validationFailed, message: "不支持的算法", hint: "E2EE envelope 仅支持 AES-256-GCM")
        }
        guard let nonceB64 = envelope["nonce"] as? String,
              let ctB64 = envelope["ciphertext"] as? String,
              let tagB64 = envelope["tag"] as? String,
              let nonceData = Data(base64Encoded: nonceB64),
              let ct = Data(base64Encoded: ctB64),
              let tag = Data(base64Encoded: tagB64) else {
            throw BaseError(code: .validationFailed, message: "E2EE envelope 字段缺失或 base64 非法", hint: "")
        }
        let key = try symKey(kind: "app", appID: appID)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonceData), ciphertext: ct, tag: tag)
        return try AES.GCM.open(box, using: key)
    }

    // MARK: 私有

    private func symKey(kind: String, appID: String) throws -> SymmetricKey {
        let payload = try syncKeyPayload(kind: kind, appID: appID)
        guard let payload, let data = Data(base64Encoded: payload) else {
            throw BaseError.notFound("E2EE 密钥缺失（kind=\(kind) appID=\(appID)）")
        }
        return SymmetricKey(data: data)
    }
}
