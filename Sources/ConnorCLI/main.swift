import Foundation
import ConnorGraphAppSupport
import ConnorGraphCore
import ConnorGraphStore

let args = Array(CommandLine.arguments.dropFirst())
let output = try ConnorCLI.route(args: args)
print(output)

struct ConnorCLI {
    static func route(args: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if args.isEmpty || args == ["commands"] || args == ["--help"] {
            return try encode(ConnorLocalTaskSurfaceCatalog.defaultCommands, encoder: encoder)
        }
        if args.first == "readiness" {
            return try encode(ConnorLocalTaskSurfaceReadiness.default, encoder: encoder)
        }
        if args.first == "tasks" {
            return try routeTasks(args: Array(args.dropFirst()), encoder: encoder)
        }
        if args.first == "memory" {
            return try AppMemoryOSCLIRouter.route(args: Array(args.dropFirst()), inspector: AppMemoryOSCLIRouter.makeLiveInspector(), encoder: encoder)
        }
        let error: [String: String] = ["error": "unknown_command", "usage": "connor commands"]
        return try encode(error, encoder: encoder)
    }

    private static func routeTasks(args: [String], encoder: JSONEncoder) throws -> String {
        let paths = try AppStoragePaths.live()
        let repository = AppTaskManagementRepository(storagePaths: paths)
        let stack = try makeTaskStack(repository: repository, paths: paths)
        _ = try repository.loadOrCreateDefault()
        let command = args.first ?? "list"
        switch command {
        case "list":
            return try encode(try stack.listTasks(), encoder: encoder)
        case "show":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            return try encode(try stack.task(id: id), encoder: encoder)
        case "runs":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            return try encode(try stack.runHistory(taskID: id), encoder: encoder)
        case "stop":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            return try encode(try stack.stopTask(id: id, reason: "cli"), encoder: encoder)
        case "restore":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            return try encode(try stack.restoreTask(id: id), encoder: encoder)
        case "delete":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            return try encode(try stack.deleteTask(id: id, reason: "cli"), encoder: encoder)
        case "purge":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            return try encode(try stack.purgeTask(id: id, reason: "cli"), encoder: encoder)
        case "rename":
            guard let id = args.dropFirst().first else { return try encode(["error": "missing_task_id"], encoder: encoder) }
            guard let newName = args.dropFirst().dropFirst().first else { return try encode(["error": "missing_new_name"], encoder: encoder) }
            return try encode(try stack.renameTask(id: id, newName: newName), encoder: encoder)
        case "session":
            return try routeSessionTasks(args: Array(args.dropFirst()), stack: stack, encoder: encoder)
        default:
            return try encode(["error": "unknown_tasks_command", "usage": "connor tasks list|show|stop|restore|delete|purge|rename"], encoder: encoder)
        }
    }

    private static func routeSessionTasks(args: [String], stack: TaskManagementStack, encoder: JSONEncoder) throws -> String {
        let command = args.first ?? "list"
        switch command {
        case "list":
            guard let sessionID = args.dropFirst().first else { return try encode(["error": "missing_session_id"], encoder: encoder) }
            return try encode(try stack.listSessionTasks(sessionID: sessionID), encoder: encoder)
        case "recoverable":
            guard let sessionID = args.dropFirst().first else { return try encode(["error": "missing_session_id"], encoder: encoder) }
            return try encode(try stack.recoverableSessionTasks(sessionID: sessionID), encoder: encoder)
        case "stop":
            let values = Array(args.dropFirst())
            guard values.count >= 2 else { return try encode(["error": "missing_session_id_or_task_id"], encoder: encoder) }
            return try encode(try stack.stopSessionTask(sessionID: values[0], taskID: values[1], reason: "cli"), encoder: encoder)
        case "restore":
            let values = Array(args.dropFirst())
            guard values.count >= 2 else { return try encode(["error": "missing_session_id_or_task_id"], encoder: encoder) }
            return try encode(try stack.restoreSessionTask(sessionID: values[0], taskID: values[1]), encoder: encoder)
        default:
            return try encode(["error": "unknown_tasks_session_command", "usage": "connor tasks session list <session-id>"], encoder: encoder)
        }
    }

    private static func makeTaskStack(repository: AppTaskManagementRepository, paths: AppStoragePaths) throws -> TaskManagementStack {
        let store = try AppGraphBootstrapper(paths: paths).bootstrapStore()
        let sessionRepository = AppChatSessionRepository(store: store, storagePaths: paths)
        return TaskManagementStack(repository: repository, sessionRepository: sessionRepository)
    }

    private static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
