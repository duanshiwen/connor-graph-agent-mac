import CryptoKit
import Foundation

public enum InteractiveWebChoiceMode: String, Codable, Sendable { case single, multiple }
public enum InteractiveWebAccessMode: String, Codable, Sendable { case `public`, password, `private` }

public struct InteractiveWebAnalytics: Codable, Sendable, Equatable {
    public var views: Int
    public var interactions: Int
    public var errors: Int
}

public struct InteractiveWebChoiceOption: Codable, Sendable, Equatable {
    public var id: String
    public var label: String
    public init(id: String, label: String) { self.id = id; self.label = label }
}

public struct InteractiveWebChoiceSelector: Codable, Sendable, Equatable {
    public var id: String
    public var prompt: String
    public var mode: InteractiveWebChoiceMode
    public var required: Bool
    public var allowCustom: Bool
    public var options: [InteractiveWebChoiceOption]
    public var minSelections: Int?
    public var maxSelections: Int?
    public init(id: String, prompt: String, mode: InteractiveWebChoiceMode, required: Bool = true, allowCustom: Bool = false, options: [InteractiveWebChoiceOption], minSelections: Int? = nil, maxSelections: Int? = nil) {
        self.id = id; self.prompt = prompt; self.mode = mode; self.required = required; self.allowCustom = allowCustom; self.options = options; self.minSelections = minSelections; self.maxSelections = maxSelections
    }
}

public struct InteractiveWebChoiceRequest: Codable, Sendable, Equatable {
    public var choiceRequestID: String
    public var accountID: String
    public var conversationID: String
    public var contextRevision: Int
    public var selectors: [InteractiveWebChoiceSelector]
    public var state: String
    public init(choiceRequestID: String, accountID: String, conversationID: String, contextRevision: Int, selectors: [InteractiveWebChoiceSelector], state: String = "awaiting_user_choice") {
        self.choiceRequestID = choiceRequestID; self.accountID = accountID; self.conversationID = conversationID; self.contextRevision = contextRevision; self.selectors = selectors; self.state = state
    }
}

public struct InteractiveWebChoiceSelection: Codable, Sendable, Equatable {
    public var selectorID: String
    public var optionIDs: [String]
    public var customValues: [String]
    public init(selectorID: String, optionIDs: [String] = [], customValues: [String] = []) { self.selectorID = selectorID; self.optionIDs = optionIDs; self.customValues = customValues }
}

public struct InteractiveWebChoiceResponse: Codable, Sendable, Equatable {
    public var choiceRequestID: String
    public var selections: [InteractiveWebChoiceSelection]
    public init(choiceRequestID: String, selections: [InteractiveWebChoiceSelection]) { self.choiceRequestID = choiceRequestID; self.selections = selections }
}

public enum InteractiveWebChoiceError: Error, Equatable { case invalid(fields: [String: String]); case staleContext; case missingRequest }

public enum InteractiveWebChoiceValidator {
    public static func validate(_ response: InteractiveWebChoiceResponse, for request: InteractiveWebChoiceRequest) throws {
        var errors: [String: String] = [:]
        if request.state != "awaiting_user_choice" || request.choiceRequestID != response.choiceRequestID { errors["choiceRequestId"] = "选择批次已失效" }
        let responses = Dictionary(uniqueKeysWithValues: response.selections.map { ($0.selectorID, $0) })
        for selector in request.selectors {
            let selection = responses[selector.id]
            let options = selection?.optionIDs ?? []
            let custom = selection?.customValues ?? []
            let known = Set(selector.options.map(\.id))
            let count = options.count + custom.count
            if options.contains(where: { !known.contains($0) }) { errors[selector.id] = "包含未知选项" }
            else if !selector.allowCustom && !custom.isEmpty { errors[selector.id] = "不允许自定义答案" }
            else if custom.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.count > 500 }) { errors[selector.id] = "自定义答案长度无效" }
            else if selector.required && count == 0 { errors[selector.id] = "此项必填" }
            else if selector.mode == .single && count > 1 { errors[selector.id] = "只能选择一项" }
            else if let minimum = selector.minSelections, count < minimum { errors[selector.id] = "选择数量不足" }
            else if let maximum = selector.maxSelections, count > maximum { errors[selector.id] = "选择数量超限" }
        }
        if !errors.isEmpty { throw InteractiveWebChoiceError.invalid(fields: errors) }
    }
}

public struct LocalInteractiveWebProject: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var accountID: String
    public var name: String
    public var rootURL: URL
    public var conversationID: String
    public var remoteProjectID: String?
    public var remoteSiteID: String?
    public var latestDeploymentID: String?
    public var publishedURL: URL?
    public var revision: Int?
    /// 正在进行分块写入、尚未 final 完成的文件名列表（nil 视为空）。非空时草稿不算创建完成，publish 会拒绝。
    public var incompleteWrites: [String]?
    public init(id: String = UUID().uuidString, accountID: String, name: String, rootURL: URL, conversationID: String, remoteProjectID: String? = nil, remoteSiteID: String? = nil, latestDeploymentID: String? = nil, publishedURL: URL? = nil, revision: Int? = 1, incompleteWrites: [String]? = nil) {
        self.id = id; self.accountID = accountID; self.name = name; self.rootURL = rootURL; self.conversationID = conversationID; self.remoteProjectID = remoteProjectID; self.remoteSiteID = remoteSiteID; self.latestDeploymentID = latestDeploymentID; self.publishedURL = publishedURL; self.revision = revision; self.incompleteWrites = incompleteWrites
    }
}

public struct InteractiveWebProjectStatus: Codable, Sendable, Equatable {
    public var projectID: String
    public var name: String
    public var rootURL: URL
    public var revision: Int
    public var manifestHash: String
    public var fileCount: Int
    public var totalBytes: Int64
    public var fileNames: [String]
    public var remoteProjectID: String?
    public var remoteSiteID: String?
    public var latestDeploymentID: String?
    public var publishedURL: URL?
    /// 尚未 final 完成的分块写入文件；非空表示草稿未创建完成。
    public var incompleteWrites: [String]

    public init(
        projectID: String,
        name: String,
        rootURL: URL,
        revision: Int,
        manifestHash: String,
        fileCount: Int,
        totalBytes: Int64,
        fileNames: [String] = [],
        remoteProjectID: String? = nil,
        remoteSiteID: String? = nil,
        latestDeploymentID: String? = nil,
        publishedURL: URL? = nil,
        incompleteWrites: [String] = []
    ) {
        self.projectID = projectID
        self.name = name
        self.rootURL = rootURL
        self.revision = revision
        self.manifestHash = manifestHash
        self.fileCount = fileCount
        self.totalBytes = totalBytes
        self.fileNames = fileNames
        self.remoteProjectID = remoteProjectID
        self.remoteSiteID = remoteSiteID
        self.latestDeploymentID = latestDeploymentID
        self.publishedURL = publishedURL
        self.incompleteWrites = incompleteWrites
    }
}

public struct InteractiveWebDraftSource: Codable, Sendable, Equatable {
    public var projectID: String
    public var revision: Int
    public var manifestHash: String
    public var fileName: String
    public var content: String
    public var availableFiles: [String]
    public var offset: Int
    public var limit: Int
    public var totalCharacters: Int
    public var truncated: Bool
    public var nextOffset: Int?
    public var remainingCharacters: Int
    public var estimatedRemainingCalls: Int

    public init(
        projectID: String,
        revision: Int,
        manifestHash: String,
        fileName: String,
        content: String,
        availableFiles: [String] = [],
        offset: Int = 0,
        limit: Int = 0,
        totalCharacters: Int = 0,
        truncated: Bool = false,
        nextOffset: Int? = nil,
        remainingCharacters: Int = 0,
        estimatedRemainingCalls: Int = 0
    ) {
        self.projectID = projectID
        self.revision = revision
        self.manifestHash = manifestHash
        self.fileName = fileName
        self.content = content
        self.availableFiles = availableFiles
        self.offset = offset
        self.limit = limit
        self.totalCharacters = totalCharacters
        self.truncated = truncated
        self.nextOffset = nextOffset
        self.remainingCharacters = remainingCharacters
        self.estimatedRemainingCalls = estimatedRemainingCalls
    }
}

/// 单个文件在保存前后的变更摘要（纯文本，供任何模型核对，不依赖截图/图片识别）。
public struct InteractiveWebDraftFileChange: Codable, Sendable, Equatable {
    public var fileName: String
    public var operation: String
    public var beforeHash: String
    public var afterHash: String
    public var beforeSizeBytes: Int
    public var afterSizeBytes: Int
    public var diff: String

    public init(
        fileName: String,
        operation: String,
        beforeHash: String,
        afterHash: String,
        beforeSizeBytes: Int,
        afterSizeBytes: Int,
        diff: String
    ) {
        self.fileName = fileName
        self.operation = operation
        self.beforeHash = beforeHash
        self.afterHash = afterHash
        self.beforeSizeBytes = beforeSizeBytes
        self.afterSizeBytes = afterSizeBytes
        self.diff = diff
    }
}

/// create_draft 的统一结果：新建或更新后的状态 + 本次实际变更的文件清单。
/// 更新 = 传同一个 projectID 与完整编辑后的文件，与新建共用同一个工具与方法。
public struct InteractiveWebDraftSaveResult: Codable, Sendable, Equatable {
    public var status: InteractiveWebProjectStatus
    public var changes: [InteractiveWebDraftFileChange]
    /// 分块写入时本块写入的起始位置；完整模式为 0。
    public var offset: Int
    /// 分块写入未完成时的下一个写入位置；完成或完整模式为 nil。
    public var nextOffset: Int?

    public init(status: InteractiveWebProjectStatus, changes: [InteractiveWebDraftFileChange], offset: Int = 0, nextOffset: Int? = nil) {
        self.status = status
        self.changes = changes
        self.offset = offset
        self.nextOffset = nextOffset
    }
}

/// 极简定向编辑结果：一次精确文本替换后的状态、文件指纹与统一 diff。
public struct InteractiveWebDraftEditResult: Codable, Sendable, Equatable {
    public var status: InteractiveWebProjectStatus
    public var fileName: String
    public var beforeHash: String
    public var afterHash: String
    public var beforeSizeBytes: Int
    public var afterSizeBytes: Int
    public var diff: String
    public var offset: Int
    public var nextOffset: Int?
    public var resultTotalCharacters: Int

    public init(
        status: InteractiveWebProjectStatus,
        fileName: String,
        beforeHash: String,
        afterHash: String,
        beforeSizeBytes: Int,
        afterSizeBytes: Int,
        diff: String,
        offset: Int = 0,
        nextOffset: Int? = nil,
        resultTotalCharacters: Int = 0
    ) {
        self.status = status
        self.fileName = fileName
        self.beforeHash = beforeHash
        self.afterHash = afterHash
        self.beforeSizeBytes = beforeSizeBytes
        self.afterSizeBytes = afterSizeBytes
        self.diff = diff
        self.offset = offset
        self.nextOffset = nextOffset
        self.resultTotalCharacters = resultTotalCharacters
    }
}

public struct InteractiveWebExportResult: Codable, Sendable, Equatable {
    public var projectID: String
    public var collection: String
    public var fileURL: URL
    public var sizeBytes: Int64
}

public struct InteractiveWebManifestFile: Codable, Sendable, Equatable {
    public var path: String
    public var sha256: String
    public var mediaType: String
    public var sizeBytes: Int64
    public init(path: String, sha256: String, mediaType: String, sizeBytes: Int64) {
        self.path = path
        self.sha256 = sha256
        self.mediaType = mediaType
        self.sizeBytes = sizeBytes
    }
}

public struct InteractiveWebCollectionField: Codable, Sendable, Equatable {
    public var name: String
    public var type: String
    public var required: Bool
    public var maxLength: Int
    public var `enum`: [String]
    public var pattern: String?
    public init(name: String, type: String, required: Bool = false, maxLength: Int = 0, enum: [String] = [], pattern: String = "") { self.name = name; self.type = type; self.required = required; self.maxLength = maxLength; self.enum = `enum`; self.pattern = pattern }
}

public struct InteractiveWebSubmitLimit: Codable, Sendable, Equatable {
    public var max: Int
    public var window: String
    public var scope: String
    public init(max: Int, window: String, scope: String) { self.max = max; self.window = window; self.scope = scope }
}

public struct InteractiveWebCollectionDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var fields: [InteractiveWebCollectionField]
    public var anonymousCreate: Bool
    public var anonymousRead: Bool
    public var submitLimit: InteractiveWebSubmitLimit?
    public var readStats: String?
    public init(name: String, fields: [InteractiveWebCollectionField], anonymousCreate: Bool = false, anonymousRead: Bool = false, submitLimit: InteractiveWebSubmitLimit? = nil, readStats: String? = nil) { self.name = name; self.fields = fields; self.anonymousCreate = anonymousCreate; self.anonymousRead = anonymousRead; self.submitLimit = submitLimit; self.readStats = readStats }
}

public struct InteractiveWebManifest: Codable, Sendable, Equatable {
    public var entryPoint = "index.html"
    public var componentVersion = "1"
    public var files: [InteractiveWebManifestFile]
    public var collections: [InteractiveWebCollectionDefinition]
    public init(files: [InteractiveWebManifestFile], collections: [InteractiveWebCollectionDefinition] = []) { self.files = files; self.collections = collections }
}

private struct InteractiveWebProjectConfiguration: Codable {
    var formatVersion = 1
    var collections: [InteractiveWebCollectionDefinition]
}

/// 互动网页项目配置校验失败时抛出的错误。
/// 之前这里混用了 CocoaError(.fileReadCorruptFile)，会把"submitLimit/readStats 配置值不合法"
/// 包装成"文件读取异常/文件损坏"，让人误以为是磁盘或后端读取问题；这里改为带明确字段说明的配置错误。
public struct InteractiveWebConfigurationError: Error, LocalizedError, CustomStringConvertible, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
    public var description: String { message }
}

public struct InteractiveWebPackager: Sendable {
    public static let configurationFileName = "connor.web.json"
    public init() {}

    public static func configurationJSON(collections: [InteractiveWebCollectionDefinition]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(InteractiveWebProjectConfiguration(collections: collections)), as: UTF8.self)
    }

    public func package(rootURL: URL, fileManager: FileManager = .default) throws -> InteractiveWebManifest {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let allowed = Set(["html", "css", "js", "json", "png", "jpg", "jpeg", "gif", "webp", "svg", "woff", "woff2"])
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { throw CocoaError(.fileReadNoSuchFile) }
        var files: [InteractiveWebManifestFile] = []
        for case let url as URL in enumerator {
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            guard resolved.path.hasPrefix(root.path + "/") else { throw CocoaError(.fileReadNoPermission) }
            let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { continue }
            let ext = resolved.pathExtension.lowercased()
            guard allowed.contains(ext) else { throw CocoaError(.fileReadUnsupportedScheme) }
            let size = Int64(values.fileSize ?? 0)
            guard size <= 20 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf: resolved, options: .mappedIfSafe)
            let path = String(resolved.path.dropFirst(root.path.count + 1))
            files.append(.init(path: path, sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), mediaType: Self.mediaType(ext), sizeBytes: size))
        }
        files.sort { $0.path < $1.path }
        guard files.contains(where: { $0.path == "index.html" }) else { throw InteractiveWebConfigurationError("project package is missing index.html") }
        guard files.count <= 500 else { throw InteractiveWebConfigurationError("project package exceeds the 500-file limit") }
        guard files.reduce(0, { $0 + $1.sizeBytes }) <= 100 * 1_024 * 1_024 else { throw InteractiveWebConfigurationError("project package exceeds the 100 MB total-size limit") }
        let configurationURL = root.appendingPathComponent(Self.configurationFileName)
        let collections: [InteractiveWebCollectionDefinition]
        if fileManager.fileExists(atPath: configurationURL.path) {
            let data = try Data(contentsOf: configurationURL)
            guard data.count <= 2 * 1_024 * 1_024 else { throw CocoaError(.fileReadTooLarge) }
            let configuration = try JSONDecoder().decode(InteractiveWebProjectConfiguration.self, from: data)
            guard configuration.formatVersion == 1 else { throw CocoaError(.fileReadUnsupportedScheme) }
            collections = configuration.collections
        } else {
            collections = []
        }
        try validate(collections: collections)
        return InteractiveWebManifest(files: files, collections: collections.map(Self.backendCompatible))
    }

    public func fingerprint(_ manifest: InteractiveWebManifest) -> String {
        var canonical = "\(manifest.entryPoint)\n\(manifest.componentVersion)\n"
        for file in manifest.files.sorted(by: { $0.path < $1.path }) {
            canonical += "\(file.path)\t\(file.sha256)\t\(file.mediaType)\t\(file.sizeBytes)\n"
        }
        for collection in manifest.collections.sorted(by: { $0.name < $1.name }) {
            canonical += "collection\t\(collection.name)\t\(collection.anonymousCreate)\t\(collection.anonymousRead)\t\(collection.readStats ?? "")\n"
            if let limit = collection.submitLimit {
                canonical += "submitLimit\t\(limit.max)\t\(limit.window)\t\(limit.scope)\n"
            }
            for field in collection.fields.sorted(by: { $0.name < $1.name }) {
                canonical += "\(field.name)\t\(field.type)\t\(field.required)\t\(field.maxLength)\t\(field.enum.joined(separator: ","))\t\(field.pattern ?? "")\n"
            }
        }
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// The backend compiles collection field patterns with Go's regexp (RE2), which does
    /// not accept ICU/Java-style `\uXXXX` escapes even though the local draft validator
    /// (NSRegularExpression) does. Normalize the manifest at the packager boundary so the
    /// same RE2-compatible pattern is used for the manifest hash and for the publish
    /// finalize request, without requiring any backend change.
    private static func backendCompatible(_ collection: InteractiveWebCollectionDefinition) -> InteractiveWebCollectionDefinition {
        var normalized = collection
        normalized.fields = collection.fields.map { field in
            guard let pattern = field.pattern, !pattern.isEmpty else { return field }
            var copy = field
            copy.pattern = re2CompatiblePattern(pattern)
            return copy
        }
        return normalized
    }

    private static func re2CompatiblePattern(_ pattern: String) -> String {
        let characters = Array(pattern)
        var output = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "\\",
               index + 2 < characters.count,
               characters[index + 1] == "u" || characters[index + 1] == "U" {
                let digitCount = characters[index + 1] == "u" ? 4 : 8
                let digitsStart = index + 2
                if digitsStart + digitCount <= characters.count {
                    let hexDigits = String(characters[digitsStart..<(digitsStart + digitCount)])
                    if hexDigits.allSatisfy(\.isHexDigit) {
                        output += "\\x{\(hexDigits)}"
                        index = digitsStart + digitCount
                        continue
                    }
                }
            }
            output.append(characters[index])
            index += 1
        }
        return output
    }

    private static func mediaType(_ ext: String) -> String {
        ["html":"text/html", "css":"text/css", "js":"text/javascript", "json":"application/json", "png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "gif":"image/gif", "webp":"image/webp", "svg":"image/svg+xml", "woff":"font/woff", "woff2":"font/woff2"][ext] ?? "application/octet-stream"
    }

    private func validate(collections: [InteractiveWebCollectionDefinition]) throws {
        guard Set(collections.map(\.name)).count == collections.count else {
            throw InteractiveWebConfigurationError("collection names must be unique")
        }
        let namePattern = try NSRegularExpression(pattern: "^[a-z][a-z0-9_]{0,63}$")
        func validName(_ value: String) -> Bool {
            namePattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) != nil
        }
        for collection in collections {
            guard validName(collection.name) else {
                throw InteractiveWebConfigurationError("collection '\(collection.name)': name must match ^[a-z][a-z0-9_]{0,63}$")
            }
            guard (1...50).contains(collection.fields.count) else {
                throw InteractiveWebConfigurationError("collection '\(collection.name)': fields must contain 1 to 50 entries")
            }
            guard Set(collection.fields.map(\.name)).count == collection.fields.count else {
                throw InteractiveWebConfigurationError("collection '\(collection.name)': field names must be unique")
            }
            if let readStats = collection.readStats {
                guard ["public", "login", "owner"].contains(readStats) else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': readStats must be one of public, login, or owner (got '\(readStats)')")
                }
            }
            if let limit = collection.submitLimit {
                guard limit.max > 0, limit.max <= 10000 else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': submitLimit.max must be between 1 and 10000")
                }
                guard ["lifetime", "day"].contains(limit.window) else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': submitLimit.window must be lifetime or day (got '\(limit.window)')")
                }
                guard ["account", "ip"].contains(limit.scope) else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': submitLimit.scope must be account or ip (got '\(limit.scope)')")
                }
                guard limit.scope != "account" || !collection.anonymousCreate else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': submitLimit with scope=account requires anonymousCreate=false (per-account counting needs login)")
                }
            }
            for field in collection.fields {
                let pattern = field.pattern ?? ""
                guard validName(field.name) else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': field name '\(field.name)' must match ^[a-z][a-z0-9_]{0,63}$")
                }
                guard ["string", "number", "boolean", "enum"].contains(field.type) else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': field '\(field.name)' type must be string, number, boolean, or enum (got '\(field.type)')")
                }
                guard (0...5000).contains(field.maxLength) else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': field '\(field.name)' maxLength must be between 0 and 5000")
                }
                guard pattern.count <= 256 else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': field '\(field.name)' pattern must be at most 256 characters")
                }
                guard field.type != "enum" || !field.enum.isEmpty else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': enum field '\(field.name)' requires at least one allowed value")
                }
                guard pattern.isEmpty || field.type == "string" else {
                    throw InteractiveWebConfigurationError("collection '\(collection.name)': pattern is only supported for string field '\(field.name)'")
                }
                if !pattern.isEmpty {
                    if let unsupported = Self.re2UnsupportedFeature(in: pattern) {
                        throw InteractiveWebConfigurationError("collection '\(collection.name)': field '\(field.name)' pattern 使用了后端 RE2 不支持的特性：\(unsupported)。请改写成不依赖该特性的正则后重新生成草稿。")
                    }
                    _ = try NSRegularExpression(pattern: pattern)
                }
            }
        }
    }

    /// Go's regexp (RE2) intentionally omits several ICU/Java features. Reject those
    /// constructs at draft time so publishing never fails with an opaque backend 422;
    /// the agent rewrites the pattern into RE2-compatible syntax before publishing.
    private static func re2UnsupportedFeature(in pattern: String) -> String? {
        let characters = Array(pattern)
        var index = 0
        var inClass = false
        var classFirst = false
        while index < characters.count {
            let char = characters[index]
            if char == "\\" {
                if !inClass, index + 1 < characters.count {
                    switch characters[index + 1] {
                    case "1"..."9": return "反向引用 \\\(characters[index + 1])"
                    case "k": return "命名反向引用 \\k"
                    case "G": return "Java 专属锚点 \\G"
                    default: break
                    }
                }
                index += 2
                continue
            }
            if inClass {
                if char == "]" && !classFirst {
                    inClass = false
                } else if char == "]" {
                    classFirst = false
                } else if classFirst, char != "^" {
                    classFirst = false
                }
                index += 1
                continue
            }
            if char == "[" {
                inClass = true
                classFirst = true
                index += 1
                continue
            }
            if char == "(", index + 2 < characters.count, characters[index + 1] == "?" {
                switch characters[index + 2] {
                case "=": return "正向环视 (?=...)"
                case "!": return "负向环视 (?!...)"
                case ">": return "原子组 (?>...)"
                case "(": return "条件组 (?(...)...)"
                case "<" where index + 3 < characters.count && (characters[index + 3] == "=" || characters[index + 3] == "!"):
                    return characters[index + 3] == "=" ? "逆序环视 (?<=...)" : "负向逆序环视 (?<!...)"
                default: break
                }
            }
            if "*+?}".contains(char), index + 1 < characters.count, characters[index + 1] == "+" {
                return "占有量词（possessive quantifier）"
            }
            index += 1
        }
        return nil
    }
}

private struct InteractiveWebLocalState: Codable { var projects: [LocalInteractiveWebProject] = []; var choices: [InteractiveWebChoiceRequest] = [] }

public actor InteractiveWebLocalStore {
    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(storagePaths: AppStoragePaths) { self.fileURL = storagePaths.artifactsDirectory.appendingPathComponent("interactive-web-state.json") }

    public func save(project: LocalInteractiveWebProject) throws { var state = try read(); state.projects.removeAll { $0.id == project.id }; state.projects.append(project); try write(state) }
    public func projects(accountID: String) throws -> [LocalInteractiveWebProject] { try read().projects.filter { $0.accountID == accountID } }
    public func project(id: String) throws -> LocalInteractiveWebProject? { try read().projects.first { $0.id == id } }
    public func project(remoteProjectID: String) throws -> LocalInteractiveWebProject? { try read().projects.first { $0.remoteProjectID == remoteProjectID } }
    public func save(choice: InteractiveWebChoiceRequest) throws { var state = try read(); state.choices.removeAll { $0.choiceRequestID == choice.choiceRequestID }; state.choices.append(choice); try write(state) }
    public func pendingChoices(accountID: String, conversationID: String) throws -> [InteractiveWebChoiceRequest] { try read().choices.filter { $0.accountID == accountID && $0.conversationID == conversationID && $0.state == "awaiting_user_choice" } }
    public func complete(_ response: InteractiveWebChoiceResponse, contextRevision: Int) throws -> Bool {
        var state = try read(); guard let index = state.choices.firstIndex(where: { $0.choiceRequestID == response.choiceRequestID }) else { throw InteractiveWebChoiceError.missingRequest }
        if state.choices[index].state == "completed" { return false }
        guard state.choices[index].contextRevision == contextRevision else { throw InteractiveWebChoiceError.staleContext }
        try InteractiveWebChoiceValidator.validate(response, for: state.choices[index]); state.choices[index].state = "completed"; try write(state); return true
    }
    private func read() throws -> InteractiveWebLocalState { guard FileManager.default.fileExists(atPath: fileURL.path) else { return .init() }; return try decoder.decode(InteractiveWebLocalState.self, from: Data(contentsOf: fileURL)) }
    private func write(_ state: InteractiveWebLocalState) throws { try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); try encoder.encode(state).write(to: fileURL, options: .atomic) }
}
