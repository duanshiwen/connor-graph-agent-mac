import XCTest
@testable import ConnorGraphCore

final class ForwardedChatBundleTests: XCTestCase {
    func testRoundTripPreservesStructuredTranscriptAndReadableFallback() throws {
        let bundle = ForwardedChatBundle(id: "bundle-1", title: "群聊的聊天记录", sourceTitle: "周末计划", caption: "给你看看", items: [
            ForwardedChatItem(id: "m1", senderName: "Tyler", createdAt: 1, kind: "image", text: ""),
            ForwardedChatItem(id: "m2", senderName: "小土豆", createdAt: 2, text: "拿回来了")
        ])
        let encoded = try ForwardedChatBundleCodec.encode(bundle)
        XCTAssertEqual(ForwardedChatBundleCodec.decode(encoded), bundle)
        XCTAssertTrue(encoded.contains("Tyler：[图片]"))
        XCTAssertNil(ForwardedChatBundleCodec.decode("普通消息"))
    }

    func testModelEncodingKeepsCardAndExposesEveryMessageAndCaption() throws {
        let bundle = ForwardedChatBundle(
            id: "bundle-model",
            title: "测试聊天记录",
            sourceTitle: "测试群聊",
            caption: "请分析主要诉求",
            items: (1...6).map { index in
                ForwardedChatItem(
                    id: "m\(index)",
                    senderName: "成员\(index)",
                    createdAt: 1_754_041_740_000 + Int64(index * 1_000),
                    text: "消息\(index)"
                )
            }
        )

        let encoded = try ForwardedChatBundleCodec.encodeForModel(bundle)

        XCTAssertEqual(ForwardedChatBundleCodec.decode(encoded), bundle)
        XCTAssertTrue(encoded.contains("完整聊天记录（供模型阅读，时间为 UTC）"))
        XCTAssertTrue(encoded.contains("[2025-08-01T09:49:06.000Z] 成员6：消息6"))
        XCTAssertTrue(encoded.contains("用户对这段记录的留言或要求：请分析主要诉求"))
    }
    func testModelEncodingDoesNotTruncateLongTextToCardPreview() throws {
        let fullText = String(repeating: "需要完整保留的上下文。", count: 30) + "最后的关键要求"
        let bundle = ForwardedChatBundle(title: "完整记录", sourceTitle: "测试", items: [
            ForwardedChatItem(id: "long", senderName: "读者", createdAt: 1, text: fullText),
            ForwardedChatItem(id: "media", senderName: "读者", createdAt: 2, kind: "image", text: "", mediaUrl: "https://example.invalid/image.png")
        ])
        let encoded = try ForwardedChatBundleCodec.encodeForModel(bundle)
        XCTAssertTrue(encoded.contains(fullText))
        XCTAssertTrue(encoded.contains("https://example.invalid/image.png"))
        XCTAssertEqual(ForwardedChatBundleCodec.decode(encoded), bundle)
    }

}
