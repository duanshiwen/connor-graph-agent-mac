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

    public static func defaultConnectionName(from rawValue: String, fallback: String, protocolName: String? = nil) -> String {
        let candidate = host(from: rawValue, emptyFallback: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return appendingProtocolName(protocolName, to: fallback) }

        let withoutPort = candidate.split(separator: ":", maxSplits: 1).first.map(String.init) ?? candidate
        let withoutWWW = withoutPort.hasPrefix("www.") ? String(withoutPort.dropFirst(4)) : withoutPort
        if protocolName != nil {
            return appendingProtocolName(protocolName, to: primaryDomainComponent(from: withoutWWW, fallback: fallback))
        }
        let withoutSuffix = removingCommonTopLevelSuffix(from: withoutWWW)
        let normalized = withoutSuffix.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        return normalized.isEmpty ? fallback : normalized
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

    private static func primaryDomainComponent(from host: String, fallback: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 1 else { return host.isEmpty ? fallback : host }
        if labels.allSatisfy({ Int($0) != nil }) { return host }

        let twoLevelSuffixes: Set<String> = ["com.cn", "net.cn", "org.cn", "gov.cn", "co.uk", "org.uk", "com.au", "co.jp"]
        let suffix = labels.suffix(2).joined(separator: ".").lowercased()
        let suffixLabelCount = twoLevelSuffixes.contains(suffix) ? 2 : 1
        let primaryIndex = labels.count - suffixLabelCount - 1
        guard labels.indices.contains(primaryIndex) else { return labels.first ?? fallback }
        return labels[primaryIndex]
    }

    private static func appendingProtocolName(_ protocolName: String?, to baseName: String) -> String {
        let baseName = baseName.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines))
        let protocolName = protocolName?.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespacesAndNewlines)) ?? ""
        guard !baseName.isEmpty else { return protocolName }
        guard !protocolName.isEmpty else { return baseName }
        return "\(baseName).\(protocolName)"
    }
}
