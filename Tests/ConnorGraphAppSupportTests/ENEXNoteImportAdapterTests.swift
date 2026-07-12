import Foundation
import CryptoKit
import Testing
import ConnorGraphCore
@testable import ConnorGraphAppSupport

@Suite("ENEX streaming import adapter")
struct ENEXNoteImportAdapterTests {
    @Test("Streams notes, converts ENML, and maps resources")
    func streamsNotesAndResources() async throws { let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }; let resource = Data("image".utf8); let hash = Insecure.MD5.hash(data: resource).map { String(format: "%02x", $0) }.joined(); let enex = """
        <?xml version="1.0" encoding="UTF-8"?><en-export><note><title>中文 日本語 Русский</title><content><![CDATA[<en-note><div>Hello &amp; world</div><en-todo checked="true"/><en-media hash="\(hash)" type="image/png"/></en-note>]]></content><created>20260712T120000Z</created><tag>知识</tag><guid>guid-1</guid><resource><data encoding="base64">\(resource.base64EncodedString())</data><mime>image/png</mime><resource-attributes><file-name>image.png</file-name></resource-attributes></resource></note><note><title>Second</title><content><![CDATA[<en-note>Body</en-note>]]></content><guid>guid-2</guid></note></en-export>
        """; let file = root.appendingPathComponent("Notebook.enex"); try enex.write(to: file, atomically: true, encoding: .utf8); var notes: [ImportedNote] = []; for try await note in ENEXNoteImportAdapter().scan(.init(sourceID: "e", sourceURL: file, kind: .evernoteENEX, options: .init())) { notes.append(note) }; #expect(notes.count == 2); #expect(notes[0].title == "中文 日本語 Русский"); #expect(notes[0].markdownContent.contains("- [x]")); #expect(notes[0].attachments.first?.displayName == "image.png"); #expect(notes[0].tags == ["知识"]); #expect(notes[0].externalID == "guid-1"); #expect(notes[1].markdownContent.contains("Body")) }
}
