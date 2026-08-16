import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("Note inline media insertion")
struct NoteInlineMediaInsertionTests {
    @Test func insertsAtCursorPosition() {
        let result = NoteInlineMediaInsertion.insert("![a](file:///x.png)", at: 2, into: "你好世界！")
        #expect(result == "你好![a](file:///x.png)\n\n世界！")
    }

    @Test func appendsWhenNoCursor() {
        let result = NoteInlineMediaInsertion.insert("![a](file:///x.png)", at: nil, into: "你好")
        #expect(result == "你好![a](file:///x.png)\n\n")
    }

    @Test func clampsOutOfRangeCursor() {
        let result = NoteInlineMediaInsertion.insert("img", at: 99, into: "abc")
        #expect(result == "abcimg\n\n")
    }
}
