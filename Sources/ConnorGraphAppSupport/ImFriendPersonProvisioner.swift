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
            let stableID = Self.profileID(for: friend.userId)
            if let boundID = friend.personProfileID.map(ContactID.init(rawValue:)),
               let resolved = resolveActiveProfile(from: boundID, profilesByID: profilesByID) {
                if resolved.id != boundID {
                    try await bind(friend: friend, personProfileID: resolved.id.rawValue)
                }
                // 好友已绑定到某个人物（而非其自动建档的 connor-friend-* 档案）：
                // 把自动建档档案并入目标人物，让人际关系列表只显示合并后的人物，
                // 好友信息（姓名/邮箱等）保留在目标档案里而不是作为独立行残留。
                try await mergeAutoProvisionedProfileIfNeeded(
                    stableID: stableID,
                    resolvedID: resolved.id,
                    profilesByID: &profilesByID
                )
                var updated = friend
                updated.personProfileID = resolved.id.rawValue
                reconciled.append(updated)
                continue
            }

            if let existing = resolveActiveProfile(from: stableID, profilesByID: profilesByID) {
                try await bind(friend: friend, personProfileID: existing.id.rawValue)
                var updated = friend
                updated.personProfileID = existing.id.rawValue
                reconciled.append(updated)
                continue
            }

            if let existing = uniqueEmailMatch(for: friend, profilesByID: profilesByID) {
                try await bind(friend: friend, personProfileID: existing.id.rawValue)
                try await mergeAutoProvisionedProfileIfNeeded(
                    stableID: stableID,
                    resolvedID: existing.id,
                    profilesByID: &profilesByID
                )
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

    /// 好友已绑定到某个「非自动建档」人物时，把自动建档档案（connor-friend-<id>）并入目标人物：
    /// 源档案标记 merged → 不再作为独立行出现，其姓名/邮箱等并入目标档案；好友记录本身不删除。
    /// 若自动建档档案已合并/已删除，或与目标相同，则不重复操作。
    private func mergeAutoProvisionedProfileIfNeeded(
        stableID: ContactID,
        resolvedID: ContactID,
        profilesByID: inout [ContactID: PersonProfile]
    ) async throws {
        guard stableID != resolvedID, let profileStore else { return }
        guard let source = profilesByID[stableID], source.isActiveForDefaultContext else { return }
        _ = try await profileStore.merge(sourceID: stableID, targetID: resolvedID, now: Date())
        // 合并后源档案不再是 active，目标档案内容已更新，刷新本地快照。
        profilesByID[stableID] = nil
        if let mergedTarget = try await profileStore.profile(id: resolvedID) {
            profilesByID[resolvedID] = mergedTarget
        }
    }

    private func bind(friend: ImFriend, personProfileID: String) async throws {
        try await imStore.bindFriendPerson(userId: friend.userId, personProfileID: personProfileID, now: now())
    }

    /// 跨端合并回放：安卓端把好友并入人物时，会把好友账号写入该人物 L4 实体的
    /// metadata（connor_friend_*，随 memory_l4_entities 同步）。本机在收到这些实体后，
    /// 把本地好友重新绑定到对应人物档案，并把好友的自动建档档案并入目标人物，
    /// 让人际关系列表与安卓一致地呈现「好友并入人物」。
    ///
    /// 只处理能唯一匹配的情况：好友必须存在于本地；目标人物按 memoryEntityID 精确匹配，
    /// 否则按规范化显示名唯一匹配（active 档案）。无法唯一匹配时跳过，不做臆测性合并。
    @discardableResult
    public func reconcileSyncedFriendBindings(entities: [MemoryOSEntity]) async throws -> Int {
        guard let profileStore else { return 0 }
        let boundEntities = entities.filter {
            $0.entityType == MemoryOSEntityType.person.rawValue && $0.metadata["connor_friend_user_id"] != nil
        }
        guard !boundEntities.isEmpty else { return 0 }

        let friends = try await imStore.loadFriends()
        let allProfiles = try await profileStore.loadProfiles(includeInactive: true)
        var applied = 0
        for entity in boundEntities {
            guard let rawUserID = entity.metadata["connor_friend_user_id"],
                  let userID = Int64(rawUserID),
                  let friend = friends.first(where: { $0.userId == userID }) else { continue }
            guard let target = Self.resolveTargetProfile(for: entity, profiles: allProfiles) else { continue }
            let stableID = Self.profileID(for: userID)
            guard stableID != target.id else { continue }

            if friend.personProfileID != target.id.rawValue {
                try await bind(friend: friend, personProfileID: target.id.rawValue)
            }
            if let source = allProfiles.first(where: { $0.id == stableID }),
               source.isActiveForDefaultContext {
                _ = try await profileStore.merge(sourceID: stableID, targetID: target.id, now: Date())
            }
            applied += 1
        }
        return applied
    }

    /// 在本地人物档案中定位与 L4 person 实体对应的人物：先按 memory_entity_id 精确匹配，
    /// 再按规范化显示名唯一匹配（排除已合并/已删除档案）。
    private static func resolveTargetProfile(for entity: MemoryOSEntity, profiles: [PersonProfile]) -> PersonProfile? {
        if let exact = profiles.first(where: {
            ($0.memoryEntityID != nil && $0.memoryEntityID == entity.id) || ($0.memoryStableKey != nil && $0.memoryStableKey == entity.stableKey)
        }) {
            return exact.isActiveForDefaultContext ? exact : nil
        }
        let candidates = profiles.filter {
            $0.isActiveForDefaultContext && Self.normalizedName($0.displayName) == Self.normalizedName(entity.name)
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func normalizedName(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
