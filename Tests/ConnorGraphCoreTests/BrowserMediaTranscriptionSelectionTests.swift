import Foundation
import Testing
import ConnorGraphCore

@Suite("Browser Media Transcription Selection Tests")
struct BrowserMediaTranscriptionSelectionTests {
    @Test func snapshotBuildsStableSourceOptionsForElementsAndOpenGraphMedia() {
        let snapshot = BrowserMediaSourceSnapshot(
            pageURLString: "https://example.com/watch",
            pageTitle: "Demo",
            mediaElements: [
                BrowserDetectedMediaElement(id: "video-0", kind: "video", sourceURLString: "https://cdn.example.com/video.mp4", durationSeconds: 123, isPaused: false, readyState: 4),
                BrowserDetectedMediaElement(id: "audio-0", kind: "audio", sourceURLString: "https://cdn.example.com/audio.m4a")
            ],
            openGraphMedia: [
                BrowserDetectedMediaCandidate(id: "og-video", sourceURLString: "https://example.com/og.mp4", type: "video")
            ]
        )

        let options = snapshot.transcriptionSourceOptions

        #expect(options.map(\.id) == ["media-element:video-0", "media-element:audio-0", "open-graph:og-video"])
        #expect(options[0].kind == .mediaElement)
        #expect(options[0].mediaKind == "video")
        #expect(options[0].durationSeconds == 123)
        #expect(options[2].kind == .openGraph)
        #expect(options[2].sourceURLString == "https://example.com/og.mp4")
    }

    @Test func selectionFiltersSnapshotToSelectedSources() {
        let snapshot = BrowserMediaSourceSnapshot(
            pageURLString: "https://example.com/watch",
            mediaElements: [
                BrowserDetectedMediaElement(id: "video-0", kind: "video", sourceURLString: "https://cdn.example.com/video.mp4"),
                BrowserDetectedMediaElement(id: "audio-0", kind: "audio", sourceURLString: "https://cdn.example.com/audio.m4a")
            ],
            openGraphMedia: [
                BrowserDetectedMediaCandidate(id: "og-video", sourceURLString: "https://example.com/og.mp4", type: "video")
            ]
        )
        let selection = BrowserMediaTranscriptionSelection(
            snapshot: snapshot,
            selectedSourceIDs: ["media-element:audio-0", "open-graph:og-video"],
            mode: .transcribeAndSummarize
        )

        let selected = selection.selectedSnapshot

        #expect(selected.mediaElements.map(\.id) == ["audio-0"])
        #expect(selected.openGraphMedia.map(\.id) == ["og-video"])
        #expect(selected.hasDetectedMedia)
    }

    @Test func defaultAllSourcesSelectsEveryDetectedSource() {
        let snapshot = BrowserMediaSourceSnapshot(
            pageURLString: "https://example.com/watch",
            mediaElements: [BrowserDetectedMediaElement(id: "video-0", kind: "video")],
            openGraphMedia: [BrowserDetectedMediaCandidate(id: "og-video", sourceURLString: "https://example.com/og.mp4")]
        )

        let selection = BrowserMediaTranscriptionSelection.defaultAllSources(from: snapshot)

        #expect(selection.selectedSourceIDs == ["media-element:video-0", "open-graph:og-video"])
        #expect(selection.mode == .transcribeSummarizeAndChapters)
        #expect(selection.options.shouldGenerateSummary)
        #expect(selection.options.shouldGenerateChapters)
    }

    @Test func modesMapToExpectedRequestOptions() {
        let transcribeOnly = BrowserMediaTranscriptionOptions.defaults(for: .transcribeOnly).mediaTranscriptionRequest()
        let summarize = BrowserMediaTranscriptionOptions.defaults(for: .transcribeAndSummarize).mediaTranscriptionRequest()
        let chapters = BrowserMediaTranscriptionOptions.defaults(for: .transcribeSummarizeAndChapters).mediaTranscriptionRequest()

        #expect(transcribeOnly.shouldGenerateChapters == false)
        #expect(transcribeOnly.outputPurpose == .discussion)
        #expect(summarize.shouldGenerateChapters == false)
        #expect(summarize.outputPurpose == .summary)
        #expect(chapters.shouldGenerateChapters == true)
        #expect(chapters.outputPurpose == .summary)
    }
}
