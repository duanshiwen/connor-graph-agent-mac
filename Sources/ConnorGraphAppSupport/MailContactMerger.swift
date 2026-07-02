import Foundation
import ConnorGraphCore

/// 联系人合并服务
public struct MailContactMerger: Sendable {
    public init() {}

    /// 合并两个联系人
    public func merge(_ existing: MailContact, with new: MailContact) -> MailContact {
        var merged = existing
        merged.frequency += new.frequency
        merged.sources.formUnion(new.sources)

        // 更新时间
        if let newLast = new.lastContactedAt {
            if let existingLast = existing.lastContactedAt {
                if newLast > existingLast {
                    merged.lastContactedAt = newLast
                }
            } else {
                merged.lastContactedAt = newLast
            }
        }

        if new.lastSeenAt > existing.lastSeenAt {
            merged.lastSeenAt = new.lastSeenAt
        }

        if new.firstSeenAt < existing.firstSeenAt {
            merged.firstSeenAt = new.firstSeenAt
        }

        // 保留更完整的显示名
        if merged.displayName == nil || merged.displayName?.isEmpty == true {
            merged.displayName = new.displayName
        }

        return merged
    }

    /// 合并联系人列表
    public func mergeContacts(_ existing: [MailContact], with new: [MailContact]) -> [MailContact] {
        var contactMap: [String: MailContact] = [:]

        // 添加现有联系人
        for contact in existing {
            contactMap[contact.email] = contact
        }

        // 合并新联系人
        for contact in new {
            if let existingContact = contactMap[contact.email] {
                contactMap[contact.email] = merge(existingContact, with: contact)
            } else {
                contactMap[contact.email] = contact
            }
        }

        return Array(contactMap.values)
    }

    /// 合并多个联系人列表
    public func mergeMultiple(_ lists: [[MailContact]]) -> [MailContact] {
        var result: [MailContact] = []
        for list in lists {
            result = mergeContacts(result, with: list)
        }
        return result
    }

    /// 按频率排序
    public func sortByFrequency(_ contacts: [MailContact]) -> [MailContact] {
        contacts.sorted { $0.frequency > $1.frequency }
    }

    /// 按最近联系时间排序
    public func sortByLastContact(_ contacts: [MailContact]) -> [MailContact] {
        contacts.sorted { 
            let date1 = $0.lastContactedAt ?? $0.lastSeenAt
            let date2 = $1.lastContactedAt ?? $1.lastSeenAt
            return date1 > date2
        }
    }

    /// 过滤低频联系人
    public func filterByFrequency(_ contacts: [MailContact], minFrequency: Int) -> [MailContact] {
        contacts.filter { $0.frequency >= minFrequency }
    }

    /// 搜索联系人
    public func search(_ contacts: [MailContact], query: String) -> [MailContact] {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return contacts }

        return contacts.filter { contact in
            contact.email.lowercased().contains(normalized) ||
            (contact.displayName?.lowercased().contains(normalized) ?? false)
        }
    }
}
