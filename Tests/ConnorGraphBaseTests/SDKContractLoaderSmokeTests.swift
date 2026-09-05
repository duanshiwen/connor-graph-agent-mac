import XCTest
@testable import ConnorGraphBase

/// 加载器冒烟测试：三端加载同一份契约 JSON 必须成功（M0-4 DoD）。
/// 契约内容断言见 ContractSnapshotTests（M0-6）。
final class SDKContractLoaderSmokeTests: XCTestCase {

    func testLoadsBothContractFiles() throws {
        for file in SDKContractLoader.ContractFile.allCases {
            let data = try SDKContractLoader.loadData(file)
            XCTAssertFalse(data.isEmpty, "\(file.fileName) 应为非空")
            let dict = try SDKContractLoader.load(file)
            XCTAssertFalse(dict.isEmpty, "\(file.fileName) 应解析为 JSON 对象")
        }
    }

    func testGuideContractTextReturnsSDKJSON() throws {
        let text = try SDKContractLoader.guideContractText()
        XCTAssertTrue(text.contains("\"contractId\": \"base.sdk.v1\""), "base.guide 应返回 base.sdk.v1 契约全文")
        XCTAssertTrue(text.contains("\"tools\""), "契约应含 tools 工具目录")
    }
}
