import Foundation
import Testing
import ConnorGraphAppSupport

@Suite("Mail Connection Test Service Tests")
struct MailConnectionTestServiceTests {
    @Test func connectionTestSummaryRedactsCredentialLikeSecrets() {
        let result = MailConnectionTestResult(
            imapConnect: .success("已连接到 imap.example.com:993"),
            imapAuth: .failure("认证失败: password=super-secret-app-password", error: nil),
            smtpConnect: .failure("SMTP AUTH failed for token refresh_token_123", error: nil),
            smtpAuth: .skipped("连接失败，跳过认证测试")
        )

        let summary = result.summary

        #expect(!summary.contains("super-secret-app-password"))
        #expect(!summary.contains("refresh_token_123"))
        #expect(summary.contains("[redacted]"))
        #expect(summary.contains("IMAP 认证"))
        #expect(summary.contains("SMTP 连接"))
    }
}
