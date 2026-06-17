import Foundation
import Testing
import ConnorGraphAppSupport
import ConnorGraphCore

private func makeGovernanceSkillPackage(slug: String = "skill") -> SkillPackage {
    SkillPackage(
        id: SkillPackageID("user:/tmp/\(slug)"),
        slug: SkillSlug(slug),
        sourceTier: .user,
        manifest: SkillManifest(name: "Skill", description: "Governed skill"),
        instructions: "Do work.",
        packagePath: "/tmp/\(slug)",
        skillFilePath: "/tmp/\(slug)/SKILL.md"
    )
}

@Suite("Commercial Skill Governance Services Tests")
struct SkillGovernanceServicesTests {
    @Test func evaluatesRequiredSourcesAndPreenableCandidates() {
        let result = SkillSourcePreenableService().evaluate(
            requiredSources: ["github", "linear", "missing"],
            availableSources: ["github", "linear"],
            enabledSources: ["github"],
            authenticatedSources: ["github", "linear"],
            policy: .preenableIfReady
        )

        #expect(result.enabledSources == ["linear"])
        #expect(result.blocksInvocation == false)
        #expect(result.readiness.first { $0.sourceSlug == "github" }?.state == .ready)
        #expect(result.readiness.first { $0.sourceSlug == "missing" }?.state == .missing)
    }

    @Test func requireReadyPolicyBlocksMissingOrUnauthenticatedSources() {
        let result = SkillSourcePreenableService().evaluate(
            requiredSources: ["github", "linear"],
            availableSources: ["github", "linear"],
            enabledSources: [],
            authenticatedSources: ["github"],
            policy: .requireReady
        )

        #expect(result.enabledSources == ["github"])
        #expect(result.blocksInvocation == true)
        #expect(result.readiness.first { $0.sourceSlug == "linear" }?.state == .unauthenticated)
    }

    @Test func mapsAllowedToolsToSkillScopedPermissionGrants() {
        var package = makeGovernanceSkillPackage(slug: "deploy")
        package.manifest.alwaysAllow = ["Bash"]
        package.manifest.allowedTools = ["Write", "WebFetch"]
        package.sourceTier = SkillSourceTier.project

        let grants: [SkillPermissionGrant] = SkillPermissionMapper().grants(for: package)
        let capabilities: [AgentPermissionCapability] = grants.map { $0.capability }

        #expect(capabilities.contains(AgentPermissionCapability.runWorkspaceShellCommand))
        #expect(capabilities.contains(AgentPermissionCapability.writeWorkspaceFile))
        #expect(capabilities.contains(AgentPermissionCapability.externalNetwork))
        #expect(grants.allSatisfy { $0.requiresApproval })
        #expect(grants.allSatisfy { $0.scope == SkillPermissionGrantScope.invocation })
    }

    @Test func projectSkillsRequireTrustByDefault() {
        var package = makeGovernanceSkillPackage(slug: "project-skill")
        package.sourceTier = SkillSourceTier.project
        package.trustState = SkillTrustState.projectRequiresTrust

        let state = SkillTrustStore().requiredTrustState(for: package)

        #expect(state == .projectRequiresTrust)
    }
}
