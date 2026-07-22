import Foundation
import Testing
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport
@testable import ConnorGraphAgentMac

@MainActor
struct SkillRuntimeFeatureModelTests {
    @Test func instructionPresentationLimitsCollapsedLayoutWork() {
        let source = "  " + String(repeating: "内容", count: 1_000) + "  "

        let presentation = SkillInstructionsPresentation(instructions: source)

        #expect(presentation.isCollapsible)
        #expect(presentation.fullText == String(repeating: "内容", count: 1_000))
        #expect(presentation.collapsedText.hasSuffix("\n\n…"))
        #expect(presentation.collapsedText.count == SkillInstructionsPresentation.previewCharacterLimit + 3)
    }

    @Test func emptyInstructionPresentationUsesStableFallback() {
        let presentation = SkillInstructionsPresentation(instructions: " \n ")

        #expect(presentation.fullText == "No instructions found.")
        #expect(presentation.collapsedText == presentation.fullText)
        #expect(!presentation.isCollapsible)
    }

    @Test func multilineInstructionPresentationAlwaysOffersFullTextWhenPreviewIsTruncated() {
        let source = (1...20).map { "Step \($0)" }.joined(separator: "\n")

        let presentation = SkillInstructionsPresentation(instructions: source)

        #expect(source.count < SkillInstructionsPresentation.previewCharacterLimit)
        #expect(presentation.isCollapsible)
        #expect(presentation.fullText == source)
        #expect(presentation.collapsedText == (1...18).map { "Step \($0)" }.joined(separator: "\n") + "\n\n…")
    }

    @Test func reloadBuildsDefinitionsAndCommercialPresentation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeSkill(slug: "review-skill", name: "Review Skill", paths: fixture.paths)
        let definition = try fixture.repository.loadSkill(
            slug: "review-skill",
            scope: .home,
            skillURL: fixture.paths.skillsDirectory
                .appendingPathComponent("review-skill", isDirectory: true)
                .appendingPathComponent("SKILL.md")
        )
        try fixture.repository.save(definition)

        let model = SkillRuntimeFeatureModel(repository: fixture.repository, storagePaths: fixture.paths)
        model.selectedCardID = "missing-skill"
        model.reload()

        #expect(model.definitions.map(\.slug) == ["review-skill"])
        #expect(model.presentation.cards.map(\.id) == ["review-skill"])
        #expect(model.presentation.summary.total == 1)
        #expect(model.selectedCardID == nil)
    }

    @Test func dialogsDelegateAddAndEditThroughNarrowAsyncHandlers() async {
        let model = SkillRuntimeFeatureModel(repository: nil, storagePaths: nil)
        model.onAddRequest = { request in
            #expect(request == "创建审查技能")
            return "review-skill"
        }
        let card = makeCard(id: "review-skill", sourceTier: SkillSourceTier.user.rawValue, packagePath: "/tmp/review-skill")
        model.onEditRequest = { receivedCard, request in
            #expect(receivedCard.id == card.id)
            #expect(request == "增加安全检查")
        }

        model.presentAddDialog()
        model.addRequestDraft = "  创建审查技能  "
        await model.submitAddRequest()
        #expect(model.addDialogMessage == "技能已创建：review-skill。")
        #expect(model.selectedCardID == "review-skill")
        #expect(model.isSubmittingAddRequest == false)

        model.presentEditDialog(card: card)
        model.editRequestDraft = " 增加安全检查 "
        await model.submitEditRequest()
        #expect(model.editDialogMessage == "修改请求已提交。完成后技能列表会自动刷新。")
        #expect(model.selectedCardID == card.id)
        #expect(model.isSubmittingEditRequest == false)
    }

    @Test func toolMutationEventReloadsAndSafeDeleteRemovesOnlyUserPackage() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try writeSkill(slug: "delete-skill", name: "Delete Skill", paths: fixture.paths)
        let packageURL = fixture.paths.skillsDirectory.appendingPathComponent("delete-skill", isDirectory: true)
        let card = makeCard(id: "delete-skill", sourceTier: SkillSourceTier.user.rawValue, packagePath: packageURL.path)
        let model = SkillRuntimeFeatureModel(repository: fixture.repository, storagePaths: fixture.paths)
        model.selectedCardID = card.id

        let mutation = AgentEventPresentation(
            kind: AgentEventKind.toolFinished.rawValue,
            title: "Tool finished: connor_skill_create",
            detail: "created",
            severity: .success,
            runID: "run",
            sessionID: "session"
        )
        model.reloadIfNeeded(after: mutation)
        #expect(model.presentation.cards.map(\.id) == [card.id])

        model.requestDelete(card: card)
        model.confirmDelete()
        #expect(FileManager.default.fileExists(atPath: packageURL.path) == false)
        #expect(model.pendingDeletionCard == nil)
        #expect(model.selectedCardID == nil)
    }

    @Test func unavailableSessionHandlerPreservesDialogFeedback() async {
        let model = SkillRuntimeFeatureModel(repository: nil, storagePaths: nil)
        model.presentAddDialog()
        model.addRequestDraft = "创建技能"
        await model.submitAddRequest()
        #expect(model.addDialogMessage == "会话系统尚未初始化。")

        let card = makeCard(id: "review-skill", sourceTier: SkillSourceTier.user.rawValue, packagePath: "/tmp/review-skill")
        model.presentEditDialog(card: card)
        model.editRequestDraft = "修改技能"
        await model.submitEditRequest()
        #expect(model.editDialogMessage == "会话系统尚未初始化。")
    }

    @Test func discoversSelectsAndImportsExternalSkillsIntoUserLibrary() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let externalRoot = fixture.root.appendingPathComponent("external-skills", isDirectory: true)
        let externalSkill = externalRoot.appendingPathComponent("external-review", isDirectory: true)
        let importedInstructions = (1...20).map { "Review step \($0)." }.joined(separator: "\n")
        try FileManager.default.createDirectory(at: externalSkill, withIntermediateDirectories: true)
        try """
        ---
        name: External Review
        description: Imported from another agent
        ---
        \(importedInstructions)
        """.write(to: externalSkill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let importer = ExternalSkillLibraryImporter(roots: [
            ExternalSkillLibraryRoot(source: .claudeCode, directoryURL: externalRoot)
        ])
        let model = SkillRuntimeFeatureModel(
            repository: fixture.repository,
            storagePaths: fixture.paths,
            externalSkillImporter: importer
        )

        model.prepareSkillImport()
        #expect(model.importCandidates.map(\.slug) == ["external-review"])
        #expect(model.selectedImportCandidateIDs == Set(model.importCandidates.map(\.id)))

        await model.submitSkillImport()

        #expect(FileManager.default.fileExists(atPath: fixture.paths.skillsDirectory.appendingPathComponent("external-review/SKILL.md").path))
        #expect(model.presentation.cards.map(\.id) == ["external-review"])
        let importedCard = try #require(model.presentation.cards.first)
        #expect(importedCard.instructions == importedInstructions)
        #expect(SkillInstructionsPresentation(instructions: importedCard.instructions).isCollapsible)
        #expect(model.importDialogMessage == "已导入 1 个技能。")
        #expect(model.selectedImportCandidateIDs.isEmpty)
    }

    private func makeFixture() throws -> (root: URL, paths: AppStoragePaths, repository: AppSkillRuntimeRepository) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-skill-runtime-model-\(UUID().uuidString)", isDirectory: true)
        let paths = AppStoragePaths.resolving(applicationSupportBaseDirectory: root)
        try paths.ensureDirectoryHierarchy(fileManager: .default)
        return (root, paths, AppSkillRuntimeRepository(storagePaths: paths))
    }

    private func writeSkill(slug: String, name: String, paths: AppStoragePaths) throws {
        let directory = paths.skillsDirectory.appendingPathComponent(slug, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        name: \(name)
        description: Test skill
        ---
        Follow the test instructions.
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }

    private func makeCard(id: String, sourceTier: String, packagePath: String) -> SkillManagerCard {
        SkillManagerCard(
            id: id,
            title: "Review Skill",
            subtitle: "Test skill",
            path: URL(fileURLWithPath: packagePath).appendingPathComponent("SKILL.md").path,
            packagePath: packagePath,
            instructions: "Follow the test instructions.",
            sourceTier: sourceTier,
            trustState: "userTrusted",
            riskLabel: "low",
            lifecycleLabel: "stable",
            requiredSources: [],
            permissionLabels: [],
            overrideChain: [],
            warnings: []
        )
    }
}
