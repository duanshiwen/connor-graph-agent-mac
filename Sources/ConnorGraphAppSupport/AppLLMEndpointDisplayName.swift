import Foundation

public enum AppLLMEndpointDisplayName {
    public static func host(from rawValue: String, emptyFallback: String = "未设置 endpoint") -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return emptyFallback }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }
        return fallbackHost(from: trimmed) ?? trimmed
    }

    public static func defaultConnectionName(from rawValue: String, fallback: String) -> String {
        let candidate = host(from: rawValue, emptyFallback: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return fallback.trimmingCharacters(in: .whitespacesAndNewlines) }

        let withoutPort = candidate.split(separator: ":", maxSplits: 1).first.map(String.init) ?? candidate
        let withoutWWW = withoutPort.hasPrefix("www.") ? String(withoutPort.dropFirst(4)) : withoutPort
        let withoutSuffix = removingCommonTopLevelSuffix(from: withoutWWW)
        let normalized = withoutSuffix.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return normalized.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
    }

    private static func fallbackHost(from trimmed: String) -> String? {
        let withoutScheme = trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return withoutScheme
            .split(separator: "/")
            .first
            .map(String.init)
    }

    private static func removingCommonTopLevelSuffix(from host: String) -> String {
        let suffixes = [".com", ".cn", ".run", ".ai", ".sh", ".chat", ".co", ".io", ".org", ".net"]
        for suffix in suffixes where host.hasSuffix(suffix) {
            return String(host.dropLast(suffix.count))
        }
        return host
    }
}
