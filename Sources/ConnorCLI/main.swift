import Foundation
import ConnorGraphAppSupport
import ConnorGraphCore

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
        if args.first == "automations", args.dropFirst().first == "evaluate" {
            let request = ConnorAutomationSurfaceTriggerRequest(
                triggerKind: parseTrigger(args: args) ?? .sessionStatusChanged,
                sessionID: parseOption("--session", args: args) ?? "demo",
                status: parseStatus(args: args),
                dryRun: args.contains("--dry-run"),
                reviewed: args.contains("--reviewed")
            )
            let evaluation = ConnorAutomationSurfaceEvaluator().evaluate(request: request, config: .default)
            return try encode(evaluation, encoder: encoder)
        }
        let error: [String: String] = ["error": "unknown_command", "usage": "connor commands"]
        return try encode(error, encoder: encoder)
    }

    private static func routeTasks(args: [String], encoder: JSONEncoder) throws -> String {
        let paths = try AppStoragePaths.live()
        let repository = AppTaskManagementRepository(storagePaths: paths)
        let stack = TaskManagementStack(repository: repository)
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
        default:
            return try encode(["error": "unknown_tasks_command", "usage": "connor tasks list"], encoder: encoder)
        }
    }

    private static func parseOption(_ name: String, args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), args.indices.contains(args.index(after: index)) else { return nil }
        return args[args.index(after: index)]
    }

    private static func parseTrigger(args: [String]) -> ProductOSAutomationTriggerKind? {
        parseOption("--trigger", args: args).flatMap(ProductOSAutomationTriggerKind.init(rawValue:))
    }

    private static func parseStatus(args: [String]) -> AgentSessionStatus? {
        parseOption("--status", args: args).flatMap(AgentSessionStatus.init(rawValue:))
    }

    private static func encode<T: Encodable>(_ value: T, encoder: JSONEncoder) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
