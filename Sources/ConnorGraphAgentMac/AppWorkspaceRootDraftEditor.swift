import Foundation

enum AppWorkspaceRootDraftEditor {
    @discardableResult
    static func addRoot(path rawPath: String, to roots: inout [WorkspaceRootDraft], makePrimary: Bool) -> Bool {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        if let existing = roots.first(where: { $0.path == path }) {
            if makePrimary { setPrimaryRoot(id: existing.id, in: &roots) }
            return false
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if makePrimary {
            for index in roots.indices { roots[index].isPrimary = false }
        }
        roots.append(WorkspaceRootDraft(
            displayName: url.lastPathComponent.isEmpty ? path : url.lastPathComponent,
            path: path,
            role: roots.isEmpty ? "project" : "additional",
            isPrimary: makePrimary || roots.isEmpty
        ))
        normalizePrimary(in: &roots)
        return true
    }

    static func removeRoot(id: String, from roots: inout [WorkspaceRootDraft]) {
        let removedWasPrimary = roots.first(where: { $0.id == id })?.isPrimary == true
        roots.removeAll { $0.id == id }
        if removedWasPrimary, !roots.isEmpty {
            roots[0].isPrimary = true
        }
        normalizePrimary(in: &roots)
    }

    static func setPrimaryRoot(id: String, in roots: inout [WorkspaceRootDraft]) {
        for index in roots.indices {
            roots[index].isPrimary = roots[index].id == id
        }
        normalizePrimary(in: &roots)
    }

    static func normalizePrimary(in roots: inout [WorkspaceRootDraft]) {
        guard !roots.isEmpty else { return }
        let primaryID = roots.first(where: \.isPrimary)?.id ?? roots[0].id
        for index in roots.indices {
            roots[index].isPrimary = roots[index].id == primaryID
        }
    }
}
