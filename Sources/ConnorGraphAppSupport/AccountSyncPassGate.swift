import Foundation

/// Coordinators are recreated by the application. Serialize checkpoint edits across instances and UI choices.
actor AccountSyncPassGate {
    static let shared = AccountSyncPassGate()
    private var busy = false
    private var waiting: [CheckedContinuation<Void,Never>] = []
    func acquire() async {
        if !busy {busy = true;return}
        await withCheckedContinuation {waiting.append($0)}
    }
    func release() {
        if waiting.isEmpty {busy = false}
        else {waiting.removeFirst().resume()}
    }
}

public struct BaseAccountConflict: Sendable, Identifiable {
    public let accountID:String
    public let appID:String
    public let remoteVersion:Int64
    public let remoteDeleted:Bool
    public let localFingerprint:String?
    public var id:String {appID}
}
