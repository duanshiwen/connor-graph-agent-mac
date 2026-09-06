import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K3：名字解析与子库边界（D24：v1 只解析当前子库表名）。
final class BaseNameResolverTests: XCTestCase {

    func testResolvesCurrentLibraryTable() throws {
        XCTAssertEqual(try BaseNameResolver.resolveTable("expenses", in: "acct"), "expenses")
        XCTAssertEqual(try BaseNameResolver.resolveTable("monthly_report_2", in: "acct"), "monthly_report_2")
    }

    func testRejectsCrossLibraryReference() {
        // 全限定跨库表引用（imports 形态随跨库只读导入暂缓，D24）→ NOT_FOUND 承载。
        XCTAssertThrowsError(try BaseNameResolver.resolveTable("subs.subscriptions", in: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "NOT_FOUND")
            XCTAssertEqual(e.message, BaseNameResolver.scopeViolationMessage)
        }
    }

    func testRejectsInvalidTableName() {
        XCTAssertThrowsError(try BaseNameResolver.resolveTable("Bad-Table!", in: "acct")) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
        }
        XCTAssertThrowsError(try BaseNameResolver.resolveTable("", in: "acct"))
    }

    func testResolveFieldValidatesAgainstSchema() throws {
        let fields = ["amount": "number", "paid": "boolean"]
        XCTAssertEqual(try BaseNameResolver.resolveField("amount", in: "expenses", fields: fields), "number")
        XCTAssertThrowsError(try BaseNameResolver.resolveField("ghost", in: "expenses", fields: fields)) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "NOT_FOUND")
        }
        XCTAssertThrowsError(try BaseNameResolver.resolveField("bad field", in: "expenses", fields: fields)) { error in
            let e = error as! BaseError
            XCTAssertEqual(e.code, "VALIDATION_FAILED")
        }
    }
}
