import Foundation
import ConnorGraphAppSupport
import ConnorGraphCore

@main
struct ConnorCLI {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let output = try route(args: args)
        print(output)
    }

    private static func route(args: [String]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if args.isEmpty || args == ["commands"] || args == ["--help"] {
            return try encode(ConnorLocalAutomationSurfaceCatalog.defaultCommands, encoder: encoder)
        }
        if args.first == "readiness" {
            let presentation = ConnorLocalAutomationSurfacePresentation.default
            let payload: [String: String] = [
                "surface": "local-api-cli-automation",
                "status": "ready",
                "endpoints": "\(presentation.endpoints.count)",
                "commands": "\(presentation.cliCommands.count)",
                "localOnly": "\(presentation.localOnly)"
            ]
            return try encode(payload, encoder: encoder)
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
