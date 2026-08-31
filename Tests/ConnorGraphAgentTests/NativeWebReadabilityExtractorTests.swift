import Foundation
import Testing
@testable import ConnorGraphAgent

struct NativeWebReadabilityExtractorTests {

    @Test func articlePageExtractsBodyAndDropsNoise() throws {
        let html = """
        <html><head><title>Real Title</title></head><body>
        <nav><a href="/">Home</a><a href="/about">About</a></nav>
        <header>Header Banner</header>
        <article><h1>Real Title</h1><p>body paragraph one</p><p>body paragraph two</p></article>
        <footer>Footer links</footer>
        <aside>Related posts</aside>
        </body></html>
        """
        let markdown = NativeWebTextExtractor.markdown(from: html, baseURL: URL(string: "https://example.com")!)
        #expect(markdown.contains("body paragraph"))
        #expect(markdown.contains("Real Title"))
        #expect(!markdown.contains("Home"))
        #expect(!markdown.contains("Footer links"))
        #expect(!markdown.contains("Related posts"))
    }

    @Test func nonArticlePageFallsBackToCleanedBody() throws {
        let html = """
        <html><head><title>T</title></head><body>
        <main><p>Hello page content</p></main>
        </body></html>
        """
        let markdown = NativeWebTextExtractor.markdown(from: html, baseURL: URL(string: "https://example.com")!)
        #expect(markdown.contains("Hello page content"))
    }
}
