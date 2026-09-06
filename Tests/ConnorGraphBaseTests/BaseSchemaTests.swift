import XCTest
import Foundation
@testable import ConnorGraphBase

/// M1-K1：schema 模型与校验器（对齐 golden 01–05 的 message/hint）。
final class BaseSchemaTests: XCTestCase {

    // MARK: 字段类型

    func testFieldTypeRawValuesMatchContract() {
        let raw = BaseFieldType.allRawValues
        XCTAssertEqual(raw, ["text", "number", "boolean", "date", "enum", "relation", "asset"])
        XCTAssertEqual(BaseFieldType(raw: "blob"), nil)
        XCTAssertEqual(BaseFieldType(raw: "text"), .text)
        XCTAssertEqual(BaseFieldType.enum.rawValue, "enum")
    }

    // MARK: 名称

    func testValidNames() {
        XCTAssertTrue(BaseSchemaValidator.isValidName("expenses"))
        XCTAssertTrue(BaseSchemaValidator.isValidName("a"))
        XCTAssertTrue(BaseSchemaValidator.isValidName("monthly_report_2"))
        XCTAssertFalse(BaseSchemaValidator.isValidName("Bad-Table!"))
        XCTAssertFalse(BaseSchemaValidator.isValidName("1abc"))
        XCTAssertFalse(BaseSchemaValidator.isValidName(""))
        XCTAssertFalse(BaseSchemaValidator.isValidName("aBc"))
    }

    func testAppIDPattern() {
        XCTAssertTrue(BaseSchemaValidator.isValidAppID("acct"))
        XCTAssertTrue(BaseSchemaValidator.isValidAppID("book-keeping_2"))
        XCTAssertFalse(BaseSchemaValidator.isValidAppID("Bad App"))
        XCTAssertFalse(BaseSchemaValidator.isValidAppID(String(repeating: "a", count: 49)))
    }

    // MARK: golden 02 表名非法

    func testInvalidTableNameMatchesFixture02() {
        let table: [String: Any] = [
            "name": "Bad-Table!",
            "fields": [["name": "amount", "type": "number"]]
        ]
        XCTAssertThrowsError(try BaseSchemaValidator.parseTable(table)) { error in
            let e = error as! BaseSchemaValidator.ValidationError
            XCTAssertEqual(e.reason.message, "表名不合法")
            XCTAssertEqual(e.reason.hint, "表名须匹配 ^[a-z][a-z0-9_]{0,47}$")
        }
    }

    // MARK: golden 03 字段类型非法

    func testInvalidFieldTypeMatchesFixture03() {
        let table: [String: Any] = [
            "name": "weird",
            "fields": [["name": "data", "type": "blob"]]
        ]
        XCTAssertThrowsError(try BaseSchemaValidator.parseTable(table)) { error in
            let e = error as! BaseSchemaValidator.ValidationError
            XCTAssertEqual(e.reason.message, "字段类型不合法")
            XCTAssertEqual(e.reason.hint, "字段类型只允许 text/number/boolean/date/enum/relation/asset")
        }
    }

    // MARK: golden 04 字段缺少类型

    func testMissingFieldTypeMatchesFixture04() {
        let table: [String: Any] = [
            "name": "broken",
            "fields": [["name": "amount"]]
        ]
        XCTAssertThrowsError(try BaseSchemaValidator.parseTable(table)) { error in
            let e = error as! BaseSchemaValidator.ValidationError
            XCTAssertEqual(e.reason.message, "字段缺少类型")
            XCTAssertEqual(e.reason.hint, "字段定义必须包含 type")
        }
    }

    // MARK: golden 05 字段重名

    func testDuplicateFieldMatchesFixture05() {
        let table: [String: Any] = [
            "name": "dups",
            "fields": [
                ["name": "a", "type": "number"],
                ["name": "a", "type": "text"]
            ]
        ]
        XCTAssertThrowsError(try BaseSchemaValidator.parseTable(table)) { error in
            let e = error as! BaseSchemaValidator.ValidationError
            XCTAssertEqual(e.reason.message, "字段名重复")
            XCTAssertEqual(e.reason.hint, "同一表内字段名须唯一")
        }
    }

    // MARK: golden 01 合法 App schema

    func testValidAppSchemaMatchesFixture01() {
        let schema: [String: Any] = [
            "tables": [
                [
                    "name": "expenses",
                    "fields": [
                        ["name": "amount", "type": "number", "required": true, "range": ["min": 0]],
                        ["name": "category", "type": "enum", "enum": ["food", "transport", "home", "other"]],
                        ["name": "date", "type": "date", "required": true],
                        ["name": "note", "type": "text"],
                        ["name": "owner", "type": "relation", "relation": ["table": "members", "on": "id"]]
                    ]
                ],
                [
                    "name": "members",
                    "fields": [["name": "name", "type": "text", "required": true]]
                ]
            ]
        ]
        let parsed = try? BaseSchemaValidator.parseSchema(schema)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.tables.count, 2)
        XCTAssertEqual(parsed?.table(named: "expenses")?.fields.count, 5)
    }

    // MARK: relation 跨子库边界（M1-K3 的静态层：解析期即拒）

    func testRelationToUnknownTableRejected() {
        let schema: [String: Any] = [
            "tables": [
                [
                    "name": "expenses",
                    "fields": [["name": "owner", "type": "relation", "relation": ["table": "other_lib", "on": "id"]]]
                ]
            ]
        ]
        XCTAssertThrowsError(try BaseSchemaValidator.parseSchema(schema)) { error in
            let e = error as! BaseSchemaValidator.ValidationError
            XCTAssertEqual(e.reason.message, "关系字段引用了不存在的表")
        }
    }

    // MARK: enum 缺值

    func testEnumNeedsValues() throws {
        // enum 字段不提供 enum 数组：契约校验器允许（值校验留待记录写入），此处仅验证类型可解析。
        let table: [String: Any] = [
            "name": "t",
            "fields": [["name": "cat", "type": "enum"]]
        ]
        let parsed = try BaseSchemaValidator.parseTable(table)
        XCTAssertEqual(parsed.fields[0].type, "enum")
    }

    // MARK: range

    func testInvalidRangeRejected() {
        let table: [String: Any] = [
            "name": "t",
            "fields": [["name": "n", "type": "number", "range": ["min": 10, "max": 1]]]
        ]
        XCTAssertThrowsError(try BaseSchemaValidator.parseTable(table))
    }
}
