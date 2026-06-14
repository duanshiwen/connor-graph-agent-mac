import Foundation
import ConnorGraphAgent
import ConnorGraphAppSupport

enum AppWorkspaceRootDraftMapper {
    static func drafts(from settings: AgentRuntimeWorkspaceSettings) -> [WorkspaceRootDraft] {
        let roots = settings.effectiveRoots()
        let primaryID = roots.first(where: \.isPrimary)?.id ?? roots.first?.id
        return roots.map { root in
            WorkspaceRootDraft(
                id: root.id,
                displayName: root.displayName,
                path: root.path,
                role: root.role,
                isPrimary: root.id == primaryID
            )
        }
    }

    static func drafts(from workspace: AppSessionWorkspaceReference) -> [WorkspaceRootDraft] {
        let primaryID = workspace.roots.first(where: \.isPrimary)?.id ?? workspace.roots.first?.id
        let trimmedWorkingDirectoryPath = workspace.workingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if workspace.roots.isEmpty, !trimmedWorkingDirectoryPath.isEmpty {
            return [WorkspaceRootDraft(
                displayName: URL(fileURLWithPath: trimmedWorkingDirectoryPath).lastPathComponent,
                path: trimmedWorkingDirectoryPath,
                role: "project",
                isPrimary: true
            )]
        }
        return workspace.roots.map { root in
            WorkspaceRootDraft(
                id: root.id,
                displayName: root.displayName,
                path: root.path,
                role: root.role,
                isPrimary: root.id == primaryID
            )
        }
    }
}
