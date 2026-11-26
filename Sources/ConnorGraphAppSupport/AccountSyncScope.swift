import Foundation
import CryptoKit

/// Local checkpoints and app ownership include the configured server; the existing wire KDF is unchanged.
public enum AccountSyncScope {
    public static func key(server:String,userID:String)->String {
        var normalized = server.trimmingCharacters(in:.whitespacesAndNewlines)
        while normalized.hasSuffix("/"){normalized.removeLast()}
        if normalized.hasSuffix("/api/v1"){normalized = String(normalized.dropLast(7))}
        while normalized.hasSuffix("/"){normalized.removeLast()}
        return "acct_"+SHA256.hash(data:Data((normalized+"\0"+userID).utf8)).map{String(format:"%02x",$0)}.joined()
    }
}
