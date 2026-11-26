import Foundation
import CryptoKit

public enum BaseAccountTransport {
    public static let collection = "base_apps"
    public static let inlineBytes = 192 * 1024, partBytes = 256 * 1024, maxParts = 512
    public enum Failure: Error { case invalid, missingParts }
    private static func hash(_ data:Data) -> String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    private static func partID(_ app:String,_ digest:String,_ index:Int) -> String {"bsp_"+hash(Data("\(app)\0\(digest)\0\(index)".utf8)).prefix(48)}
    public static func isPartID(_ id:String) -> Bool {id.count == 52 && id.hasPrefix("bsp_") && id.dropFirst(4).allSatisfy{$0.isHexDigit}}
    public static func partIDs(_ data:Data) throws -> [String] {
        guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any] else {throw Failure.invalid}
        return (root["_connorBaseChunks"] as? [String:Any])?["parts"] as? [String] ?? []
    }
    public static func project(appID:String,snapshot:Data) throws -> [String:Data] {
        guard let root = try JSONSerialization.jsonObject(with:snapshot) as? [String:Any],root["appID"] as? String == appID else {throw Failure.invalid}
        if snapshot.count <= inlineBytes {return [appID:snapshot]}
        let count = (snapshot.count+partBytes-1)/partBytes
        guard count <= maxParts else {throw Failure.invalid}
        let digest = hash(snapshot);var result:[String:Data] = [:];var ids:[String] = []
        for index in 0..<count {
            let id = partID(appID,digest,index);ids.append(id)
            result[id] = try JSONSerialization.data(withJSONObject:["_connorBaseChunk":["v":1,"appID":appID,"sha256":digest,"index":index,"data":snapshot.subdata(in:index*partBytes..<min(snapshot.count,(index+1)*partBytes)).base64EncodedString()]],options:[.sortedKeys,.withoutEscapingSlashes])
        }
        result[appID] = try JSONSerialization.data(withJSONObject:["appID":appID,"_connorBaseChunks":["v":1,"sha256":digest,"byteLength":snapshot.count,"parts":ids]],options:[.sortedKeys,.withoutEscapingSlashes])
        return result
    }
    public static func resolve(id:String,payload:Data,cache:inout [String:Data]) throws -> Data? {
        guard let root = try JSONSerialization.jsonObject(with:payload) as? [String:Any] else {throw Failure.invalid}
        if let part = root["_connorBaseChunk"] as? [String:Any] {
            guard let app = part["appID"] as? String,BaseSchemaValidator.isValidAppID(app),let digest = part["sha256"] as? String,digest.count == 64,digest.allSatisfy({$0.isHexDigit}),let index = part["index"] as? Int,index>=0,index<maxParts,part["v"] as? Int == 1,
                  let encoded = part["data"] as? String,let bytes = Data(base64Encoded:encoded),!bytes.isEmpty,bytes.count<=partBytes,partID(app,digest,index)==id else {throw Failure.invalid}
            cache[id] = payload;return nil
        }
        guard root["appID"] as? String == id,BaseSchemaValidator.isValidAppID(id) else {throw Failure.invalid}
        guard let manifest = root["_connorBaseChunks"] as? [String:Any] else {return payload}
        guard manifest["v"] as? Int == 1,let digest = manifest["sha256"] as? String,let length = manifest["byteLength"] as? Int,length>inlineBytes,length<=partBytes*maxParts,let parts = manifest["parts"] as? [String],!parts.isEmpty,parts.count<=maxParts else {throw Failure.invalid}
        var bytes = Data()
        for (index,idPart) in parts.enumerated() {
            guard idPart==partID(id,digest,index) else {throw Failure.invalid}
            guard let saved = cache[idPart] else {throw Failure.missingParts}
            guard let obj = try JSONSerialization.jsonObject(with:saved) as? [String:Any],let part = obj["_connorBaseChunk"] as? [String:Any],part["appID"] as? String == id,part["sha256"] as? String == digest,part["index"] as? Int == index,let encoded = part["data"] as? String,let value = Data(base64Encoded:encoded) else {throw Failure.invalid}
            bytes.append(value);guard bytes.count<=length else {throw Failure.invalid}
        }
        guard bytes.count == length,hash(bytes) == digest,let snapshot = try JSONSerialization.jsonObject(with:bytes) as? [String:Any],snapshot["appID"] as? String == id else {throw Failure.invalid}
        return bytes
    }
}
