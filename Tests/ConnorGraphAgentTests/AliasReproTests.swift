import XCTest
@testable import ConnorGraphAgent

/// present_image 参数别名回归：canonical "altText" 曾被误判为别名 "alt_text" 的变体而删除，
/// 导致报错 "Invalid arguments: $.altText is required"（2026-09 微信截图流程复现）。
final class ToolArgumentAliasTests: XCTestCase {
    private var aliases: [String: [String]] {
        [
            "source": ["imageURL", "imageUrl", "image_url", "url"],
            "altText": ["alt", "alt_text"],
        ]
    }

    func testCanonicalCamelCaseArgumentsSurviveNormalization() throws {
        let args = try AgentToolArguments(json: #"{"altText":"微信窗口截图","source":"/tmp/a.png"}"#)
        let normalized = args.normalizingAliases(aliases)
        XCTAssertEqual(normalized.string("altText"), "微信窗口截图")
        XCTAssertEqual(normalized.string("source"), "/tmp/a.png")
    }

    func testGenuineAliasesStillMapToCanonicalKeys() throws {
        let args = try AgentToolArguments(json: #"{"alt":"说明","url":"https://example.com/a.png"}"#)
        let normalized = args.normalizingAliases(aliases)
        XCTAssertEqual(normalized.string("altText"), "说明")
        XCTAssertEqual(normalized.string("source"), "https://example.com/a.png")
        XCTAssertNil(normalized.string("alt"))
        XCTAssertNil(normalized.string("url"))
    }

    func testCaseVariantMapsToCanonicalWhenCanonicalMissing() throws {
        let args = try AgentToolArguments(json: #"{"AltText":"说明","source":"/tmp/a.png"}"#)
        let normalized = args.normalizingAliases(aliases)
        XCTAssertEqual(normalized.string("altText"), "说明")
        XCTAssertNil(normalized.string("AltText"))
    }

    func testSnakeCaseAliasMapsToCanonicalForImageSearchStyleAliases() throws {
        let args = try AgentToolArguments(json: #"{"max_results":4,"license_filter":"commercial"}"#)
        let normalized = args.normalizingAliases([
            "maxResults": ["max_results"],
            "licenseFilter": ["license_filter"],
        ])
        XCTAssertEqual(normalized.int("maxResults"), 4)
        XCTAssertEqual(normalized.string("licenseFilter"), "commercial")
    }

    func testSchemaLayerResolvesCasingAndUnderscoreVariantsOfCanonicalKey() throws {
        // canonical 缺失时，"AltText"/"alt_text" 变体由 schema 层解析到 altText
        let schema = AgentToolInputSchema.closedObject(properties: [
            "source": .string(description: "image source"),
            "altText": .string(description: "alt text"),
        ], required: ["source", "altText"])

        for variant in ["AltText", "alt_text", "altText"] {
            let value = schema.normalizingLegacyPropertyAliases(.object([
                "source": .string("/tmp/a.png"),
                variant: .string("说明"),
            ]))
            guard case .object(let normalized) = value else { return XCTFail("not an object") }
            XCTAssertEqual(normalized["altText"], .string("说明"), variant)
            let issues = schema.argumentValidationIssues(value)
            XCTAssertTrue(issues.isEmpty, "\(variant): \(issues)")
        }
    }
}
