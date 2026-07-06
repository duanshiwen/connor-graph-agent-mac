import Testing
@testable import ConnorGraphAgentMac

@Suite("Mail HTML Body Sanitizer Tests")
struct MailHTMLBodySanitizerTests {
    @Test func blocksRemoteImagesByDefaultAndReportsCount() {
        let html = """
        <p>LinkedIn 通知</p>
        <img src="https://static.licdn.com/avatar.png" alt="头像">
        """

        let result = MailHTMLBodySanitizer().prepareHTML(html, policy: MailHTMLDisplayPolicy(remoteContentMode: .block))

        #expect(result.blockedRemoteImageCount == 1)
        #expect(!result.html.contains("<img src=\"https://static.licdn.com/avatar.png\""))
        #expect(result.html.contains("data-connor-remote-src="))
        #expect(result.html.contains("<span class=\"connor-mail-remote-image-placeholder\""))
        #expect(result.html.contains("已阻止远程图片"))
    }

    @Test func allowsRemoteImagesWhenExplicitlyRequestedForMessage() {
        let html = """
        <p>LinkedIn 通知</p>
        <img src="https://static.licdn.com/avatar.png" alt="头像">
        """

        let result = MailHTMLBodySanitizer().prepareHTML(html, policy: MailHTMLDisplayPolicy(remoteContentMode: .allowForMessage))

        #expect(result.blockedRemoteImageCount == 0)
        #expect(result.html.contains("src=\"https://static.licdn.com/avatar.png\""))
        #expect(!result.html.contains("<span class=\"connor-mail-remote-image-placeholder\""))
    }

    @Test func keepsEmbeddedDataImagesWhileBlockingRemoteImages() {
        let html = """
        <p>签名</p>
        <img src="data:image/png;base64,aGVsbG8=" alt="内联图">
        <img src='http://tracker.example.com/pixel.gif' alt='tracker'>
        """

        let result = MailHTMLBodySanitizer().prepareHTML(html, policy: MailHTMLDisplayPolicy(remoteContentMode: .block))

        #expect(result.blockedRemoteImageCount == 1)
        #expect(result.html.contains("src=\"data:image/png;base64,aGVsbG8=\""))
        #expect(!result.html.contains("src='http://tracker.example.com/pixel.gif'"))
    }

    @Test func wrapsFragmentsWithMailSafeDocumentChrome() {
        let result = MailHTMLBodySanitizer().prepareHTML("<p>Hello</p>", policy: MailHTMLDisplayPolicy(remoteContentMode: .block))

        #expect(result.html.contains("<!DOCTYPE html>"))
        #expect(result.html.contains("img { max-width: 100%; height: auto; }"))
        #expect(result.html.contains("<body><p>Hello</p></body>"))
    }
}
