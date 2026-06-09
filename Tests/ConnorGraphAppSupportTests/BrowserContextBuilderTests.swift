import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAppSupport

@Suite("BrowserContextBuilderTests")
struct BrowserContextBuilderTests {
    @Test func textSelectionPromptIncludesPageMetadataSelectedTextPageBodyAndQuestion() throws {
        let selection = BrowserSelectionContext(
            page: BrowserPageContext(
                url: "https://example.com/article",
                title: "Example Article",
                text: "This is the full readable article body. It contains surrounding context."
            ),
            selectedText: "Important selected paragraph."
        )

        let prompt = BrowserLLMContextBuilder().makePrompt(selection: selection, question: "What does this imply?")

        #expect(prompt.contains("Example Article"))
        #expect(prompt.contains("https://example.com/article"))
        #expect(prompt.contains("Important selected paragraph."))
        #expect(prompt.contains("This is the full readable article body."))
        #expect(prompt.contains("What does this imply?"))
    }

    @Test func imageSelectionPromptIncludesImageMetadataAndVisionFallback() throws {
        let selection = BrowserSelectionContext(
            page: BrowserPageContext(url: "https://example.com", title: "Image Page", text: "Page body near the image."),
            selectedText: "",
            image: BrowserSelectedImageContext(url: "https://example.com/image.png", alt: "Architecture diagram")
        )

        let prompt = BrowserLLMContextBuilder().makePrompt(selection: selection, question: "Explain this image.")

        #expect(selection.hasSelectionContext)
        #expect(prompt.contains("https://example.com/image.png"))
        #expect(prompt.contains("Architecture diagram"))
        #expect(prompt.contains("当前模型接口暂未启用 vision"))
        #expect(prompt.contains("Page body near the image."))
    }

    @Test func imageOnlySelectionIsValidContext() throws {
        let selection = BrowserSelectionContext(
            page: BrowserPageContext(url: "https://example.com", title: "Image Page"),
            selectedText: "   ",
            image: BrowserSelectedImageContext(url: "https://example.com/image.png", alt: nil)
        )

        #expect(selection.hasSelectionContext)
    }

    @Test func episodeDraftUsesWebPageSourceAndIncludesSelectionAndImageAndBody() throws {
        let selection = BrowserSelectionContext(
            page: BrowserPageContext(
                url: "https://example.com/article",
                title: "Example Article",
                text: "Full page body for evidence."
            ),
            selectedText: "Selected evidence.",
            image: BrowserSelectedImageContext(url: "https://example.com/image.png", alt: "Evidence image")
        )

        let draft = BrowserGraphEvidenceBuilder().makeEpisodeDraft(selection: selection, groupID: "default", sessionID: "session-1")

        #expect(draft.episode.sourceType == .webPage)
        #expect(draft.episode.sourceID == "https://example.com/article")
        #expect(draft.episode.name == "Example Article")
        #expect(draft.episode.sessionID == "session-1")
        #expect(draft.episode.content.contains("Selected evidence."))
        #expect(draft.episode.content.contains("https://example.com/image.png"))
        #expect(draft.episode.content.contains("Full page body for evidence."))
        #expect(draft.episode.metadata["origin"] == "embedded_browser")
    }
}
