import Foundation
import ConnorGraphCore

/// Anonymization result: the scrubbed transcript plus the participant tokens used
/// in this forward (in first-appearance order, for prompt reinforcement).
public struct ImAnonymizedForward: Sendable, Equatable {
    public var transcriptText: String
    public var tokensUsed: [String]

    public init(transcriptText: String, tokensUsed: [String]) {
        self.transcriptText = transcriptText
        self.tokensUsed = tokensUsed
    }
}

/// A participant's real identity (local only, never sent to the AI): the bound
/// person profile id and the local display name.
public struct ImParticipantInfo: Sendable, Equatable {
    public var personProfileID: String
    public var displayName: String

    public init(personProfileID: String, displayName: String) {
        self.personProfileID = personProfileID
        self.displayName = displayName
    }
}

/// Transcript anonymizer: turns selected IM messages into the transcript sent to
/// the AI, ported one-to-one from the Android `TranscriptAnonymizer`.
/// - Participant identity → persistent opaque token `@CXxxxxxx` (reused per
///   senderId across forwards so knowledge accumulates consistently);
/// - the user's own messages become `我：` (self identity is not anonymized);
/// - message bodies get local regex PII scrubbing (phone/email/ID card/bank
///   card) and participant real names are replaced with their tokens.
/// Purely local and deterministic; tokens share the `ImAliasTokens` definition
/// with projection-side resolution.
public struct ImTranscriptAnonymizer: Sendable {
    private let store: any ImStore
    private let now: @Sendable () -> Int64
    private let generateToken: @Sendable () -> String

    public init(
        store: any ImStore,
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
        generateToken: @escaping @Sendable () -> String = { Self.randomToken() }
    ) {
        self.store = store
        self.now = now
        self.generateToken = generateToken
    }

    /// Allocate (or reuse) a participant token: an existing alias for the same
    /// `senderId` is reused verbatim, otherwise a store-unique random token is
    /// generated and persisted. One participant keeps one token across forwards.
    public func allocateAlias(
        senderId: Int64,
        conversationId: String,
        personProfileID: String,
        displayName: String
    ) async throws -> String {
        if let existing = try await store.aliasBySender(senderId: senderId) {
            return existing.aliasToken
        }
        var token = generateToken()
        while try await store.aliasByToken(token) != nil { token = generateToken() }
        try await store.insertAlias(ImForwardAlias(
            aliasToken: token,
            senderId: senderId,
            imConversationId: conversationId,
            personProfileID: personProfileID,
            displayName: displayName,
            createdAt: now()
        ))
        return token
    }

    /// Anonymize the selected messages. `friendLookup` is supplied by the caller:
    /// senderId → bound person info; nil means the sender has no bound person
    /// (e.g. a non-friend group member), in which case an ephemeral non-persisted
    /// token is used — projection then degrades to a plain name without blocking
    /// the remaining facts.
    public func anonymize(
        messages: [ImMessage],
        conversation: ImConversation,
        selfUserId: Int64,
        friendLookup: @Sendable (Int64) async -> ImParticipantInfo?
    ) async throws -> ImAnonymizedForward {
        var tokensUsed: [String] = []
        var tokensSeen = Set<String>()
        var tokenBySender: [Int64: String] = [:]
        // Body replacement table: real name → token (applied longest-first to
        // avoid substring mis-replacement).
        var nameToToken: [String: String] = [:]
        var ephemeral: [Int64: String] = [:]

        var otherSenderIds: [Int64] = []
        for message in messages where message.senderId != selfUserId {
            if !otherSenderIds.contains(message.senderId) { otherSenderIds.append(message.senderId) }
        }
        for senderId in otherSenderIds {
            let info = await friendLookup(senderId)
            let token: String
            if let info {
                token = try await allocateAlias(
                    senderId: senderId,
                    conversationId: conversation.id,
                    personProfileID: info.personProfileID,
                    displayName: info.displayName
                )
            } else if let existing = ephemeral[senderId] {
                token = existing
            } else {
                token = uniqueEphemeralToken(used: tokensSeen)
                ephemeral[senderId] = token
            }
            tokenBySender[senderId] = token
            if tokensSeen.insert(token).inserted { tokensUsed.append(token) }
            if let name = info?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                nameToToken[name] = token
            }
            if let senderName = messages.first(where: { $0.senderId == senderId })?.senderName
                .trimmingCharacters(in: .whitespacesAndNewlines), !senderName.isEmpty, nameToToken[senderName] == nil {
                nameToToken[senderName] = token
            }
        }

        let orderedNames = nameToToken.keys.sorted { $0.count > $1.count }
        let lines = messages.map { message -> String in
            var body = Self.scrubPii(message.content)
            for name in orderedNames {
                body = body.replacingOccurrences(of: name, with: nameToToken[name]!)
            }
            if message.senderId == selfUserId {
                return "我：\(body)"
            }
            return "\(tokenBySender[message.senderId] ?? "")：\(body)"
        }
        return ImAnonymizedForward(transcriptText: lines.joined(separator: "\n"), tokensUsed: tokensUsed)
    }

    // MARK: - PII scrubbing

    /// Local PII regex scrubbing: phone / email / ID card / bank card → mask.
    /// Order matters: ID card (18 digits) must run before bank card (16-19
    /// digits) so an 18-digit ID number is not consumed as a bank card.
    public static func scrubPii(_ raw: String) -> String {
        var text = raw
        text = replaceMatches(in: text, pattern: "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}")
        text = replaceMatches(in: text, pattern: "\\d{17}[\\dXx]")
        text = replaceMatches(in: text, pattern: "\\d{16,19}")
        text = replaceMatches(in: text, pattern: "1[3-9]\\d{9}")
        return text
    }

    private static let mask = "「[已隐藏]」"

    private static func replaceMatches(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: mask)
    }

    // MARK: - Token generation

    public static func randomToken() -> String {
        let hexDigits = Array("0123456789ABCDEF")
        let suffix = (0..<ImAliasTokens.hexDigitCount).map { _ in hexDigits.randomElement()! }
        return ImAliasTokens.tokenPrefix + String(suffix)
    }

    private func uniqueEphemeralToken(used: Set<String>) -> String {
        var token = generateToken()
        while used.contains(token) { token = generateToken() }
        return token
    }
}
