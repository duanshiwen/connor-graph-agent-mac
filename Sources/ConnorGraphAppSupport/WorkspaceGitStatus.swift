import Foundation

public enum WorkspaceGitFileStatus: String, Sendable, Equatable {
    case added
    case modified
}

public actor WorkspaceGitStatusLoader {
    public init() {}

    public func statuses(for workspaceRootURL: URL) -> [String: WorkspaceGitFileStatus] {
        guard let repositoryRootPath = runGit(
            in: workspaceRootURL,
            arguments: ["rev-parse", "--show-toplevel"]
        ).flatMap({ String(data: $0, encoding: .utf8) })?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !repositoryRootPath.isEmpty
        else {
            return [:]
        }
        let repositoryRootURL = URL(fileURLWithPath: repositoryRootPath, isDirectory: true)
        guard let data = runGit(
            in: repositoryRootURL,
            arguments: ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignored=no"]
        ) else {
            return [:]
        }
        return Self.parsePorcelainV1Z(data, repositoryRootURL: repositoryRootURL)
    }

    private func runGit(in directoryURL: URL, arguments: [String]) -> Data? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directoryURL.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? data : nil
        } catch {
            return nil
        }
    }

    static func parsePorcelainV1Z(
        _ data: Data,
        repositoryRootURL: URL
    ) -> [String: WorkspaceGitFileStatus] {
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
        var statuses: [String: WorkspaceGitFileStatus] = [:]
        var recordIndex = 0

        while recordIndex < records.count {
            let record = records[recordIndex]
            guard record.count >= 4 else {
                recordIndex += 1
                continue
            }

            let indexStatus = Character(UnicodeScalar(record[record.startIndex]))
            let workTreeStatus = Character(UnicodeScalar(record[record.index(after: record.startIndex)]))
            let pathBytes = record.dropFirst(3)
            guard let relativePath = String(bytes: pathBytes, encoding: .utf8) else {
                recordIndex += 1
                continue
            }

            let status: WorkspaceGitFileStatus =
                (indexStatus == "?" && workTreeStatus == "?") || indexStatus == "A"
                ? .added
                : .modified
            let fileURL = repositoryRootURL.appendingPathComponent(relativePath).standardizedFileURL
            statuses[fileURL.path] = status

            if indexStatus == "R" || indexStatus == "C" {
                recordIndex += 1
            }
            recordIndex += 1
        }
        return statuses
    }
}
