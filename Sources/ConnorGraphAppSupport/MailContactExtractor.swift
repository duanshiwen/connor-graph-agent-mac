import Foundation
import ConnorGraphCore

/// 从邮件消息中提取联系人
public struct MailContactExtractor: Sendable {
    public init() {}

    /// 从单封邮件中提取联系人
    public func extract(from message: MailMessageSummary) -> [MailContact] {
        var contacts: [MailContact] = []

        // 1. 提取 From
        if let contact = extractAddress(message.from, source: .from, date: message.date) {
            contacts.append(contact)
        }

        // 2. 提取 To
        for to in message.to {
            if let contact = extractAddress(to, source: .to, date: message.date) {
                contacts.append(contact)
            }
        }

        // 3. 提取 Cc
        for cc in message.cc {
            if let contact = extractAddress(cc, source: .cc, date: message.date) {
                contacts.append(contact)
            }
        }

        return contacts
    }

    /// 从多封邮件中提取联系人（批量处理）
    public func extract(from messages: [MailMessageSummary]) -> [MailContact] {
        var contactMap: [String: MailContact] = [:]

        for message in messages {
            let contacts = extract(from: message)
            for contact in contacts {
                if let existing = contactMap[contact.email] {
                    contactMap[contact.email] = mergeContacts(existing, with: contact)
                } else {
                    contactMap[contact.email] = contact
                }
            }
        }

        return Array(contactMap.values)
    }

    /// 提取单个地址
    private func extractAddress(_ address: MailAddress, source: ContactSource, date: Date) -> MailContact? {
        let email = address.email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, email.contains("@") else { return nil }

        // 验证邮箱格式
        let emailRegex = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        guard email.range(of: emailRegex, options: .regularExpression) != nil else { return nil }

        return MailContact(
            id: MailContactID(rawValue: email),
            email: email,
            displayName: address.name,
            frequency: 1,
            lastContactedAt: date,
            firstSeenAt: date,
            lastSeenAt: date,
            sources: [source]
        )
    }

    /// 合并两个联系人
    private func mergeContacts(_ existing: MailContact, with new: MailContact) -> MailContact {
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
}
