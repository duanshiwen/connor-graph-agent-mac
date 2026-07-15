import Foundation
import Observation
import ConnorGraphCore
import ConnorGraphAppSupport

struct MCPSourceDraft: Equatable {
    var editingSourceID: String?
    var sourceID: String = ""
    var displayName: String = ""
    var transportKind: String = "stdio"
    var command: String = ""
    var argumentsText: String = ""
    var status: ProductOSRegistryEntryStatus = .draft
    var credentialRequirement: ProductOSCredentialRequirement = .none
    var credentialEnvironmentText: String = ""
    var credentialSecret: String = ""
    var allowExternalNetwork: Bool = true
    var allowReadSession: Bool = true
    var allowWorkspaceRead: Bool = false
    var tagsText: String = "mcp"
    var notes: String = ""

    init() {}

    init(configuration: MCPSourceRuntimeConfiguration) {
        editingSourceID = configuration.sourceID
        sourceID = configuration.sourceID
        displayName = configuration.displayName
        status = configuration.status
        credentialRequirement = configuration.credentialRequirement
        credentialEnvironmentText = configuration.credentialBindings.map { binding in
            binding.label.isEmpty || binding.label == binding.environmentVariable
                ? binding.environmentVariable
                : "\(binding.label):\(binding.environmentVariable)"
        }.joined(separator: ", ")
        allowExternalNetwork = configuration.allowedCapabilities.contains(.externalNetwork)
        allowReadSession = configuration.allowedCapabilities.contains(.readSession)
        allowWorkspaceRead = configuration.allowedCapabilities.contains(.readWorkspaceFile) || configuration.allowedCapabilities.contains(.listWorkspaceFiles)
        tagsText = configuration.tags.joined(separator: ", ")
        notes = configuration.notes
        switch configuration.transport {
        case .stdio(let command, let arguments):
            transportKind = "stdio"
            self.command = command
            self.argumentsText = arguments.joined(separator: " ")
        case .http(let url):
            transportKind = "http"
            self.command = url.absoluteString
            self.argumentsText = ""
        }
    }

    var parsedArguments: [String] {
        argumentsText
            .split(whereSeparator: { $0 == "\n" || $0 == " " || $0 == "\t" })
            .map(String.init)
    }

    var parsedCredentialBindings: [MCPSourceCredentialBinding] {
        guard credentialRequirement != .none else { return [] }
        var bindings: [String: MCPSourceCredentialBinding] = [:]
        for token in credentialEnvironmentText.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" }) {
            let parsed = Self.parseCredentialBindingToken(String(token))
            if let parsed { bindings[parsed.environmentVariable] = parsed }
        }
        for env in parsedCredentialSecretByEnvironment.keys.sorted() where bindings[env] == nil {
            bindings[env] = MCPSourceCredentialBinding(label: env, environmentVariable: env)
        }
        return bindings.values.sorted { $0.environmentVariable < $1.environmentVariable }
    }

    var parsedCredentialSecretByEnvironment: [String: String] {
        var values: [String: String] = [:]
        for line in credentialSecret.split(whereSeparator: { $0 == "\n" || $0 == ";" }) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separatorIndex = text.firstIndex(of: "=") else { continue }
            let key = String(text[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let value = String(text[text.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty { values[key] = value }
        }
        return values
    }

    var trimmedCredentialSecret: String {
        credentialSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseCredentialBindingToken(_ raw: String) -> MCPSourceCredentialBinding? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let separator = text.firstIndex(where: { $0 == ":" || $0 == "=" }) {
            let label = String(text[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let env = String(text[text.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !label.isEmpty, !env.isEmpty else { return nil }
            return MCPSourceCredentialBinding(label: label, environmentVariable: env)
        }
        let env = text.uppercased()
        return MCPSourceCredentialBinding(label: env, environmentVariable: env)
    }

    var parsedTags: [String] {
        Array(Set(tagsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\t" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }))
        .sorted()
    }

    var runtimeTransport: MCPSourceRuntimeTransport? {
        let endpoint = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if transportKind == "http" {
            guard let url = URL(string: endpoint), url.scheme != nil, url.host != nil else { return nil }
            return .http(url: url)
        }
        return .stdio(command: endpoint, arguments: parsedArguments)
    }

    var allowedCapabilities: [AgentPermissionCapability] {
        var capabilities: [AgentPermissionCapability] = []
        if allowExternalNetwork { capabilities.append(.externalNetwork) }
        if allowReadSession { capabilities.append(.readSession) }
        if allowWorkspaceRead {
            capabilities.append(.readWorkspaceFile)
            capabilities.append(.listWorkspaceFiles)
        }
        return capabilities.isEmpty ? [.readSession] : capabilities
    }

    var normalizedSourceID: String {
        sourceID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var normalizedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? normalizedSourceID : trimmed
    }

    var isEditing: Bool { editingSourceID != nil }
}

@MainActor
@Observable
final class SourceRuntimeFeatureModel {
    enum Event {
        case operationSucceeded
        case operationFailed(String)
    }

    var configurations: [MCPSourceRuntimeConfiguration] = []
    var healthRecords: [MCPSourceRuntimeHealthRecord] = []
    var toolCatalogs: [String: [MCPSourceToolDescriptor]] = [:]
    var auditRecordsBySource: [String: [MCPSourceRuntimeAuditRecord]] = [:]
    var selectedCardID: String?
    var testingSourceIDs: Set<String> = []
    var testMessages: [String: String] = [:]
    var isPresentingAddSheet = false
    var addDraft = MCPSourceDraft()
    var addMessage: String?
    var pendingDeletionID: String?
    var pendingDeletionName: String?

    @ObservationIgnored private let repository: AppMCPSourceRuntimeRepository?
    @ObservationIgnored private let credentialStore: MCPSourceCredentialStore
    @ObservationIgnored var workingDirectoryURLProvider: @MainActor () -> URL?
    @ObservationIgnored var onEvent: ((Event) -> Void)?

    init(
        repository: AppMCPSourceRuntimeRepository?,
        credentialStore: MCPSourceCredentialStore = MCPSourceCredentialStore(),
        workingDirectoryURLProvider: @escaping @MainActor () -> URL? = { nil }
    ) {
        self.repository = repository
        self.credentialStore = credentialStore
        self.workingDirectoryURLProvider = workingDirectoryURLProvider
    }

    var presentation: SourceRuntimeUIPresentation {
        SourceRuntimeUIPresentation.build(
            sources: configurations,
            healthRecords: healthRecords,
            auditRecords: auditRecordsBySource.values.flatMap { $0 }
        )
    }

    func applyStartupSnapshot(_ result: StartupDomainResult<SourceRuntimeContentSnapshot>) {
        guard let snapshot = result.value else {
            if let failureMessage = result.failureMessage { onEvent?(.operationFailed(failureMessage)) }
            return
        }
        configurations = snapshot.configurations
        healthRecords = snapshot.healthRecords
        toolCatalogs = snapshot.toolCatalogs
        auditRecordsBySource = snapshot.auditRecordsBySource
        if let selectedCardID,
           !configurations.contains(where: { $0.sourceID == selectedCardID }) {
            self.selectedCardID = nil
        }
    }

    func reload() {
        do {
            let configurations = try repository?.list() ?? []
            self.configurations = configurations
            healthRecords = try repository?.listHealthRecords() ?? []
            var catalogs: [String: [MCPSourceToolDescriptor]] = [:]
            var audits: [String: [MCPSourceRuntimeAuditRecord]] = [:]
            for configuration in configurations {
                catalogs[configuration.sourceID] = try repository?.loadToolCatalog(sourceID: configuration.sourceID) ?? []
                audits[configuration.sourceID] = try repository?.loadRecentAuditRecords(sourceID: configuration.sourceID, limit: 12) ?? []
            }
            toolCatalogs = catalogs
            auditRecordsBySource = audits
            if let selectedCardID,
               !configurations.contains(where: { $0.sourceID == selectedCardID }) {
                self.selectedCardID = nil
            }
            onEvent?(.operationSucceeded)
        } catch {
            onEvent?(.operationFailed(String(describing: error)))
        }
    }

    func selectCard(_ id: String) {
        selectedCardID = id
    }

    func presentAddSheet() {
        addDraft = MCPSourceDraft()
        addMessage = nil
        isPresentingAddSheet = true
    }

    func presentEditSheet(sourceID: String) {
        guard let configuration = configurations.first(where: { $0.sourceID == sourceID }) else {
            testMessages[sourceID] = "Source configuration not found."
            return
        }
        addDraft = MCPSourceDraft(configuration: configuration)
        addMessage = nil
        isPresentingAddSheet = true
    }

    func dismissAddSheet() {
        isPresentingAddSheet = false
        addMessage = nil
    }

    func saveDraft() {
        guard let repository else {
            addMessage = "Source runtime repository is not available."
            return
        }
        let draft = addDraft
        let originalConfiguration = draft.editingSourceID.flatMap { sourceID in
            configurations.first(where: { $0.sourceID == sourceID })
        }
        if let originalSourceID = draft.editingSourceID, draft.normalizedSourceID != originalSourceID {
            addMessage = "Editing Source ID is not supported yet. Create a new source instead."
            return
        }
        let sourceID = originalConfiguration?.sourceID ?? draft.normalizedSourceID
        guard let transport = draft.runtimeTransport else {
            addMessage = "Invalid HTTP MCP endpoint URL. Use https://host/path, or http://localhost/path for local development."
            return
        }
        let configuration = MCPSourceRuntimeConfiguration(
            sourceID: sourceID,
            displayName: draft.normalizedDisplayName,
            transport: transport,
            status: draft.status,
            credentialRequirement: draft.credentialRequirement,
            credentialBindings: draft.parsedCredentialBindings,
            allowedCapabilities: draft.allowedCapabilities,
            toolNamePrefix: originalConfiguration?.toolNamePrefix ?? sourceID,
            graphIngestionEnabled: false,
            graphWritePolicy: .readOnly,
            tags: draft.parsedTags,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: originalConfiguration?.createdAt ?? Date()
        )
        do {
            try repository.save(configuration)
            if configuration.credentialRequirement == .none {
                if let originalConfiguration {
                    try credentialStore.deleteSecrets(sourceID: configuration.sourceID, bindings: originalConfiguration.credentialBindings)
                }
            } else if !draft.trimmedCredentialSecret.isEmpty {
                let secretsByEnvironment = draft.parsedCredentialSecretByEnvironment
                for binding in configuration.credentialBindings {
                    let secret = secretsByEnvironment[binding.environmentVariable] ?? draft.trimmedCredentialSecret
                    try credentialStore.saveSecret(
                        secret,
                        sourceID: configuration.sourceID,
                        environmentVariable: binding.environmentVariable
                    )
                }
            }
            reload()
            selectedCardID = configuration.sourceID
            testMessages[configuration.sourceID] = draft.isEditing
                ? "Source updated. Run Test Source to refresh tools if transport changed."
                : "Source saved. Run Test Source to discover tools."
            isPresentingAddSheet = false
            addMessage = nil
            onEvent?(.operationSucceeded)
        } catch {
            addMessage = "Unable to save source: \(String(describing: error))"
        }
    }

    func setStatus(sourceID: String, status: ProductOSRegistryEntryStatus) {
        guard let repository else {
            testMessages[sourceID] = "Source runtime repository is not available."
            return
        }
        guard var configuration = configurations.first(where: { $0.sourceID == sourceID }) else {
            testMessages[sourceID] = "Source configuration not found."
            return
        }
        configuration.status = status
        do {
            try repository.save(configuration)
            reload()
            selectedCardID = sourceID
            testMessages[sourceID] = "Source status updated to \(status.rawValue)."
            onEvent?(.operationSucceeded)
        } catch {
            testMessages[sourceID] = "Unable to update source status: \(String(describing: error))"
        }
    }

    func archive(sourceID: String) {
        setStatus(sourceID: sourceID, status: .deprecated)
        testMessages[sourceID] = "Source archived as deprecated. Catalog, health and audit history are preserved."
    }

    func requestDelete(sourceID: String) {
        guard let configuration = configurations.first(where: { $0.sourceID == sourceID }) else {
            testMessages[sourceID] = "Source configuration not found."
            return
        }
        pendingDeletionID = sourceID
        pendingDeletionName = configuration.displayName
    }

    func cancelDelete() {
        pendingDeletionID = nil
        pendingDeletionName = nil
    }

    func confirmDelete() {
        guard let sourceID = pendingDeletionID else { return }
        guard let repository else {
            testMessages[sourceID] = "Source runtime repository is not available."
            cancelDelete()
            return
        }
        do {
            if let configuration = configurations.first(where: { $0.sourceID == sourceID }) {
                try credentialStore.deleteSecrets(sourceID: sourceID, bindings: configuration.credentialBindings)
            }
            try repository.deleteSourceRuntime(sourceID: sourceID)
            testMessages.removeValue(forKey: sourceID)
            toolCatalogs.removeValue(forKey: sourceID)
            auditRecordsBySource.removeValue(forKey: sourceID)
            healthRecords.removeAll { $0.sourceID == sourceID }
            if selectedCardID == sourceID {
                selectedCardID = nil
            }
            cancelDelete()
            reload()
            onEvent?(.operationSucceeded)
        } catch {
            testMessages[sourceID] = "Unable to delete source: \(String(describing: error))"
            cancelDelete()
        }
    }

    func testSource(sourceID: String) async {
        guard !testingSourceIDs.contains(sourceID) else { return }
        guard let repository else {
            testMessages[sourceID] = "Source runtime repository is not available."
            return
        }
        guard let configuration = configurations.first(where: { $0.sourceID == sourceID }) else {
            testMessages[sourceID] = "Source configuration not found."
            return
        }
        testingSourceIDs.insert(sourceID)
        testMessages[sourceID] = "Testing source…"
        defer { testingSourceIDs.remove(sourceID) }

        let service = MCPSourceTestService(
            repository: repository,
            currentDirectoryURL: workingDirectoryURLProvider(),
            credentialStore: credentialStore
        )
        do {
            let report = try await service.testSource(configuration)
            testMessages[sourceID] = report.success
                ? "Source test passed · discovered \(report.catalog.count) tools."
                : "Source test completed with unhealthy status · discovered \(report.catalog.count) tools."
            reload()
            selectedCardID = sourceID
            onEvent?(.operationSucceeded)
        } catch {
            testMessages[sourceID] = "Source test failed: \(String(describing: error))"
            reload()
            selectedCardID = sourceID
        }
    }
}
