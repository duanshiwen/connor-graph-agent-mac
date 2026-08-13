import Foundation
import ConnorGraphCore

/// 邮件正文后台回填服务。
///
/// 列表同步只拉取信封/头部与摘要（不含正文），因此本地缓存里大量邮件没有可搜索的正文。
/// 本服务在同步完成后排队下载这些邮件的正文：只保存解析出的纯文本 / HTML 文本，
/// 不落盘附件、图片、多媒体等二进制内容，避免本地存储膨胀；写回缓存时同步更新搜索索引，
/// 让聚合搜索可以按正文命中（包括已发送文件夹里的邮件）。
///
/// 性能设计：
/// - 默认走 MailCore2 批量拉取：每个邮箱文件夹只建立一个 IMAP 会话，串行拉取该文件夹
///   内缺少正文的邮件，避免“一封邮件一个连接”造成的服务器与网络开销；
/// - 批量失败或 MailCore2 不可用时，退回逐封拉取（受 `maxConcurrentFetches` 限制）；
/// - 调用方应把本服务放在后台低优先级任务中执行（App 内由 `MailFeatureModel` 以
///   detached utility task 调用），不在主线程/主 actor 上运行。
public struct MailBodyBackfillService: Sendable {
    public var credentialStore: AppMailCredentialStore
    /// 每批从数据库取出的邮件数量（按时间倒序取最新）。
    /// 回填会分页持续处理，直到本地缓存中不再有缺正文的邮件为止（可被取消）。
    public var maxBodiesPerRun: Int
    /// 逐封退回路径的最大并发拉取数，避免同时开太多 IMAP 连接。
    public var maxConcurrentFetches: Int
    /// 可注入的批量拉取实现；为 nil 时在 MailCore2 可用时走内置批量实现。
    /// 返回数组与传入的 `[MailMessageDetail]` 顺序一致，元素为 nil 表示该封未拉到正文。
    public var batchBodyFetcher: (@Sendable (MailAccount, MailMailbox, [MailMessageDetail]) async throws -> [MailMessageDetail?])?
    /// 可注入的逐封拉取实现（默认走 MailIMAPInitialSyncService，MailCore2 优先）。
    public var bodyFetcher: @Sendable (MailAccount, MailMailbox?, MailMessageDetail) async throws -> MailMessageDetail?

    public init(
        credentialStore: AppMailCredentialStore = AppMailCredentialStore(),
        maxBodiesPerRun: Int = 500,
        maxConcurrentFetches: Int = 2,
        batchBodyFetcher: (@Sendable (MailAccount, MailMailbox, [MailMessageDetail]) async throws -> [MailMessageDetail?])? = nil,
        bodyFetcher: (@Sendable (MailAccount, MailMailbox?, MailMessageDetail) async throws -> MailMessageDetail?)? = nil
    ) {
        self.credentialStore = credentialStore
        self.maxBodiesPerRun = maxBodiesPerRun
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
        self.batchBodyFetcher = batchBodyFetcher
        self.bodyFetcher = bodyFetcher ?? Self.defaultBodyFetcher(credentialStore: credentialStore)
    }

    /// 找出本地缓存中缺少可显示正文的邮件，分页排队拉取并写回，直到全部处理完
    /// （或达到 `limit` 总数限制；为 nil 表示处理所有缺正文的邮件）。
    ///
    /// 保证性：
    /// - 每处理完一批会重新查询“仍缺正文”的邮件，所以已经同步过的几千封旧邮件也会被
    ///   逐批覆盖，不会只拉最新的 200 封；
    /// - 分页之间检查 `Task.isCancelled`，应用退出/关闭时会立即停止；
    /// - 单封或单批失败不会中断整体，失败邮件保留在缺正文集合里，下次运行再试；
    /// - 某一批完全没有任何成功（例如服务器持续失败）时停止本轮，避免空转。
    public func backfillMissingBodies(store: FileBackedMailSourceStore, limit: Int? = nil) async throws -> Int {
        let accounts = try await store.listAccounts()
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        var mailboxByID: [MailMailboxID: MailMailbox] = [:]
        for account in accounts {
            for mailbox in try await store.listMailboxes(accountID: account.id) {
                mailboxByID[mailbox.id] = mailbox
            }
        }

        let pageSize = max(1, min(maxBodiesPerRun, 500))
        var savedCount = 0
        var processed = 0
        // 本轮已经尝试过的邮件 ID：失败的不在本轮内重复重试，留到下次运行。
        var attemptedIDs = Set<String>()
        while !Task.isCancelled {
            let remaining = limit.map { $0 - processed } ?? Int.max
            guard remaining > 0 else { break }
            let candidates = try await store.messagesMissingBody(limit: min(pageSize, remaining))
            let pendingCandidates = candidates.filter { !attemptedIDs.contains($0.id.rawValue) }
            guard !pendingCandidates.isEmpty else { break }
            attemptedIDs.formUnion(pendingCandidates.map(\.id.rawValue))
            processed += pendingCandidates.count

            let saved = try await processBatch(
                candidates: pendingCandidates,
                accountByID: accountByID,
                mailboxByID: mailboxByID,
                store: store
            )
            savedCount += saved

            // 本批没有任何成功时停止，避免对同一批失败邮件无限重试。
            if saved == 0 { break }
        }

        if savedCount > 0 {
            // 让邮件列表/正文展示感知到回填完成（搜索索引已在 saveMessage 内同步更新）。
            NotificationCenter.default.post(
                name: .connorMailCacheDidChange,
                object: nil,
                userInfo: [MailCacheChangeNotificationUserInfoKey.reason: MailCacheChangeReason.bodyBackfilled.rawValue]
            )
        }
        return savedCount
    }

    private func processBatch(
        candidates: [MailMessageDetail],
        accountByID: [MailAccountID: MailAccount],
        mailboxByID: [MailMailboxID: MailMailbox],
        store: FileBackedMailSourceStore
    ) async throws -> Int {
        let grouped = Dictionary(grouping: candidates, by: { $0.summary.mailboxID })
        var savedCount = 0
        for (mailboxID, group) in grouped {
            guard let first = group.first, let account = accountByID[first.summary.accountID] else { continue }
            let mailbox = mailboxByID[mailboxID]
            var pending = group

            // 1) 批量路径：每个文件夹一个 IMAP 会话
            if let mailbox,
               let fetched = try? await batchFetch(account: account, mailbox: mailbox, details: pending) {
                var savedIDs: Set<MailMessageID> = []
                for (detail, result) in zip(pending, fetched) {
                    guard let result, MailBodyOnDemandFetchPlanner.hasDisplayableBody(result) else { continue }
                    var merged = detail
                    merged.body = result.body
                    do {
                        try await store.saveMessage(merged)
                        savedIDs.insert(detail.id)
                    } catch {
                        NSLog("[Connor.Mail] body backfill save failed: id=%@, error=%@", detail.id.rawValue, error.localizedDescription)
                    }
                }
                savedCount += savedIDs.count
                pending = pending.filter { !savedIDs.contains($0.id) }
            }

            // 2) 逐封退回路径：批量不可用或未覆盖的邮件
            if !pending.isEmpty {
                savedCount += try await fetchOneByOne(account: account, mailbox: mailbox, details: pending, store: store)
            }
        }
        return savedCount
    }

    private func batchFetch(account: MailAccount, mailbox: MailMailbox, details: [MailMessageDetail]) async throws -> [MailMessageDetail?] {
        if let batchBodyFetcher {
            return try await batchBodyFetcher(account, mailbox, details)
        }
        guard MailCore2Availability.isAvailable,
              let binding = account.credentialBinding,
              let password = try credentialStore.readCredential(binding: binding),
              !password.isEmpty else {
            return []
        }
        let remoteMailbox = RemoteIMAPMailbox(name: mailbox.name, path: mailbox.path, role: mailbox.role)
        let uidPairs = details.compactMap { detail -> (MailMessageID, String)? in
            guard let uid = remoteMailbox.uid(fromMessageID: detail.id, accountID: account.id) else { return nil }
            return (detail.id, uid)
        }
        guard !uidPairs.isEmpty else { return [] }
        let email = account.identities.first?.address.email ?? ""
        let fetched = try await MailCore2MailBackend().fetchMessageBodies(
            account: account,
            credential: password,
            mailbox: remoteMailbox,
            uids: uidPairs.map(\.1),
            fallbackRecipient: MailAddress(email: email),
            snippet: details.first?.summary.snippet ?? ""
        )
        let byID = Dictionary(uniqueKeysWithValues: zip(uidPairs.map(\.0), fetched))
        return details.map { byID[$0.id] ?? nil }
    }

    private func fetchOneByOne(account: MailAccount, mailbox: MailMailbox?, details: [MailMessageDetail], store: FileBackedMailSourceStore) async throws -> Int {
        var savedCount = 0
        let concurrency = max(1, maxConcurrentFetches)
        for chunkStart in stride(from: 0, to: details.count, by: concurrency) {
            let chunk = Array(details[chunkStart..<min(chunkStart + concurrency, details.count)])
            let fetched: [MailMessageDetail?]
            do {
                fetched = try await withThrowingTaskGroup(of: MailMessageDetail?.self) { group in
                    let bodyFetcher = self.bodyFetcher
                    for detail in chunk {
                        group.addTask { [bodyFetcher] in
                            try? await bodyFetcher(account, mailbox, detail)
                        }
                    }
                    var results: [MailMessageDetail?] = []
                    for try await result in group {
                        results.append(result)
                    }
                    return results
                }
            } catch {
                continue
            }
            for (detail, result) in zip(chunk, fetched) {
                guard let result, MailBodyOnDemandFetchPlanner.hasDisplayableBody(result) else { continue }
                var merged = detail
                merged.body = result.body
                do {
                    try await store.saveMessage(merged)
                    savedCount += 1
                } catch {
                    NSLog("[Connor.Mail] body backfill save failed: id=%@, error=%@", detail.id.rawValue, error.localizedDescription)
                }
            }
        }
        return savedCount
    }

    private static func defaultBodyFetcher(credentialStore: AppMailCredentialStore) -> @Sendable (MailAccount, MailMailbox?, MailMessageDetail) async throws -> MailMessageDetail? {
        { account, mailbox, detail in
            let path = mailbox?.path ?? "INBOX"
            let role = mailbox?.role ?? .inbox
            let remoteMailbox = RemoteIMAPMailbox(name: mailbox?.name ?? "INBOX", path: path, role: role)
            guard let uid = remoteMailbox.uid(fromMessageID: detail.id, accountID: account.id), !uid.isEmpty else {
                return nil
            }
            let service = MailIMAPInitialSyncService(credentialStore: credentialStore, messageLimit: 0)
            return try await service.fetchMessageBody(
                account: account,
                uid: uid,
                messageID: detail.id,
                mailboxID: detail.summary.mailboxID,
                mailboxPath: path,
                mailboxRole: role,
                snippet: detail.summary.snippet
            )
        }
    }
}
