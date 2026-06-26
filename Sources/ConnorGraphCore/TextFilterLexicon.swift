import Foundation

public enum TextFilterLanguage: String, Codable, Sendable, Hashable {
    case english
    case chinese
    case mixed
    case unknown
}

public enum TextFilterCategory: String, Codable, Sendable, Hashable {
    case functionWord
    case pronoun
    case conjunction
    case preposition
    case modal
    case questionWord
    case quantifier
    case temporalFiller
    case genericVerb
    case englishStopWord
}

public enum TextFilterAction: String, Codable, Sendable, Hashable {
    case keep
    case softDemote
    case dropForDisplay
    case dropForQuery
}

public enum TextFilterContext: String, Codable, Sendable, Hashable {
    case searchQuery
    case searchDisplay
    case listFilter
    case indexing
    case llmContext
}

public struct TextFilterEntry: Codable, Sendable, Equatable, Hashable {
    public var term: String
    public var language: TextFilterLanguage
    public var categories: Set<TextFilterCategory>
    public var defaultAction: TextFilterAction
    public var weightMultiplier: Double
    public var preserveInPhrase: Bool
    public var notes: String?

    public init(
        term: String,
        language: TextFilterLanguage,
        categories: Set<TextFilterCategory>,
        defaultAction: TextFilterAction = .softDemote,
        weightMultiplier: Double = 0.1,
        preserveInPhrase: Bool = true,
        notes: String? = nil
    ) {
        self.term = term
        self.language = language
        self.categories = categories
        self.defaultAction = defaultAction
        self.weightMultiplier = weightMultiplier
        self.preserveInPhrase = preserveInPhrase
        self.notes = notes
    }
}

public struct TextFilterLexicon: Sendable {
    public static let `default` = TextFilterLexicon(entries: Self.defaultEntries)

    private let entriesByTerm: [String: TextFilterEntry]

    public init(entries: [TextFilterEntry]) {
        var mapped: [String: TextFilterEntry] = [:]
        for entry in entries {
            let key = Self.normalized(entry.term)
            guard !key.isEmpty else { continue }
            var normalizedEntry = entry
            normalizedEntry.term = key
            mapped[key] = normalizedEntry
        }
        self.entriesByTerm = mapped
    }

    public func entry(for term: String) -> TextFilterEntry? {
        entriesByTerm[Self.normalized(term)]
    }

    public func contains(_ term: String) -> Bool {
        entry(for: term) != nil
    }

    public func action(for term: String, context: TextFilterContext) -> TextFilterAction {
        guard let entry = entry(for: term) else { return .keep }
        switch context {
        case .indexing:
            return .keep
        case .searchQuery, .listFilter:
            return entry.defaultAction == .dropForQuery ? .dropForQuery : .softDemote
        case .searchDisplay:
            if entry.defaultAction == .dropForQuery { return .dropForQuery }
            if entry.categories.contains(.temporalFiller)
                || entry.categories.contains(.questionWord)
                || entry.categories.contains(.quantifier)
                || entry.categories.contains(.genericVerb)
                || entry.categories.contains(.modal)
                || entry.categories.contains(.functionWord)
                || entry.categories.contains(.pronoun)
                || entry.categories.contains(.conjunction)
                || entry.categories.contains(.preposition) {
                return .dropForDisplay
            }
            return entry.defaultAction
        case .llmContext:
            return entry.defaultAction
        }
    }

    public func weightMultiplier(for term: String, context: TextFilterContext) -> Double {
        guard let entry = entry(for: term) else { return 1 }
        return action(for: term, context: context) == .keep ? 1 : entry.weightMultiplier
    }

    private static func normalized(_ term: String) -> String {
        term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let defaultEntries: [TextFilterEntry] = {
        var entries: [TextFilterEntry] = []

        func add(_ terms: [String], language: TextFilterLanguage, categories: Set<TextFilterCategory>, weight: Double = 0.1) {
            for term in terms {
                entries.append(TextFilterEntry(term: term, language: language, categories: categories, weightMultiplier: weight))
            }
        }

        add(["a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "for", "with", "by", "at", "from", "is", "are", "was", "were", "be", "been", "being", "this", "that", "these", "those", "about", "into", "as"], language: .english, categories: [.englishStopWord])
        add(["的", "了", "着", "过", "吗", "呢", "啊", "呀", "吧", "么", "得", "地", "所"], language: .chinese, categories: [.functionWord])
        add(["我", "你", "他", "她", "它", "我们", "你们", "他们", "她们", "它们", "这个", "那个", "这些", "那些", "这里", "那里"], language: .chinese, categories: [.pronoun])
        add(["和", "与", "或", "以及", "并且", "但是", "然后", "因为", "所以", "如果"], language: .chinese, categories: [.conjunction])
        add(["在", "从", "到", "对", "向", "把", "被", "给", "关于", "对于", "里面", "之间"], language: .chinese, categories: [.preposition])
        add(["可以", "需要", "应该", "可能", "能够", "必须", "想要"], language: .chinese, categories: [.modal], weight: 0.2)
        add(["什么", "为什么", "怎么", "怎样", "如何", "哪里", "哪个", "哪些", "多少", "几", "几个", "是否", "有没有"], language: .chinese, categories: [.questionWord], weight: 0.2)
        add(["个", "些", "种", "条", "件", "本", "次", "家", "位", "名", "份", "张", "只", "项", "段", "篇", "组", "批", "类", "一个", "一些", "一下", "一点"], language: .chinese, categories: [.quantifier], weight: 0.15)
        add(["今天", "明天", "后天", "昨天", "前天", "现在", "当前", "时候", "时间", "日期", "星期", "周", "月份", "年份", "上午", "下午", "晚上", "中午"], language: .chinese, categories: [.temporalFiller], weight: 0.25)
        add(["去", "来", "做", "看", "找", "查", "搜", "问", "帮", "帮我", "告诉", "介绍", "想", "知道"], language: .chinese, categories: [.genericVerb], weight: 0.25)
        return entries
    }()
}
