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
    public init(id: String = UUID().uuidString, accountID: String, name: String, rootURL: URL, conversationID: String, remoteProjectID: String? = nil, remoteSiteID: String? = nil, latestDeploymentID: String? = nil, publishedURL: URL? = nil, revision: Int? = 1) {
        self.id = id; self.accountID = accountID; self.name = name; self.rootURL = rootURL; self.conversationID = conversationID; self.remoteProjectID = remoteProjectID; self.remoteSiteID = remoteSiteID; self.latestDeploymentID = latestDeploymentID; self.publishedURL = publishedURL; self.revision = revision
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
    public var remoteProjectID: String?
    public var remoteSiteID: String?
    public var latestDeploymentID: String?
    public var publishedURL: URL?
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
}

public struct InteractiveWebCollectionField: Codable, Sendable, Equatable {
    public var name: String
    public var type: String
    public var required: Bool
    public var maxLength: Int
    public var `enum`: [String]
    public init(name: String, type: String, required: Bool = false, maxLength: Int = 0, enum: [String] = []) { self.name = name; self.type = type; self.required = required; self.maxLength = maxLength; self.enum = `enum` }
}

public struct InteractiveWebCollectionDefinition: Codable, Sendable, Equatable {
    public var name: String
    public var fields: [InteractiveWebCollectionField]
    public var anonymousCreate: Bool
    public var anonymousRead: Bool
    public init(name: String, fields: [InteractiveWebCollectionField], anonymousCreate: Bool = false, anonymousRead: Bool = false) { self.name = name; self.fields = fields; self.anonymousCreate = anonymousCreate; self.anonymousRead = anonymousRead }
}

public struct InteractiveWebManifest: Codable, Sendable, Equatable {
    public var entryPoint = "index.html"
    public var componentVersion = "1"
    public var files: [InteractiveWebManifestFile]
    public var collections: [InteractiveWebCollectionDefinition]
    public init(files: [InteractiveWebManifestFile], collections: [InteractiveWebCollectionDefinition] = []) { self.files = files; self.collections = collections }
}

public struct InteractiveWebPackager: Sendable {
    public init() {}
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
        guard files.contains(where: { $0.path == "index.html" }), files.count <= 500, files.reduce(0, { $0 + $1.sizeBytes }) <= 100 * 1_024 * 1_024 else { throw CocoaError(.fileReadCorruptFile) }
        return InteractiveWebManifest(files: files)
    }

    public func fingerprint(_ manifest: InteractiveWebManifest) -> String {
        var canonical = "\(manifest.entryPoint)\n\(manifest.componentVersion)\n"
        for file in manifest.files.sorted(by: { $0.path < $1.path }) {
            canonical += "\(file.path)\t\(file.sha256)\t\(file.mediaType)\t\(file.sizeBytes)\n"
        }
        for collection in manifest.collections.sorted(by: { $0.name < $1.name }) {
            canonical += "collection\t\(collection.name)\t\(collection.anonymousCreate)\t\(collection.anonymousRead)\n"
            for field in collection.fields.sorted(by: { $0.name < $1.name }) {
                canonical += "\(field.name)\t\(field.type)\t\(field.required)\t\(field.maxLength)\t\(field.enum.joined(separator: ","))\n"
            }
        }
        return SHA256.hash(data: Data(canonical.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func mediaType(_ ext: String) -> String {
        ["html":"text/html", "css":"text/css", "js":"text/javascript", "json":"application/json", "png":"image/png", "jpg":"image/jpeg", "jpeg":"image/jpeg", "gif":"image/gif", "webp":"image/webp", "svg":"image/svg+xml", "woff":"font/woff", "woff2":"font/woff2"][ext] ?? "application/octet-stream"
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
