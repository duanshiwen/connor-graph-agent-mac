import Foundation

public enum BaseLocalChange {
    public static let notification = Notification.Name("ConnorBaseLocalDataDidChange")
    public static func post() {NotificationCenter.default.post(name:notification,object:nil)}
    /// Ignore initialization, audit and transport bookkeeping; user tables may themselves start with base_.
    static func isUserWrite(_ sql:String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern:"^\\s*(?:INSERT(?: OR [A-Z]+)? INTO|UPDATE|DELETE FROM)\\s+\"?([a-zA-Z0-9_]+)",options:[.caseInsensitive]),let match = regex.firstMatch(in:sql,range:NSRange(sql.startIndex...,in:sql)),let range = Range(match.range(at:1),in:sql) else {return false}
        return !["base_pkg_state","schema_migrations","base_schema_cache","base_idempotency","base_record_seq","base_audit_log","base_sync_marker","sqlite_sequence"].contains(String(sql[range]).lowercased())
    }
}
