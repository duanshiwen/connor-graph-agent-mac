import XCTest
import Foundation
import SQLite3
@testable import ConnorGraphBase

/// 注册库 schema 迁移回归：旧版 base_apps 缺列时，打开 registry 必须幂等补列。
///
/// 根因（2026-09 记账 App 创建失败）：guide_version 列随 M2-M2 加入 canonical DDL，
/// 但 ensureRegistryTables 只对 purpose 做了 ALTER 迁移；从更早版本升级的设备
/// （CREATE TABLE IF NOT EXISTS 不改已存在的表）缺 guide_version，
/// createApp 的 INSERT 直接报 "table base_apps has no column named guide_version"（SQL 编译失败）。
final class BaseRegistryMigrationTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("base-registry-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// M7 双态硬切：guide 须为 {authoring, usage}（测试夹具与内核同一口径）。
    private func guide(_ appID: String) -> [String: Any] {
        let state: [String: Any] = ["appID": appID, "whenToUse": "记一笔时用",
                                    "whenNotToUse": "闲聊时不用", "sections": []]
        return ["authoring": state, "usage": state]
    }

    private func manifest(_ appID: String) -> [String: Any] {
        ["appID": appID, "name": "记账", "domain": "finance", "visibility": "private",
         "requiredCapabilities": [], "imports": [], "riskLevel": "low", "sdkVersion": 1]
    }

    /// 旧版 base_apps（M2 schema：有 purpose、无 guide_version）打开后应自动补列，createApp 成功。
    func testRegistryMigrationAddsMissingGuideVersionColumn() throws {
        let registryURL = tmpDir.appendingPathComponent("base_registry.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(registryURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, """
            CREATE TABLE base_apps (
                app_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                domain TEXT NOT NULL DEFAULT '',
                visibility TEXT NOT NULL DEFAULT 'private',
                package_version INTEGER NOT NULL DEFAULT 0,
                sdk_version INTEGER NOT NULL DEFAULT 1,
                risk_level TEXT NOT NULL DEFAULT 'low',
                capabilities_json TEXT NOT NULL DEFAULT '[]',
                imports_json TEXT NOT NULL DEFAULT '[]',
                schema_json TEXT NOT NULL DEFAULT '{\"tables\":[]}',
                guide_json TEXT NOT NULL DEFAULT '{}',
                methods_json TEXT NOT NULL DEFAULT '[]',
                purpose TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(handle)

        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        // 迁移前缺列；createApp 的 INSERT 引用 guide_version——迁移未跑会抛 SQL 编译失败。
        _ = try library.createApp(manifest: manifest("migrated"), schemaObject: ["tables": []],
                                  guide: guide("migrated"), methods: [])
        XCTAssertTrue(try library.appExists("migrated"))
    }

    /// 更老的 M1 时代 base_apps（连 purpose 也没有）同样要补齐两列并创建成功。
    func testRegistryMigrationFromM1SchemaAddsBothColumns() throws {
        let registryURL = tmpDir.appendingPathComponent("base_registry.db")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(registryURL.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, """
            CREATE TABLE base_apps (
                app_id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                domain TEXT NOT NULL DEFAULT '',
                visibility TEXT NOT NULL DEFAULT 'private',
                package_version INTEGER NOT NULL DEFAULT 0,
                sdk_version INTEGER NOT NULL DEFAULT 1,
                risk_level TEXT NOT NULL DEFAULT 'low',
                capabilities_json TEXT NOT NULL DEFAULT '[]',
                imports_json TEXT NOT NULL DEFAULT '[]',
                schema_json TEXT NOT NULL DEFAULT '{\"tables\":[]}',
                guide_json TEXT NOT NULL DEFAULT '{}',
                methods_json TEXT NOT NULL DEFAULT '[]',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """, nil, nil, nil), SQLITE_OK)
        sqlite3_close_v2(handle)

        let library = try BaseLibraryStore(directory: tmpDir)
        defer { library.close() }
        _ = try library.createApp(manifest: manifest("oldschool"), schemaObject: ["tables": []],
                                  guide: guide("oldschool"), methods: [])
        let apps = try library.listApps()
        XCTAssertTrue(try library.appExists("oldschool"))
        XCTAssertEqual(apps.first?["purpose"] as? String, "")
    }
}
