import Testing
@testable import ConnorGraphAppSupport

@Suite("Agent Tool Change Presentation Tests")
struct AgentToolChangePresentationTests {
    @Test func extractsUnifiedDiffFromResultJSON() throws {
        let invocation = makeInvocation(
            callID: "edit-1",
            semanticKind: .editFile,
            target: "README.md",
            resultJSON: #"{"diff":"--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-old\n+new","path":"README.md"}"#
        )

        let change = AgentToolChangePresentation(invocation: invocation)

        #expect(change?.path == "README.md")
        #expect(change?.format == .unifiedDiff)
        #expect(change?.diffText?.contains("-old") == true)
        #expect(change?.diffText?.contains("+new") == true)
    }

    @Test func buildsBeforeAfterDiffFromArgumentsJSON() throws {
        let invocation = makeInvocation(
            callID: "edit-2",
            semanticKind: .editFile,
            target: "Sources/file.swift",
            argumentsJSON: #"{"path":"Sources/file.swift","oldText":"let value = 1\n","newText":"let value = 2\n"}"#
        )

        let change = AgentToolChangePresentation(invocation: invocation)

        #expect(change?.path == "Sources/file.swift")
        #expect(change?.format == .beforeAfter)
        #expect(change?.beforeText == "let value = 1\n")
        #expect(change?.afterText == "let value = 2\n")
        #expect(change?.diffText?.contains("-let value = 1") == true)
        #expect(change?.diffText?.contains("+let value = 2") == true)
    }

    @Test func extractsUnifiedDiffFromOutputTextFallback() throws {
        let invocation = makeInvocation(
            callID: "write-1",
            semanticKind: .writeFile,
            target: "Notes.md",
            outputText: "--- a/Notes.md\n+++ b/Notes.md\n@@ -0,0 +1 @@\n+hello"
        )

        let change = AgentToolChangePresentation(invocation: invocation)

        #expect(change?.path == "Notes.md")
        #expect(change?.format == .unifiedDiff)
        #expect(change?.diffText?.contains("+hello") == true)
    }

    @Test func ignoresNonFileChangeTools() throws {
        let invocation = makeInvocation(
            callID: "bash-1",
            semanticKind: .shellCommand,
            target: nil,
            resultJSON: #"{"diff":"--- a/x\n+++ b/x"}"#
        )

        #expect(AgentToolChangePresentation(invocation: invocation) == nil)
    }

    private func makeInvocation(
        callID: String,
        semanticKind: AgentToolSemanticKind,
        target: String?,
        argumentsJSON: String? = nil,
        resultJSON: String? = nil,
        outputText: String? = nil,
        errorText: String? = nil
    ) -> AgentToolInvocationPresentation {
        AgentToolInvocationPresentation(
            id: "tool-invocation-\(callID)",
            callID: callID,
            runID: "run",
            sessionID: "session",
            toolName: semanticKind == .shellCommand ? "Bash" : "Edit",
            semanticKind: semanticKind,
            phase: .finished,
            severity: .success,
            title: "Tool finished",
            subtitle: "Finished",
            target: target,
            icon: semanticKind == .shellCommand ? "terminal" : "pencil.and.outline",
            argumentsJSON: argumentsJSON,
            resultJSON: resultJSON,
            outputText: outputText,
            errorText: errorText,
            requestedEventID: "requested",
            approvedEventID: nil,
            startedEventID: nil,
            finishedEventID: "finished",
            failedEventID: nil,
            rawEventIDs: ["requested", "finished"],
            isOutputTruncated: false,
            outputArtifactPath: nil
        )
    }
}
