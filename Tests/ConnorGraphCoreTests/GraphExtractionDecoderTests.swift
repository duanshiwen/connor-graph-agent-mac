import Foundation
import Testing
import ConnorGraphCore

private let validExtractionJSON = """
{
  "entities": [
    {
      "localID": "shiwen",
      "name": "诗闻",
      "entityKind": "person_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "",
      "confidence": 0.9,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    },
    {
      "localID": "tea",
      "name": "tea",
      "entityKind": "life_object",
      "scope": "personal",
      "canonicalClassID": null,
      "aliases": [],
      "summary": "",
      "confidence": 0.85,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "statements": [
    {
      "explicitID": null,
      "subjectLocalID": "shiwen",
      "predicate": "PREFERS",
      "objectLocalID": "tea",
      "statementText": "诗闻 prefers tea",
      "confidence": 0.88,
      "validAt": null,
      "referenceTime": null,
      "evidenceSpanIDs": ["span-1"],
      "metadata": {}
    }
  ],
  "evidenceSpans": [
    {
      "id": "span-1",
      "text": "诗闻 prefers tea.",
      "startOffset": null,
      "endOffset": null
    }
  ],
  "warnings": [],
  "confidence": 0.87,
  "metadata": {}
}
"""

@Test func extractionDecoderDecodesPlainJSON() throws {
    let result = try GraphExtractionDecoder().decode(validExtractionJSON)

    #expect(result.output.entities.count == 2)
    #expect(result.output.statements.count == 1)
    #expect(result.normalizedJSON.contains("\"entities\""))
}

@Test func extractionDecoderStripsMarkdownJSONFence() throws {
    let fenced = """
    ```json
    \(validExtractionJSON)
    ```
    """

    let result = try GraphExtractionDecoder().decode(fenced)

    #expect(result.output.statements.count == 1)
    #expect(result.warnings.contains("stripped_markdown_code_fence"))
}

@Test func extractionDecoderRejectsEmptyResponse() throws {
    #expect(throws: GraphExtractionDecodingError.emptyResponse) {
        try GraphExtractionDecoder().decode("   \n  ")
    }
}

@Test func extractionDecoderRejectsMalformedJSON() throws {
    #expect(throws: GraphExtractionDecodingError.self) {
        try GraphExtractionDecoder().decode("{ not-json")
    }
}

@Test func extractionDecoderRejectsSchemaViolation() throws {
    let invalid = """
    {
      "entities": [],
      "statements": [
        {
          "explicitID": null,
          "subjectLocalID": "missing",
          "predicate": "PREFERS",
          "objectLocalID": "tea",
          "statementText": "missing prefers tea",
          "confidence": 0.88,
          "validAt": null,
          "referenceTime": null,
          "evidenceSpanIDs": ["span-1"],
          "metadata": {}
        }
      ],
      "evidenceSpans": [{ "id": "span-1", "text": "missing prefers tea", "startOffset": null, "endOffset": null }],
      "warnings": [],
      "confidence": null,
      "metadata": {}
    }
    """

    #expect(throws: GraphExtractionDecodingError.self) {
        try GraphExtractionDecoder().decode(invalid)
    }
}
