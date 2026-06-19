import Foundation
import ConnorGraphCore

public enum ScientificComputeOperation: String, Codable, Sendable, Equatable {
    case add
    case subtract
    case multiply
    case divide
    case greaterThan = "greater_than"
    case greaterThanOrEqual = "greater_than_or_equal"
    case lessThan = "less_than"
    case lessThanOrEqual = "less_than_or_equal"
    case equal
    case notEqual = "not_equal"
    case compare
    case summary
    case unitConvert = "unit_convert"
    case solveLinearSystem = "solve_linear_system"
    case symbolic
    case optimize
    case tableCompute = "table_compute"
}

public struct ScientificComputeOptions: Codable, Sendable, Equatable {
    public var absoluteTolerance: Double?
    public var relativeTolerance: Double?
    public var preferredEngine: String?

    public init(absoluteTolerance: Double? = nil, relativeTolerance: Double? = nil, preferredEngine: String? = nil) {
        self.absoluteTolerance = absoluteTolerance
        self.relativeTolerance = relativeTolerance
        self.preferredEngine = preferredEngine
    }
}

public struct ScientificComputeRequest: Codable, Sendable, Equatable {
    public var operation: ScientificComputeOperation
    public var inputs: ScientificValue
    public var options: ScientificComputeOptions

    public init(operation: ScientificComputeOperation, inputs: ScientificValue, options: ScientificComputeOptions = ScientificComputeOptions()) {
        self.operation = operation
        self.inputs = inputs
        self.options = options
    }
}

public enum ScientificValue: Codable, Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: ScientificValue])
    case array([ScientificValue])
    case null

    public var objectValue: [String: ScientificValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [ScientificValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }

    public init(sendableJSON value: SendableJSONValue) throws {
        switch value {
        case .string(let string): self = .string(string)
        case .int(let int): self = .int(int)
        case .double(let double): self = .double(double)
        case .bool(let bool): self = .bool(bool)
        case .object(let object): self = .object(try object.mapValues { try ScientificValue(sendableJSON: $0) })
        case .array(let array): self = .array(try array.map { try ScientificValue(sendableJSON: $0) })
        case .null: self = .null
        }
    }
}

public struct ScientificDiagnostics: Codable, Sendable, Equatable {
    public var engine: String
    public var method: String
    public var tolerance: ScientificComputeOptions
    public var warnings: [String]
    public var elapsedMilliseconds: Double

    public init(engine: String, method: String, tolerance: ScientificComputeOptions, warnings: [String] = [], elapsedMilliseconds: Double = 0) {
        self.engine = engine
        self.method = method
        self.tolerance = tolerance
        self.warnings = warnings
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public struct ScientificComputeResult: Codable, Sendable, Equatable {
    public var value: ScientificValue
    public var diagnostics: ScientificDiagnostics

    public init(value: ScientificValue, diagnostics: ScientificDiagnostics) {
        self.value = value
        self.diagnostics = diagnostics
    }
}

public enum ScientificComputeError: Error, Sendable, Equatable, CustomStringConvertible {
    case unsupportedOperation(String)
    case invalidInput(String)
    case incompatibleUnits(String)
    case singularMatrix

    public var description: String {
        switch self {
        case .unsupportedOperation(let message): return "Unsupported operation: \(message)"
        case .invalidInput(let message): return "Invalid input: \(message)"
        case .incompatibleUnits(let message): return "Incompatible units: \(message)"
        case .singularMatrix: return "Singular matrix"
        }
    }
}

public protocol ScientificComputeEngine: Sendable {
    var id: String { get }
    var version: String { get }
    func supports(_ request: ScientificComputeRequest) -> Bool
    func compute(_ request: ScientificComputeRequest) async throws -> ScientificComputeResult
}

public struct ScientificComputeRuntime: Sendable {
    private let engines: [any ScientificComputeEngine]

    public init(engines: [any ScientificComputeEngine] = [NativeSwiftScientificEngine()]) {
        self.engines = engines
    }

    public func compute(_ request: ScientificComputeRequest) async throws -> ScientificComputeResult {
        guard let engine = engines.first(where: { $0.supports(request) }) else {
            throw ScientificComputeError.unsupportedOperation(request.operation.rawValue)
        }
        return try await engine.compute(request)
    }
}

public struct NativeSwiftScientificEngine: ScientificComputeEngine {
    public let id = "native-swift"
    public let version = "0.1.0"

    public init() {}

    public func supports(_ request: ScientificComputeRequest) -> Bool {
        switch request.operation {
        case .add, .subtract, .multiply, .divide, .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .equal, .notEqual, .compare, .summary, .unitConvert, .solveLinearSystem:
            return true
        case .symbolic, .optimize, .tableCompute:
            return false
        }
    }

    public func compute(_ request: ScientificComputeRequest) async throws -> ScientificComputeResult {
        let start = Date()
        let value: ScientificValue
        var warnings: [String] = []
        switch request.operation {
        case .add:
            value = .double(try numbers(from: request.inputs, key: "values").reduce(0, +))
        case .subtract:
            let values = try numbers(from: request.inputs, key: "values")
            guard let first = values.first else { throw ScientificComputeError.invalidInput("subtract requires values") }
            value = .double(values.dropFirst().reduce(first, -))
        case .multiply:
            value = .double(try numbers(from: request.inputs, key: "values").reduce(1, *))
        case .divide:
            let values = try numbers(from: request.inputs, key: "values")
            guard let first = values.first else { throw ScientificComputeError.invalidInput("divide requires values") }
            value = .double(try values.dropFirst().reduce(first) { partial, next in
                guard next != 0 else { throw ScientificComputeError.invalidInput("division by zero") }
                return partial / next
            })
        case .greaterThan, .greaterThanOrEqual, .lessThan, .lessThanOrEqual, .equal, .notEqual, .compare:
            value = try compareValue(request: request, warnings: &warnings)
        case .summary:
            value = try summaryValue(request.inputs)
        case .unitConvert:
            value = try unitConvertValue(request.inputs)
        case .solveLinearSystem:
            value = try solveLinearSystemValue(request.inputs)
        case .symbolic, .optimize, .tableCompute:
            throw ScientificComputeError.unsupportedOperation(request.operation.rawValue)
        }
        return ScientificComputeResult(
            value: value,
            diagnostics: ScientificDiagnostics(
                engine: id,
                method: request.operation.rawValue,
                tolerance: request.options,
                warnings: warnings,
                elapsedMilliseconds: Date().timeIntervalSince(start) * 1000
            )
        )
    }

    private func object(_ value: ScientificValue) throws -> [String: ScientificValue] {
        guard let object = value.objectValue else { throw ScientificComputeError.invalidInput("Expected object inputs") }
        return object
    }

    private func numbers(from value: ScientificValue, key: String) throws -> [Double] {
        let object = try object(value)
        guard let values = object[key]?.arrayValue else { throw ScientificComputeError.invalidInput("Expected array at \(key)") }
        return try values.map { item in
            guard let number = item.doubleValue, number.isFinite else { throw ScientificComputeError.invalidInput("Expected finite number") }
            return number
        }
    }

    private func compareValue(request: ScientificComputeRequest, warnings: inout [String]) throws -> ScientificValue {
        let object = try object(request.inputs)
        guard let left = object["left"]?.doubleValue, let right = object["right"]?.doubleValue else {
            throw ScientificComputeError.invalidInput("compare requires numeric left and right")
        }
        let diff = left - right
        let absTolerance = request.options.absoluteTolerance
        let relTolerance = request.options.relativeTolerance
        let approximatelyEqual: Bool
        if let absTolerance {
            approximatelyEqual = abs(diff) <= absTolerance
        } else if let relTolerance {
            approximatelyEqual = abs(diff) <= relTolerance * max(abs(left), abs(right), 1)
        } else {
            approximatelyEqual = diff == 0
            if request.operation == .equal || request.operation == .notEqual || request.operation == .compare {
                warnings.append("Floating equality used without explicit tolerance policy.")
            }
        }

        let comparison: Int = approximatelyEqual ? 0 : (diff > 0 ? 1 : -1)
        let relation: String
        switch request.operation {
        case .greaterThan: relation = left > right && !approximatelyEqual ? "greater_than" : "false"
        case .greaterThanOrEqual: relation = (left > right || approximatelyEqual) ? "greater_than_or_equal" : "false"
        case .lessThan: relation = left < right && !approximatelyEqual ? "less_than" : "false"
        case .lessThanOrEqual: relation = (left < right || approximatelyEqual) ? "less_than_or_equal" : "false"
        case .equal: relation = approximatelyEqual ? (absTolerance != nil || relTolerance != nil ? "approximately_equal" : "equal") : "false"
        case .notEqual: relation = approximatelyEqual ? "false" : "not_equal"
        case .compare: relation = approximatelyEqual ? (absTolerance != nil || relTolerance != nil ? "approximately_equal" : "equal") : (comparison > 0 ? "greater_than" : "less_than")
        default: relation = "unknown"
        }
        return .object([
            "relation": .string(relation),
            "comparison": .int(comparison),
            "left": .double(left),
            "right": .double(right)
        ])
    }

    private func summaryValue(_ inputs: ScientificValue) throws -> ScientificValue {
        let values = try numbers(from: inputs, key: "values").sorted()
        guard !values.isEmpty else { throw ScientificComputeError.invalidInput("summary requires non-empty values") }
        let count = values.count
        let sum = values.reduce(0, +)
        let mean = sum / Double(count)
        let median = count % 2 == 1 ? values[count / 2] : (values[count / 2 - 1] + values[count / 2]) / 2
        let sampleVariance = count > 1 ? values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count - 1) : 0
        guard let minimum = values.first, let maximum = values.last else {
            throw ScientificComputeError.invalidInput("summary requires non-empty values")
        }
        return .object([
            "count": .int(count),
            "sum": .double(sum),
            "mean": .double(mean),
            "median": .double(median),
            "min": .double(minimum),
            "max": .double(maximum),
            "sample_standard_deviation": .double(sqrt(sampleVariance))
        ])
    }

    private func unitConvertValue(_ inputs: ScientificValue) throws -> ScientificValue {
        let object = try object(inputs)
        guard let value = object["value"]?.doubleValue,
              let from = object["from"]?.stringValue,
              let to = object["to"]?.stringValue else {
            throw ScientificComputeError.invalidInput("unit_convert requires value, from, to")
        }
        let table: [String: (dimension: String, toBase: Double)] = [
            "m": ("length", 1), "cm": ("length", 0.01), "km": ("length", 1000),
            "s": ("time", 1), "min": ("time", 60), "h": ("time", 3600),
            "m/s": ("speed", 1), "km/h": ("speed", 1000.0 / 3600.0)
        ]
        guard let source = table[from], let target = table[to] else {
            throw ScientificComputeError.invalidInput("unsupported unit conversion: \(from) to \(to)")
        }
        guard source.dimension == target.dimension else {
            throw ScientificComputeError.incompatibleUnits("\(from) and \(to)")
        }
        let converted = value * source.toBase / target.toBase
        return .object([
            "value": .double(converted),
            "unit": .string(to),
            "dimension": .string(source.dimension)
        ])
    }

    private func solveLinearSystemValue(_ inputs: ScientificValue) throws -> ScientificValue {
        let object = try object(inputs)
        guard let matrixValues = object["matrix"]?.arrayValue,
              let vectorValues = object["vector"]?.arrayValue else {
            throw ScientificComputeError.invalidInput("solve_linear_system requires matrix and vector")
        }
        var matrix = try matrixValues.map { rowValue -> [Double] in
            guard let row = rowValue.arrayValue else { throw ScientificComputeError.invalidInput("matrix rows must be arrays") }
            return try row.map {
                guard let number = $0.doubleValue else { throw ScientificComputeError.invalidInput("matrix entries must be numbers") }
                return number
            }
        }
        var vector = try vectorValues.map { value -> Double in
            guard let number = value.doubleValue else { throw ScientificComputeError.invalidInput("vector entries must be numbers") }
            return number
        }
        let n = matrix.count
        guard n > 0, matrix.allSatisfy({ $0.count == n }), vector.count == n else {
            throw ScientificComputeError.invalidInput("matrix must be square and match vector length")
        }

        for pivot in 0..<n {
            var maxRow = pivot
            for row in pivot..<n where abs(matrix[row][pivot]) > abs(matrix[maxRow][pivot]) { maxRow = row }
            guard abs(matrix[maxRow][pivot]) > 1e-12 else { throw ScientificComputeError.singularMatrix }
            if maxRow != pivot {
                matrix.swapAt(maxRow, pivot)
                vector.swapAt(maxRow, pivot)
            }
            for row in (pivot + 1)..<n {
                let factor = matrix[row][pivot] / matrix[pivot][pivot]
                for column in pivot..<n { matrix[row][column] -= factor * matrix[pivot][column] }
                vector[row] -= factor * vector[pivot]
            }
        }

        var solution = Array(repeating: 0.0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var rhs = vector[row]
            for column in (row + 1)..<n { rhs -= matrix[row][column] * solution[column] }
            solution[row] = rhs / matrix[row][row]
        }
        return .object(["solution": .array(solution.map { .double(clean($0)) })])
    }

    private func clean(_ value: Double) -> Double {
        abs(value) < 1e-12 ? 0 : value
    }
}

public struct ScienceComputeTool: AgentTool {
    public let name = "science_compute"
    public let description = "Run deterministic, governed scientific computations such as arithmetic, comparison, units, statistics, and small linear algebra."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = AgentToolInputSchema.object(properties: [
        "operation": .string(description: "Whitelisted scientific operation, e.g. add, compare, unit_convert, summary, solve_linear_system."),
        "inputs": .object(properties: [:], required: []),
        "options": .object(properties: [:], required: [])
    ], required: ["operation", "inputs"])

    private let runtime: ScientificComputeRuntime

    public init(runtime: ScientificComputeRuntime = ScientificComputeRuntime()) {
        self.runtime = runtime
    }

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        guard let operationString = arguments.string("operation"), let operation = ScientificComputeOperation(rawValue: operationString) else {
            throw AgentToolError.invalidArguments("Unsupported or missing operation")
        }
        guard let inputJSON = arguments.values["inputs"] else {
            throw AgentToolError.invalidArguments("Missing inputs")
        }
        let options = parseOptions(arguments.values["options"])
        let request = ScientificComputeRequest(operation: operation, inputs: try ScientificValue(sendableJSON: inputJSON), options: options)
        let result = try await runtime.compute(request)
        let json = try encodeJSON(result)
        return AgentToolResult(
            runID: context.runID,
            sessionID: context.sessionID,
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "Scientific compute \(operation.rawValue) completed with \(result.diagnostics.engine).",
            contentJSON: json
        )
    }

    private func parseOptions(_ value: SendableJSONValue?) -> ScientificComputeOptions {
        guard case .object(let object) = value else { return ScientificComputeOptions() }
        return ScientificComputeOptions(
            absoluteTolerance: object["absolute_tolerance"]?.doubleLikeValue,
            relativeTolerance: object["relative_tolerance"]?.doubleLikeValue,
            preferredEngine: object["preferred_engine"]?.stringValue
        )
    }
}

public struct ScienceUnitsTool: AgentTool {
    public let name = "science_units"
    public let description = "Convert and compare physical units with dimensional validation."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = ScienceComputeTool().inputSchema
    private let runtime: ScientificComputeRuntime
    public init(runtime: ScientificComputeRuntime = ScientificComputeRuntime()) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await ScienceComputeTool(runtime: runtime).execute(arguments: arguments, context: context)
    }
}

public struct ScienceStatsTool: AgentTool {
    public let name = "science_stats"
    public let description = "Compute governed descriptive and statistical operations."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = ScienceComputeTool().inputSchema
    private let runtime: ScientificComputeRuntime
    public init(runtime: ScientificComputeRuntime = ScientificComputeRuntime()) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await ScienceComputeTool(runtime: runtime).execute(arguments: arguments, context: context)
    }
}

public struct ScienceLinalgTool: AgentTool {
    public let name = "science_linalg"
    public let description = "Compute governed linear algebra operations."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = ScienceComputeTool().inputSchema
    private let runtime: ScientificComputeRuntime
    public init(runtime: ScientificComputeRuntime = ScientificComputeRuntime()) { self.runtime = runtime }
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try await ScienceComputeTool(runtime: runtime).execute(arguments: arguments, context: context)
    }
}

public struct ScienceSymbolicTool: AgentTool {
    public let name = "science_symbolic"
    public let description = "Symbolic math entrypoint. Native engine reports unsupported until the Python scientific sidecar is configured."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = ScienceComputeTool().inputSchema
    public init() {}
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        throw AgentToolError.invalidArguments("science_symbolic requires the planned Python/SymPy sidecar engine")
    }
}

public struct ScienceOptimizeTool: AgentTool {
    public let name = "science_optimize"
    public let description = "Optimization entrypoint. Native engine reports unsupported until advanced engines are configured."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = ScienceComputeTool().inputSchema
    public init() {}
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        throw AgentToolError.invalidArguments("science_optimize requires the planned SciPy/Accelerate engine")
    }
}

public struct ScienceTableComputeTool: AgentTool {
    public let name = "science_table_compute"
    public let description = "Table-aware scientific computation entrypoint. Native implementation is intentionally conservative pending DataFrame sidecar support."
    public let permission: AgentPermissionCapability = .computeScientific
    public let inputSchema = ScienceComputeTool().inputSchema
    public init() {}
    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        throw AgentToolError.invalidArguments("science_table_compute requires the planned table compute engine")
    }
}

private extension SendableJSONValue {
    var doubleLikeValue: Double? {
        switch self {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}
