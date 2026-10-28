import Foundation
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("Content-only mail synchronization")
struct MailContentSyncTests {
 private func fixture() throws -> [String:ConnorJSONValue] {
  let url=try #require(Bundle.module.url(forResource:"mail-content-v1",withExtension:"json",subdirectory:"SessionSync"))
  guard case .object(let value)=try JSONDecoder().decode(ConnorJSONValue.self,from:Data(contentsOf:url)) else {throw SessionChunks.Failure.invalid};return value
 }
 @Test func portableIdentityAndHashExcludeSecretsAndAttachmentBytes() throws {
  let f=try fixture();let payload=try #require(f["message"]);let mail=try SharedMailStore.decode(payload)
  #expect(mail.id==SharedMailStore.recordID(address:" OWNER@EXAMPLE.TEST ",folder:"inbox",validity:mail.uidValidity,uid:mail.uid))
  #expect(mail.id != SharedMailStore.recordID(address:mail.mailboxAddress,folder:"Sent",validity:mail.uidValidity,uid:mail.uid))
  #expect(mail.id != SharedMailStore.recordID(address:mail.mailboxAddress,folder:mail.folder,validity:"124",uid:mail.uid))
  #expect(f["semanticHash"] == .string(try SharedMailStore.semanticHash(payload)))
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  guard case .object(var fields)=payload else {throw SessionChunks.Failure.invalid}
  fields["password"] = .string("must-not-persist");fields["imapHost"] = .string("must-not-persist")
  if case .array(var attachments)=fields["attachments"], case .object(var a)=attachments[0] {a["data"] = .string("must-not-persist");a["localPath"] = .string("must-not-persist");attachments[0] = .object(a);fields["attachments"] = .array(attachments)}
  let store=SharedMailStore(configDirectory:root);try store.apply(.object(fields))
  let saved=try #require(store.all().first);let json=String(decoding:try JSONEncoder().encode(saved),as:UTF8.self)
  #expect(!json.contains("must-not-persist"))
 }
 @Test func twoClientsConvergeWithoutEchoAndRetainTheCompleteBody() throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let a=SharedMailStore(configDirectory:root.appendingPathComponent("a"));let b=SharedMailStore(configDirectory:root.appendingPathComponent("b"))
  let native=try SharedMailStore.decode(#require(try fixture()["message"]));var alternate=native;alternate.mailboxName="different local label"
  #expect(try a.capture(native));#expect(try b.capture(alternate))
  try a.apply(SharedMailStore.wire(#require(b.all().first)));try b.apply(SharedMailStore.wire(#require(a.all().first)))
  #expect(try a.capture(native)==false);#expect(try b.capture(alternate)==false);#expect(try a.all().count==1)
  var partial=try #require(a.all().first);partial.bodyText="";partial.bodyAvailable=false;partial.attachments=[];partial.isRead=true;partial.updatedAt+=100
  try a.apply(SharedMailStore.wire(partial));let after=try #require(a.all().first)
  #expect(after.bodyText==native.bodyText && after.isRead && after.attachments.count==1)
 }
 @Test func unicodeAndLargeChunkedBodiesRequireCompleteVerifiedParts() throws {
  let f=try fixture();let payload=try #require(f["message"]);let mail=try SharedMailStore.decode(payload)
  guard case .object(let records)=f["records"] else {throw SessionChunks.Failure.invalid};var parts:[String:ConnorJSONValue]=[:]
  #expect(throws:SessionChunks.Failure.self){try SessionChunks.resolve(id:mail.id,payload:#require(records[mail.id]),parts:&parts,mail:true)}
  for(id,value)in records where id != mail.id{#expect(try SessionChunks.resolve(id:id,payload:value,parts:&parts,mail:true)==nil)}
  #expect(try SessionChunks.resolve(id:mail.id,payload:#require(records[mail.id]),parts:&parts,mail:true)==payload)
  var large=mail;large.bodyText=String(repeating:"文",count:600_000)+"😀 complete"
  let projected=try SessionChunks.project(id:large.id,payload:SharedMailStore.wire(large),mail:true);#expect(projected.count>3);parts=[:]
  for(id,value)in projected where id != large.id{_ = try SessionChunks.resolve(id:id,payload:value,parts:&parts,mail:true)}
  let restored=try #require(SessionChunks.resolve(id:large.id,payload:#require(projected[large.id]),parts:&parts,mail:true))
  #expect(try SharedMailStore.decode(restored).bodyText==large.bodyText)
 }
}

extension MailContentSyncTests {
 @Test func integralWireNumbersStayJSONIntegers() throws {
  let value=ConnorJSONValue.object(["sentAt":.number(1_700_000_000_000),"schemaVersion":.number(1),"score":.number(0.5)])
  let encoded=String(decoding:try JSONEncoder().encode(value),as:UTF8.self)
  #expect(encoded.contains("\"sentAt\":1700000000000"))
  #expect(!encoded.contains("1700000000000.0"))
  #expect(encoded.contains("\"schemaVersion\":1"))
  #expect(encoded.contains("\"score\":0.5"))
 }
}
