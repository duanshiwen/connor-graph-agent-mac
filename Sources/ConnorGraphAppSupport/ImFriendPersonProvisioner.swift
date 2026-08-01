import Foundation
import ConnorGraphCore

/// Auto-provisions a local person profile for every Connor-system friend, so the
/// merged 人际关系 registry always contains a person for each friend. Friends that
/// already carry a valid `personProfileID` binding are reused; otherwise a stable,
/// friend-derived profile is created and the friend row is bound to it. Chat
/// capability remains owned by the friend store and is never duplicated on the
/// person profile.
public struct ImFriendPersonProvisioner: Sendable {
    public static let connorFriendSource = "connorFriend"
    public static let connorFriendDiscoverer = "connor-friend"
    public static func profileID(for userID: Int64) -> ContactID {
        ContactID(rawValue: "connor-friend-\(userID)")
    }

    private let profileStore: (any PersonProfileStore)?
    private let imStore: (any ImStore)
    private let now: @Sendable () -> Int64

    public init(
        profileStore: (any PersonProfileStore)?,
        imStore: (any ImStore),
        now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }
    ) {
        self.profileStore = profileStore
        self.imStore = imStore
        self.now = now
    }

    /// Reconciles every friend row with a local person profile. Returns the
    /// reconciled friend rows (with `personProfileID` populated where possible).
    /// Without a profile store the input is returned unchanged (demo / degraded mode).
    @discardableResult
    public func reconcile(friends: [ImFriend]) async throws -> [ImFriend] {
        guard let profileStore else { return friends }
        var profilesByID = Dictionary(
            uniqueKeysWithValues: try await profileStore.loadProfiles(includeInactive: true).map { ($0.id, $0) }
        )
        var reconciled: [ImFriend] = []
        reconciled.reserveCapacity(friends.count)
        for friend in friends {
            if let boundID = friend.personProfileID.map(ContactID.init(rawValue:)),
               let resolved = resolveActiveProfile(from: boundID, profilesByID: profilesByID) {
                if resolved.id != boundID {
                    try await bind(friend: friend, personProfileID: resolved.id.rawValue)
                }
                var updated = friend
                updated.personProfileID = resolved.id.rawValue
                reconciled.append(updated)
                continue
            }

            let stableID = Self.profileID(for: friend.userId)
            if let existing = resolveActiveProfile(from: stableID, profilesByID: profilesByID) {
                try await bind(friend: friend, personProfileID: existing.id.rawValue)
                var updated = friend
                updated.personProfileID = existing.id.rawValue
                reconciled.append(updated)
                continue
            }

            if let existing = uniqueEmailMatch(for: friend, profilesByID: profilesByID) {
                try await bind(friend: friend, personProfileID: existing.id.rawValue)
                var updated = friend
                updated.personProfileID = existing.id.rawValue
                reconciled.append(updated)
                continue
            }

            let profile = makeProfile(for: friend)
            _ = try await profileStore.upsert(profile)
            profilesByID[profile.id] = profile
            try await bind(friend: friend, personProfileID: profile.id.rawValue)
            var updated = friend
            updated.personProfileID = profile.id.rawValue
            reconciled.append(updated)
        }
        return reconciled
    }

    private func bind(friend: ImFriend, personProfileID: String) async throws {
        try await imStore.bindFriendPerson(userId: friend.userId, personProfileID: personProfileID, now: now())
    }

    private func makeProfile(for friend: ImFriend) -> PersonProfile {
        let emails = friend.email.trimmingCharacters(in: .whitespacesAndNewlines)
        return PersonProfile(
            id: Self.profileID(for: friend.userId),
            displayName: friend.displayName,
            emails: emails.isEmpty ? [] : [ContactEmailAddress(email: emails)],
            source: Self.connorFriendSource,
            discoveredBy: Self.connorFriendDiscoverer
        )
    }

    private func resolveActiveProfile(
        from initialID: ContactID,
        profilesByID: [ContactID: PersonProfile]
    ) -> PersonProfile? {
        var currentID = initialID
        var visited = Set<ContactID>()
        while visited.insert(currentID).inserted, let profile = profilesByID[currentID] {
            switch profile.status {
            case .active, .pending:
                return profile
            case .merged:
                guard let mergedIntoID = profile.mergedIntoID else { return nil }
                currentID = mergedIntoID
            case .deleted:
                return nil
            }
        }
        return nil
    }

    private func uniqueEmailMatch(
        for friend: ImFriend,
        profilesByID: [ContactID: PersonProfile]
    ) -> PersonProfile? {
        let email = friend.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !email.isEmpty else { return nil }
        let matches = profilesByID.values.filter { profile in
            profile.isActiveForDefaultContext
                && profile.emails.contains {
                    $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email
                }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
