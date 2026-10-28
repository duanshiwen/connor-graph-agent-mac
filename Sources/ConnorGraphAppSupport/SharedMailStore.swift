import Foundation
import CryptoKit

public struct SharedMailAttachment: Codable, Sendable, Equatable, Identifiable {
 public var id: String; public var fileName: String; public var mimeType: String; public var size: Int64; public var contentId: String; public var isInline: Bool
}
public struct SharedMailMessage: Codable, Sendable, Equatable, Identifiable {
 public var schemaVersion = 1
 public var id = ""; public var mailboxAddress = ""; public var mailboxName = ""; public var folder = "INBOX"; public var uidValidity = ""; public var uid = ""
 public var messageId = ""; public var subject = ""; public var from = ""; public var to: [String] = []; public var cc: [String] = []; public var sentAt: Int64 = 0; public var snippet = ""
 public var bodyText = ""; public var bodyAvailable = false; public var bodyTruncated = false; public var attachments: [SharedMailAttachment] = []; public var isRead = false; public var updatedAt: Int64 = 0
 public init() {}
}
/// Content is kept separately from local login accounts. No attachment bytes or vault identifiers.
public struct SharedMailStore: Sendable {
 public let directory: URL
 private static let gate = NSRecursiveLock()
 public init(configDirectory: URL) { directory = configDirectory.appendingPathComponent("shared-mail", isDirectory: true) }
 public static func digest(_ value: String) -> String { SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined() }
 public static func recordID(address: String, folder: String, validity: String, uid: String) -> String {
  "mail_" + digest("\(address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())\0\(folder.uppercased() == "INBOX" ? "INBOX" : folder)\0\(validity)\0\(uid)")
 }
 static func wire(_ value: SharedMailMessage) throws -> ConnorJSONValue { try JSONDecoder().decode(ConnorJSONValue.self, from: JSONEncoder().encode(value)) }
 static func decode(_ payload: ConnorJSONValue) throws -> SharedMailMessage {
  let value = try JSONDecoder().decode(SharedMailMessage.self, from: JSONEncoder().encode(payload))
  guard value.schemaVersion == 1, !value.mailboxAddress.isEmpty, (UInt32(value.uid) ?? 0) > 0, (UInt32(value.uidValidity) ?? 0) > 0,
        value.id == recordID(address: value.mailboxAddress, folder: value.folder, validity: value.uidValidity, uid: value.uid), value.updatedAt >= 0, value.updatedAt <= 9_007_199_254_740_991, value.sentAt >= -9_007_199_254_740_991, value.sentAt <= 9_007_199_254_740_991,
        value.attachments.allSatisfy({ $0.size >= -1 && $0.size <= 9_007_199_254_740_991 }) else { throw SessionChunks.Failure.invalid }
  return value
 }
 static func semanticHash(_ value: ConnorJSONValue) throws -> String {
  var bytes = Data()
  func add(_ s: String) { let b = Data(s.utf8); var size = UInt32(b.count).bigEndian; withUnsafeBytes(of: &size) { bytes.append(contentsOf: $0) }; bytes.append(b) }
  func visit(_ v: ConnorJSONValue) throws { switch v {
   case .object(let o): add("o"); add(String(o.count)); for k in o.keys.sorted() { add(k); try visit(o[k]!) }
   case .array(let a): add("a"); add(String(a.count)); for v in a { try visit(v) }
   case .string(let s): add("s"); add(s)
   case .bool(let b): add("b"); add(b ? "1" : "0")
   case .number(let n): guard n.isFinite, n.rounded() == n, abs(n) < 9_007_199_254_740_992 else { throw SessionChunks.Failure.invalid }; add("n"); add(String(Int64(n)))
   case .null: add("z")
  } }
  try visit(value); return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
 }
 private static func quality(_ v: SharedMailMessage) -> Int { !v.bodyAvailable ? 0 : v.bodyTruncated ? 1 : 2 }
 private static func preserve(_ v: SharedMailMessage, _ old: SharedMailMessage) -> SharedMailMessage {
  var next = v
  if quality(v) < quality(old) || v.bodyText.isEmpty && !old.bodyText.isEmpty && old.bodyAvailable {
   next.bodyText = old.bodyText; next.bodyAvailable = old.bodyAvailable; next.bodyTruncated = old.bodyTruncated
  }
  if next.attachments.isEmpty && !old.attachments.isEmpty { next.attachments = old.attachments }
  return next
 }
 private static func contentHash(_ v: SharedMailMessage) throws -> String { var copy = v; copy.updatedAt = 0; return try semanticHash(wire(copy)) }
 public func get(_ id: String) throws -> SharedMailMessage? {
  Self.gate.lock(); defer { Self.gate.unlock() }
  guard id.count == 69, id.hasPrefix("mail_"), id.dropFirst(5).allSatisfy({ $0.isHexDigit }) else { return nil }
  let url = directory.appendingPathComponent(id + ".json"); guard FileManager.default.fileExists(atPath: url.path) else { return nil }
  return try Self.decode(JSONDecoder().decode(ConnorJSONValue.self, from: Data(contentsOf: url)))
 }
 @discardableResult public func capture(_ input: SharedMailMessage) throws -> Bool {
  Self.gate.lock(); defer { Self.gate.unlock() }
  var next = input; next.messageId = next.messageId.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "<>")); next.mailboxAddress = next.mailboxAddress.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(); if next.folder.uppercased() == "INBOX" { next.folder = "INBOX" }
  next.id = Self.recordID(address: next.mailboxAddress, folder: next.folder, validity: next.uidValidity, uid: next.uid)
  let old = try get(next.id); let observed = try Self.contentHash(next)
  let baseline = directory.appendingPathComponent(next.id + ".origin-hash")
  if old != nil, (try? String(contentsOf: baseline, encoding: .utf8)) == observed { return false }
  if let old { next = Self.preserve(next, old) }
  var changed = old == nil
  if let old { changed = try Self.contentHash(next) != Self.contentHash(old) }
  next.updatedAt = max(Int64(Date().timeIntervalSince1970 * 1_000), (old?.updatedAt ?? 0) + 1)
  if changed { changed = try apply(Self.wire(next)) }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try observed.write(to: baseline, atomically: true, encoding: .utf8)
  return changed
 }
 @discardableResult func apply(_ payload: ConnorJSONValue) throws -> Bool {
  Self.gate.lock(); defer { Self.gate.unlock() }
  var next = try Self.decode(payload)
  if let old = try get(next.id) {
   let incoming = next
   let incomingHash = try Self.contentHash(next); let oldHash = try Self.contentHash(old)
   if next.updatedAt < old.updatedAt || next.updatedAt == old.updatedAt && incomingHash <= oldHash { next = old }
   next = Self.preserve(next, Self.quality(incoming) > Self.quality(old) ? incoming : old)
   if try Self.semanticHash(Self.wire(next)) == Self.semanticHash(Self.wire(old)) { return false }
  }
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try JSONEncoder().encode(next).write(to: directory.appendingPathComponent(next.id + ".json"), options: .atomic)
  NotificationCenter.default.post(name: .connorMailCacheDidChange, object: nil)
  return true
 }
 public func all() throws -> [SharedMailMessage] {
  Self.gate.lock(); defer { Self.gate.unlock() }
  guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
  return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("mail_") }.map { try Self.decode(JSONDecoder().decode(ConnorJSONValue.self, from: Data(contentsOf: $0))) }.sorted { $0.sentAt > $1.sentAt }
 }
 public func visible() throws -> [SharedMailMessage] {
  let values = try all(); let groups = Dictionary(grouping: values) { $0.mailboxAddress + "\0" + $0.folder }
  return groups.values.flatMap { group in let latest = group.compactMap { UInt64($0.uidValidity) }.max(); return group.filter { UInt64($0.uidValidity) == latest } }.sorted { $0.sentAt > $1.sentAt }
 }
}

import ConnorGraphCore

extension SharedMailStore {
    /// Export only content already fetched by this device; configuration never enters the wire.
    func capture(from store: any MailStoreProtocol) async throws {
        let accounts = try await store.listAccounts()
        let byAccount = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var mailboxes: [MailMailboxID: MailMailbox] = [:]
        for account in accounts { for box in try await store.listMailboxes(accountID: account.id) { mailboxes[box.id] = box } }
        for id in try await store.allMessageIDs() {
            guard let detail = try await store.message(id: id), let account = byAccount[detail.summary.accountID],
                  let box = mailboxes[detail.summary.mailboxID], let validity = box.status.syncCursor?.uidValidity,
                  let uid = detail.id.rawValue.split(separator: "-").last, (UInt32(uid) ?? 0) > 0, (UInt32(validity) ?? 0) > 0,
                  let address = account.identities.first?.address.email else { continue }
            var message = SharedMailMessage()
            message.mailboxAddress = address; message.mailboxName = address; message.folder = box.path
            message.uidValidity = String(UInt32(validity)!); message.uid = String(UInt32(uid)!); message.messageId = detail.headers.messageIDHeader ?? ""
            message.subject = detail.summary.subject; message.from = detail.summary.from.email
            message.to = detail.summary.to.map(\.email); message.cc = detail.summary.cc.map(\.email)
            message.sentAt = Int64(detail.summary.date.timeIntervalSince1970 * 1_000)
            let body = detail.body?.plainText ?? detail.body?.htmlText
            message.bodyAvailable = body != nil; message.bodyTruncated = body?.wasTruncated ?? false
            message.bodyText = detail.body?.plainText?.text ?? detail.body?.htmlText?.text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression) ?? ""
            message.snippet = String(message.bodyText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).prefix(200))
            message.isRead = detail.summary.flags.isRead
            message.attachments = detail.attachments.enumerated().map { index, value in
                SharedMailAttachment(id: String(index), fileName: value.filename, mimeType: value.mimeType, size: Int64(value.byteCount), contentId: value.contentID ?? "", isInline: value.isInline)
            }
            try capture(message)
        }
    }
}
