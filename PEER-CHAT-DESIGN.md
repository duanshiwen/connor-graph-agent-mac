# 康纳同学 · 真人聊天（Peer Chat）与会话级 AI 分析设计

文档状态：设计提案，未实现
版本：v2（统一会话列表版）
定位：在康纳同学中引入真人单聊与群聊。真人会话与 AI 会话**并列在同一个会话列表里、共用同一套状态与标签**，同时保证聊天正文不会在没有明确授权的情况下离开本机或进入 Memory OS。

---

## 1. 目标与非目标

### 目标

- 真人**单聊**与**群聊**，多设备一致，离线可发、联网补齐。
- 真人会话与 AI 会话**同列表、同状态体系、同标签体系**，各自有可编辑的会话名称，名称前带一个括号前缀标明群名或对方昵称。
- AI 分析以**多条选中消息（≥2 条）或整段会话**为单位。单条消息对模型没有语义价值，产品上直接禁掉。
- 超出模型上下文时，明确提示"消息过多，无法完成分析"，不做静默截断、不做分段拼凑。
- 隐私：**没有任何自动路径**把聊天正文送给模型或写入 Memory OS。
- 好友即人际关系：加为好友后自动建立人物档案；人物档案上可以直接发起聊天。
- 最大化复用现有基础设施：Chat Viewport、Composer、会话治理、附件、设计系统、账号体系、提升队列、人际关系。

### 非目标（本期）

- 端到端加密（见 §13，接口预留）。
- 音视频通话、动态/朋友圈。
- 跨端客户端（iOS / Web）。
- 让真人聊天成为 Agent 的自动上下文来源。

### 与 ENGINEERING.md 的冲突（必须先处理）

`ENGINEERING.md` §1/§11 目前把「远程 daemon / 云同步」「团队 / 多用户权限模型」列为不做。`feature/account-sync-multidevice` 分支（`AppUserIdentityStore`、`sync/push`、知识市场）事实上已经越过第一条。引入 IM 后两条都不成立。

改写为**双边界**，而不是删掉限制：

```text
本地优先边界：会话正文、记忆、文件、工具执行、模型凭证 —— 永远本地权威
账号托管边界：身份、好友关系、人际通讯、知识市场 —— 服务端权威，
             但不得回流为 Agent 上下文
```

同步更新：§1 边界改写、新增 §5.10 Peer Chat、§8 UI 指南补充统一列表规则、§10 检查清单补充隔离约束。**先改文档再写代码。**

---

## 2. 核心架构：信封共享，正文隔离

你要的"同一个列表、同一组状态"和"正文不能被 AI 自动看到"看起来矛盾，实际上不矛盾——因为它们作用在不同的层。

> **会话信封（envelope）共享，消息正文（body）隔离。**

| 层 | 内容 | 存储 | 谁能读 |
|---|---|---|---|
| **信封** | id、title、kind、状态、标签、归档/星标、未读状态、updatedAt | `sessions` 表（**与 AI 会话同一张表**） | 列表、筛选、搜索标题、治理 |
| **正文** | 消息、发送者、附件、已读回执 | `peer_messages` 等独立表 | 只有 Peer Chat 运行时 |

于是：

- 真人会话**就是** `sessions` 表里的一行，`kind = .direct` 或 `.group`。列表、状态、标签、归档、筛选、排序、标题编辑**全部零成本复用**。
- 但真人会话的 `AgentSession.messages` **恒为空数组**。Agent 侧读的是 `session.messages` 和 `messages` 表，所以它在结构上读不到一个字。
- 正文只能通过 `PeerChatRepository` 读取，而这个仓库不注入给任何 Agent 运行时、任何工具、任何 Memory OS 路径。

这比 v1 的"完全分家"更贴近你的产品意图，比"直接塞进 `messages` 表"安全得多——后者会让 prompt assembly、摘要、标题生成、L0/L1 摄取全部瞬间够得着聊天正文，隐私就退化成到处撒 `if` 的运气问题。

---

## 3. 领域模型

### 3.1 扩展会话种类

`Sources/ConnorGraphCore/AgentSessionGovernance.swift`：

```swift
public enum AgentSessionKind: String, Codable, Sendable, Equatable, CustomStringConvertible {
    case chat            // 与康纳同学的 AI 会话
    case note            // 笔记
    case direct          // 真人单聊
    case group           // 真人群聊
    case chatAnalysis    // 由真人会话生成的 AI 分析会话

    public var isPeer: Bool { self == .direct || self == .group }
    public var carriesAgentTranscript: Bool { !isPeer }   // 护栏用

    public var description: String {
        switch self {
        case .chat: "chat"
        case .note: "笔记"
        case .direct: "单聊"
        case .group: "群聊"
        case .chatAnalysis: "会话分析"
        }
    }
}
```

`isPeer` / `carriesAgentTranscript` 是后面所有护栏的唯一判据，不允许在别处重复手写条件。

### 3.2 真人会话的附加信息

信封在 `sessions` 表，但真人会话有一些 AI 会话没有的字段，放独立表 `peer_conversation_meta`，通过同一个 session id 关联：

```swift
public struct PeerConversationMeta: Codable, Sendable, Equatable, Identifiable {
    public var id: String                    // == AgentSession.id
    public var kind: PeerConversationKind    // direct / group
    public var remoteConversationID: String  // 服务端 ID
    public var peerName: String              // 群名，或对方昵称 —— 括号前缀的来源
    public var avatarURL: String?
    public var participants: [PeerParticipant]
    public var lastSeq: Int64
    public var lastMessagePreview: String?
    public var aiPolicy: PeerConversationAIPolicy
    public var isMuted: Bool
    public var isPinned: Bool
}

public enum PeerConversationKind: String, Codable, Sendable { case direct, group }

public enum PeerParticipantRole: String, Codable, Sendable { case owner, admin, member }

public struct PeerParticipant: Codable, Sendable, Equatable, Identifiable {
    public var userID: UInt                  // 对齐 ConnorPublicUser.id
    public var displayName: String
    public var avatarURL: String?
    public var role: PeerParticipantRole
    public var joinedAt: Date
    public var leftAt: Date?
    public var linkedPersonID: String?       // 绑定本地 PersonProfile
    public var id: UInt { userID }
}
```

**`peerName` 与 `AgentSession.title` 是两个字段。** 前者是群名/昵称（跟随服务端，不可本地编辑），后者是你给这个会话起的名字（本地可编辑，与 AI 会话完全一致的交互）。§5 说明它们如何合成显示标题。

### 3.3 消息

```swift
public enum PeerMessageKind: String, Codable, Sendable {
    case text, attachment, system, recall
}

public enum PeerMessageDeliveryState: String, Codable, Sendable {
    case pending, sent, delivered, failed    // 纯本地状态，不上行
}

public struct PeerMessage: Codable, Sendable, Equatable, Identifiable {
    public var id: String                    // 服务端 ID
    public var clientID: String              // 本地生成，幂等键
    public var conversationID: String        // == AgentSession.id
    public var seq: Int64                    // 会话内单调序号，服务端分配
    public var senderUserID: UInt
    public var kind: PeerMessageKind
    public var text: String
    public var attachments: [AgentMessageAttachmentRef]   // 复用附件模型
    public var replyToMessageID: String?
    public var mentionedUserIDs: [UInt]
    public var sentAt: Date
    public var editedAt: Date?
    public var recalledAt: Date?
    public var deliveryState: PeerMessageDeliveryState
}
```

注意这里**没有复用 `AgentRole`**。`user / assistant / system` 三值表达不了群里 8 个人谁在说话，硬套会立刻在群聊上崩掉。发送者用 `senderUserID`，渲染时对照 `participants` 取昵称与头像。

### 3.4 群 AI 策略

```swift
public enum PeerAnalysisMode: String, Codable, Sendable {
    case allowed, ownerApprovalRequired, prohibited
}

public struct PeerConversationAIPolicy: Codable, Sendable, Equatable {
    public var analysisMode: PeerAnalysisMode
    public var announcesAnalysis: Bool       // 分析后是否在会话内留系统消息
    public var defaultPseudonymize: Bool

    public static let groupDefault  = Self(analysisMode: .allowed, announcesAnalysis: true,  defaultPseudonymize: true)
    public static let directDefault = Self(analysisMode: .allowed, announcesAnalysis: false, defaultPseudonymize: true)
}
```

---

## 4. 本地存储

`sessions` 表不动结构，真人会话只是多了几种 `kind` 取值。新增：

```sql
peer_conversation_meta(
  id TEXT PRIMARY KEY,               -- == sessions.id
  kind TEXT, remote_conversation_id TEXT,
  peer_name TEXT, avatar_url TEXT,
  participants_json TEXT, last_seq INTEGER, last_message_preview TEXT,
  ai_policy_json TEXT, is_muted INTEGER, is_pinned INTEGER)

peer_messages(
  id TEXT PRIMARY KEY, conversation_id TEXT, seq INTEGER,
  client_id TEXT UNIQUE, sender_user_id INTEGER, kind TEXT, text TEXT,
  attachments_json TEXT, reply_to TEXT, mentioned_user_ids_json TEXT,
  sent_at REAL, edited_at REAL, recalled_at REAL, delivery_state TEXT)
CREATE UNIQUE INDEX peer_messages_seq ON peer_messages(conversation_id, seq);

peer_outbox(
  client_id TEXT PRIMARY KEY, conversation_id TEXT, payload_json TEXT,
  attempts INTEGER, next_attempt_at REAL, last_error TEXT)

peer_sync_state(
  conversation_id TEXT PRIMARY KEY, last_pulled_seq INTEGER, last_read_seq INTEGER)

peer_friends(
  user_id INTEGER PRIMARY KEY, username TEXT, nickname TEXT, avatar_url TEXT,
  linked_person_id TEXT, befriended_at REAL, state TEXT)  -- pending/accepted/blocked
```

约束：

- **`peer_messages_fts` 独立**，只服务本地 UI 搜索，**不注册为任何 agent tool**，不并入 `native-source-index`。
- 附件落在 `Connor/im/{conversationID}/attachments/`，复用 `AttachmentImportPolicy` 与 manifest 归一化。
- `ConnorSyncChange.isSyncable` 排除集合加入 `peer_conversation_meta` / `peer_messages` / `peer_outbox` / `peer_friends`。真人会话由服务端权威提供多设备一致性，不走 last-writer-wins 的自有设备同步通道。

---

## 5. 统一列表与命名规则

### 显示标题的合成

```text
显示标题 = "（" + peerName + "）" + title
```

| 情况 | `peerName` | `title` | 列表显示 |
|---|---|---|---|
| 群聊，未改名 | 产品组 | （空） | `（产品组）` |
| 群聊，改过名 | 产品组 | 需求评审 | `（产品组）需求评审` |
| 单聊，未改名 | 张三 | （空） | `（张三）` |
| 单聊，改过名 | 张三 | 装修的事 | `（张三）装修的事` |
| AI 会话 | — | 帮我整理资料 | `帮我整理资料` |

规则：

- 新建真人会话时 `title` 为空，列表只显示括号部分。双击标题改名即可追加自己的名称——与 AI 会话完全一致的编辑交互（`AppListDetailPanes` 里现成的 `beginTitleEdit`）。
- `peerName` 跟随服务端（群改名、对方改昵称会自动更新），**不可本地编辑**；`title` 只在本地，属于你的组织方式。
- AI 会话没有括号前缀，视觉上天然区分两类。

实现：`AgentChatSessionPresentation` 增加

```swift
public var titlePrefix: String?     // peerName，AI 会话为 nil
public var displayTitle: String     // 合成结果，列表直接用
```

`title` 字段保留原义（可编辑部分），改名时只写它。

### 列表行的其他呈现

- 状态胶囊、标签、相对时间：**完全复用**，`AgentSessionStatus` 八个状态原样适用于真人会话。
- `"\(messageCount) 条消息"`：真人会话的 count 从 `peer_messages` 取（`session.messages` 恒空），在 `ChatSessionListModel.messageCountsBySessionID` 里合并注入即可，行视图不用改。
- `row.kind == .note` 那段徽标扩展为 switch：笔记 / 单聊（`person`）/ 群聊（`person.2`）/ 会话分析（`sparkles.rectangle.stack`）。
- 未读红点复用 `SessionReadState` 与 `ChatAttentionCoordinator`。

### 筛选与搜索

- 状态筛选、标签筛选：零改动。
- 全局搜索：真人会话按**标题**参与搜索（`session.messages` 为空，正文天然不进 `AgentSessionTextSearchFilter`）。正文搜索走独立的 `peer_messages_fts`，只在消息列表内部提供，且结果不进入任何 AI 上下文。

---

## 6. 必须加的护栏（这一节不能省）

信封共享意味着真人会话会出现在很多现有代码的 `loadSessions` 结果里。以下每一处都必须显式处理，并各配一条测试：

| 位置 | 风险 | 处理 |
|---|---|---|
| `AppChatSessionRepository.loadSession` | 把 peer 正文塞进 `session.messages` | 对 `kind.isPeer` 恒返回空 `messages`，且**不查** `peer_messages` |
| `NativeSessionManager` / `AgentLoopChatController` 的发送入口 | Agent 往真人会话里发消息 | `kind.isPeer` 时抛错拒绝，不是静默返回 |
| 两处 `enqueueChatMessage` | 正文进 L0/L1 | 上一条拒绝后自然不可达；再加 `carriesAgentTranscript` 断言兜底 |
| `AppAccountDataSyncCoordinator.projections()` | 把 peer 会话推到 `sync/push` | 过滤掉 `kind.isPeer`（真人会话服务端已权威，重复同步是纯风险） |
| `ChatSessionTitleGenerationWorker` | 调模型生成标题 = 正文外发 | 跳过 `kind.isPeer` |
| `AppNoteProjectionService` | 投影成笔记 | 跳过 `kind.isPeer` |
| **任务/自动化模板** | 「session 到达某状态时向该 session 发消息」会让 AI 自动往真人群里发言 | `tasks_create_session_status_message` / `tasks_create_scheduled_session_message` 对 `kind.isPeer` 拒绝创建，已存在的任务在执行时二次校验 |
| `AgentSessionTextSearchFilter` | 正文进搜索 | 天然安全（messages 为空），加断言锁死 |
| Memory OS 检索工具 | 命中 peer 内容 | 天然安全（不在 L0–L4），加回归测试锁死 |

最后一列的"天然安全"是这套架构的价值所在——**大多数护栏是断言，不是逻辑**。断言只在架构被破坏时才会响。

---

## 7. 好友与人际关系

产品判断：**好友就是人际关系里的人，聊天是人物档案上的一个能力。**

### 数据绑定

`PersonProfile` 增加：

```swift
public var connorUserID: UInt?          // 绑定的康纳账号
public var chatAvailability: PersonChatAvailability   // .none / .friend / .pending
```

### 自动建档

好友关系建立时（无论是你申请对方通过，还是对方申请你通过）：

1. 查本地是否已有 `connorUserID` 匹配的 `PersonProfile` → 有则复用。
2. 没有 → **自动创建一个 `PersonProfile`**，姓名取对方昵称，来源标记 `connorFriend`，写入 `connorUserID`。
3. 若存在姓名或邮箱疑似匹配的既有档案 → **不自动合并**，在人物详情页给一条"可能是同一个人，是否合并？"的提示，由你决定。

自动建档写的是**身份元数据**（昵称、头像、账号 ID），不是聊天内容。任何聊天正文都不会因为建档而进入这个人的记忆记录。

### UI 落点

复用现有 `contacts`（人际关系）路由：

- 联系人列表：好友项显示可聊天标识；新增「康纳好友」分组。
- 人物详情页：`connorUserID != nil` 时出现「发消息」按钮，点击创建或跳转到对应单聊会话。
- 新增「添加好友」入口：按用户名/邮箱搜索（`GET api/v1/im/users/search`）→ 发送申请 → 对方通过。
- 好友申请以系统通知呈现，不占用会话列表。

### 反向情况

对方注册了账号并加你为好友，而你本地没有这个人的档案——这正是自动建档要解决的场景：好友关系一旦成立，档案立刻出现在人际关系里，你不需要手动录入。

---

## 8. 传输层

复用 `ConnorBackendAPIClient` 的 request 管道与 `ConnorBackendAuthenticatedSession` 的 `401 → refresh → retry once`。

### REST 契约

```text
GET    api/v1/im/conversations?updatedAfter=<ts>
POST   api/v1/im/conversations                    {kind, memberUserIds, name}
PATCH  api/v1/im/conversations/{id}               {name}          群改名
GET    api/v1/im/conversations/{id}/messages?afterSeq=&limit=     增量
GET    api/v1/im/conversations/{id}/messages?beforeSeq=&limit=    历史分页
POST   api/v1/im/conversations/{id}/messages      {clientId, kind, text, attachments,
                                                   replyTo, mentionedUserIds}
                                                  → {id, seq, sentAt}
POST   api/v1/im/conversations/{id}/read          {seq}
POST   api/v1/im/conversations/{id}/members       {userIds}
DELETE api/v1/im/conversations/{id}/members/{userId}
PATCH  api/v1/im/conversations/{id}/ai-policy     {analysisMode, announcesAnalysis}
POST   api/v1/im/messages/{id}/recall
GET    api/v1/im/friends
POST   api/v1/im/friends/requests                 {userId}
POST   api/v1/im/friends/requests/{id}/accept
GET    api/v1/im/users/search?q=<username|email>
```

### 实时通道

`WSS api/v1/im/stream?deviceId=<id>`，JWT 走 header。事件：
`message.created` / `message.recalled` / `conversation.updated` / `participant.changed` / `receipt.read` / `typing` / `friend.request` / `friend.accepted`。

**权威数据以 REST 增量拉取为准，WS 只做通知与快路径投递。** 收到事件时若 `seq != last_pulled_seq + 1`，立刻触发 REST 补拉。丢事件不会造成历史空洞。

断线重连指数退避（1s → 30s 封顶），重连后按每会话 `afterSeq` 补拉。

### 发送路径

```text
点发送
 → 本地写 peer_messages(delivery_state=pending) + peer_outbox
 → UI 立即乐观渲染（带"发送中"）
 → outbox 泵 POST，成功后用服务端 {id, seq, sentAt} 回填并置 sent
 → 失败退避重试；超阈值置 failed，行内提供重试/删除
```

`clientID` 作服务端幂等键，重发不产生重复。

新增 `PeerChatSyncEngine`（actor）：持 WS 连接、outbox 泵、每会话游标，对 MainActor 暴露 `AsyncStream<PeerChatEvent>`。

---

## 9. UI 复用矩阵

| 现有组件 | 复用方式 | 改动 |
|---|---|---|
| 会话列表、状态、标签、筛选、标题编辑、归档/星标 | **直接复用**（信封共享的直接收益） | `AgentChatSessionPresentation` 加 `titlePrefix` / `displayTitle`；徽标 switch 扩展 |
| `CommercialChatViewport<Item, RowContent>` | **直接复用** | 无，已泛型 |
| `ChatViewportController` / `StateMachine` / `TopLoadPolicy` / `InitialAnchorPolicy` / `JumpToLatest` / `DataSetID` | **直接复用** | 无 |
| `AgentChatTimelineAdapter` 的日期分隔 + 未读插入算法 | 复用算法 | 抽出 `ChatTimelineAssembly`，解除 `CommercialChatItem` 对 `AgentChatTurnTimelineItem` 的硬依赖；新增 `PeerChatTimelineAdapter` |
| Composer（`AgentComposerStore/State`、附件 shelf、语音转写、`ComposerPersonMentionResolver`） | 复用 | 抽 `ComposerHost` 协议注入 send action；peer 宿主关闭 `/` 技能、模型选择、审批 badge；`@` 提及改为群成员 |
| `AgentChatDesignSystem` / `AppShellDesignSystem` | 复用 | 新增 peer 气泡 token（自己 / 他人 / 系统）与头像样式 |
| Markdown 渲染与编译缓存 | 复用，但**默认纯文本渲染** | 他人消息不自动加载远程图片/链接预览（防追踪像素），提供"按 Markdown 显示"开关 |
| 附件导入 / manifest / 预览（Quick Look、PDFKit、音频播放器） | 复用 | conversation-scoped 附件目录 |
| `SessionReadState` / `ChatAttentionCoordinator` | **直接复用** | 无 |
| `RetainedRouteHostView` / list-detail 路由 | **直接复用** | 无——真人会话就在 `agentChat` 路由里，不新增侧边栏项 |
| `AppUserIdentityStore` / 本地加密凭证库 | **直接复用** | 无 |
| 人际关系（`PersonProfile`、`@` 提及、关系图） | 复用 | 加 `connorUserID`、好友分组、「发消息」按钮 |
| `AppPromotionQueueRepository` | **直接复用** | 无（见 §11） |
| `ConnorDeepLinkNavigator` | 复用 | 加真人会话与分析会话路由 |

**明确不复用**：`NativeSessionManager`、`AgentLoopChatController`、审批体系、工具调用、`AgentChatProcessRows`、prompt inspection、会话摘要、note projection。

### 详情区的分流

`agentChat` 路由的 detail pane 按 `kind` 分流：

```swift
switch session.governance.kind {
case .chat, .note, .chatAnalysis: AgentChatView(...)      // 现有
case .direct, .group:             PeerChatView(...)        // 新增
}
```

`PeerChatView` 内部是同一套 viewport + 同一套 composer，只是行渲染器与发送动作不同。观感上两类会话应当高度一致——这正是复用的目的。

### 新增文件

```text
Sources/ConnorGraphCore/PeerChatDomain.swift
Sources/ConnorGraphCore/PeerChatAnalysisDomain.swift
Sources/ConnorGraphStore/PeerChatStore.swift
Sources/ConnorGraphAppSupport/PeerChatAPIClient.swift
Sources/ConnorGraphAppSupport/PeerChatSyncEngine.swift
Sources/ConnorGraphAppSupport/PeerChatRepository.swift
Sources/ConnorGraphAppSupport/PeerFriendService.swift
Sources/ConnorGraphAppSupport/PeerAnalysisBundleBuilder.swift
Sources/ConnorGraphAppSupport/PeerRedactionEngine.swift
Sources/ConnorGraphAppSupport/PeerChatAnalysisConsentGate.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerChatFeatureModel.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerChatView.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerChatMessageRows.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerChatSelectionModel.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerChatAnalysisConsentSheet.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerChatConversationSettingsView.swift
Sources/ConnorGraphAgentMac/PeerChat/PeerFriendAddView.swift
Sources/ConnorGraphAgentMac/ChatViewport/ChatTimelineAssembly.swift
```

---

## 10. AI 分析

> **分析是一次有范围、有预览、有留痕的显式导出，不是订阅。**

### 10.1 选择方式（只有两种）

1. **多选消息**：进入多选模式，勾选消息，**至少 2 条**才允许分析。选中 1 条时按钮禁用，提示「请至少选择 2 条消息——单条消息无法提供足够上下文」。
2. **全选**：一键选中整段会话。

没有时间范围选择器、没有"最近 N 条"。多选 + 全选已经覆盖真实用法，少一个维度就少一处误操作。

入口只有两个，都必须由人点击：会话标题栏「AI 分析」按钮（等价于全选）、多选后的「用 AI 分析选中内容」。**不接入任何自动化路径**：不出现在任务模板里，不能被状态变化触发，Agent 没有任何工具能读到真人会话。

### 10.2 容量判断

```swift
public enum PeerAnalysisCapacity: Sendable, Equatable {
    case ok(estimatedTokens: Int, budget: Int)
    case tooLarge(estimatedTokens: Int, budget: Int, messageCount: Int)
}
```

预算取当前会话所选模型的上下文上限，扣掉 system prompt 与回复预留（建议留 25%）。超出时：

```text
消息过多，无法完成分析
选中 1,842 条 · 约 312k tokens，超出「claude-opus-5」可用上下文（约 150k）
请减少选择范围，或切换到上下文更大的模型。
```

**不静默截断、不分段拼凑。** 分段 map-reduce 会产出"看起来完整、实际丢了跨段关联"的结论，比直接拒绝更糟。按当前主流模型的窗口，正常聊天记录很难触发这条。

### 10.3 Bundle

```swift
public struct PeerAnalysisBundle: Sendable, Equatable {
    public var conversationName: String          // 可编辑，可清空
    public var kind: PeerConversationKind
    public var aliases: [UInt: String]           // 真实用户 → 别名，仅本地保留
    public var entries: [PeerAnalysisEntry]
    public var messageCount: Int
    public var characterCount: Int
    public var estimatedTokens: Int
    public var redactions: [PeerRedactionSummary]
    public var attachmentPolicy: PeerAttachmentAnalysisPolicy   // .excluded/.filenamesOnly/.includeExtractedText
    public var renderedText: String              // 真正会发出去的全文
}
```

**`renderedText` 就是 prompt 里原样出现的文本。** 确认面板看到什么，模型就收到什么，不做二次加工、不做隐式摘要。

渲染格式（给模型完整的时间序列与说话人结构）：

```text
<conversation kind="group" name="产品组" messages="128"
              from="2026-07-01T09:12+08:00" to="2026-07-20T18:40+08:00"
              note="participants are pseudonymized">
[2026-07-01 09:12] A: 明天的评审我把方案二的成本表补上
[2026-07-01 09:13] B: 好，另外预算那块要不要拉上财务
[2026-07-01 09:15] A: （图片：成本对比.png，内容未包含）
[已省略 3 条]
[2026-07-01 09:31] 我: 那就定周四下午
</conversation>
```

整段作为**首条 user 消息一次性注入**。未选中的消息留 `[已省略 N 条]` 占位，让模型知道有断点，避免它对连续性做错误推断。

### 10.4 确认面板

```text
┌─ 把这段会话交给 AI 分析 ──────────────────────────────┐
│  ⚠️ 内容将发送给「Anthropic · claude-opus-5」，会离开本机 │
│                                                          │
│  范围   产品组 · 125 条 · 7月1日–7月20日                  │
│  体量   约 24,300 字 / 预估 18.2k tokens（上限约 150k）   │
│                                                          │
│  参与者 ◉ 匿名化（A/B/C，自己显示为"我"）                 │
│         ○ 使用昵称   ○ 使用真实姓名                       │
│                                                          │
│  脱敏   ✓ 手机号 3 · 邮箱 2 · 身份证 0 · 银行卡 1 · 地址 2 │
│         （点击定位；整体关闭需二次确认）                   │
│                                                          │
│  附件   ◉ 仅文件名  ○ 不提及  ○ 包含已提取文本            │
│                                                          │
│  意图   ◉ 总结纪要 ○ 待办与承诺 ○ 决策与分歧              │
│         ○ 关系与情绪 ○ 自定义…                            │
│                                                          │
│  记忆   ◉ 本次分析不写入记忆（推荐）                       │
│         ○ 结论送入提升队列，由我逐条确认                   │
│                                                          │
│  ▼ 全文预览（可滚动，逐字即将发送的内容）                  │
│                                                          │
│  ☐ 本会话 24 小时内不再询问                               │
│                  [ 取消 ]  [ 确认并发送（125 条 / 约 18.2k）]│
└──────────────────────────────────────────────────────────┘
```

- 默认值一律取保守项：匿名化开、脱敏开、附件仅文件名、不写入记忆。
- 「24 小时内不再询问」写 `PeerAnalysisConsentGrant { conversationID, expiresAt, policyHash, participantsHash }`。**参与者变化、AI 策略变化、脱敏设置变化 → 授权立即失效。**
- **永远不提供「所有会话永久不再询问」。** 这是本方案的底线。

### 10.5 分析会话

点确认后：

1. 创建 `AgentSession(kind: .chatAnalysis)`，`peerName` 前缀沿用来源会话 → 列表显示 `（产品组）会话分析 07-20`，与来源天然相邻。
2. 首条 user 消息 = `renderedText` + 意图指令。
3. 此后**完全是一个普通康纳会话**：可继续追问「第二段谁提出的方案」「把待办导出成任务」，复用流式输出、工具、Markdown、导出。分析产物本身不需要任何新 UI。
4. `governance.memoryCapturePolicy = .disabled`（见 §11）。
5. 来源会话内插入一条**仅本地可见**的卡片「已生成分析 →」，点击跳转。

### 10.6 审计

每次授权写 `logs/audit/peer-analysis.jsonl`：

```json
{"at":"2026-07-27T14:22:03+08:00","conversationId":"...","selectionMode":"explicit",
 "messageCount":125,"characterCount":23800,"estimatedTokens":18200,
 "provider":"anthropic","model":"claude-opus-5","pseudonymized":true,
 "redactions":{"phone":3,"email":2,"bankCard":1},
 "bundleSha256":"...","announcedToConversation":true}
```

**不记录正文。** 只记录"发生过什么、多大范围、发给了谁"。

---

## 11. 与 Memory OS 的关系

新增 `AgentSessionGovernanceMetadata.memoryCapturePolicy`：

```swift
public enum MemoryCapturePolicy: String, Codable, Sendable {
    case standard          // 现有行为
    case conclusionsOnly   // 只有用户显式保存的结论可进提升队列
    case disabled          // 完全不摄取
}
```

在两处 `enqueueChatMessage` 调用点检查。改动面很小，因为入口只有两个。

| 内容 | 策略 |
|---|---|
| 真人聊天正文 | **结构性不可摄取**（不在 `messages` 表，Memory OS 看不到） |
| 分析会话首条消息（逐字转录） | `.disabled` —— **永远不进 L0** |
| 分析结论 | 用户点「保存要点到记忆」后，**不直接写 L2/L3/L4** |

结论落地复用**现有提升队列**：

```text
分析结论 → 拆条写入 ObserveLog（kind: .candidate_fact/.insight，source: .user）
        → 出现在侧边栏「提升队列」
        → 用户逐条 promote / dismiss（AppPromotionQueueRepository 现成能力）
        → promote 写入结论文本 + provenance 指向 bundleHash 与会话 ID
           —— 不回填任何原始逐条聊天记录
```

L1 后台统一投影完全不参与。链路里每一步都需要人点一下——这正是"不能像提纯知识那样自动化"。

---

## 12. 群聊与他人的知情权

群里把转录发给模型会暴露其他人的发言，这不是单方面能决定的事。

- 群 `aiPolicy.analysisMode`：`allowed`（默认）/ `ownerApprovalRequired`（产生待群主批准的请求）/ `prohibited`（按钮禁用并说明原因）。
- `announcesAnalysis`（群默认 `true`）：分析成功后向群内发一条 system 消息「张三 对 125 条消息做了一次 AI 分析（总结纪要）」。**只报范围与意图，不报结论。**
- 单聊默认 `allowed` + `announcesAnalysis = false`；对方可在账号设置开启「他人分析包含我的会话时通知我」，服务端合成生效策略下发。
- 账号级偏好放 设置 → 隐私：「默认允许他人 AI 分析包含我的会话」。
- 默认匿名化正是为降低把他人身份送到模型侧的风险。

### 必须诚实的一点

这些是**客户端 + 服务端的策略约束，不是密码学强制**。任何人都能截屏后自己粘贴给任意模型。文案只能写：

> 群主已关闭 AI 分析。康纳不会在本应用内把这个群的内容发送给模型。

不能写：

> ~~这个群的内容不会被 AI 读取。~~

---

## 13. 端到端加密：本期取舍

**决定：先明文 + 预留。** 消息 `body` 设计为不透明 payload + `encVersion` 字段，本期 `encVersion = 0` 存明文，同时提供本地存储加密。

理由：E2EE 会让服务端搜索失效、多设备需密钥分发、群成员变更需密钥轮换，与刚落地的账号同步体系正面冲突，工程量数倍。而本方案的隐私重点是**不让聊天流向模型与记忆**，这一点靠架构隔离已经解决，与传输加密是两个问题。

对应义务：UI 必须明说「消息保存在康纳服务器」，不得含糊。

---

## 14. 分期实施

全程 feature flag `CONNOR_PEER_CHAT_ENABLED` 门控（对齐 `AppFeatureFlags` 现有模式）。

| 阶段 | 内容 | 验收 |
|---|---|---|
| **M0 地基** | `AgentSessionKind` 扩展 + §6 全部护栏 + 护栏测试 | 护栏测试全绿；现有 `swift test` 无回归 |
| **M1 单聊骨架** | store schema + REST 客户端 + outbox + 统一列表接入 + `PeerChatView` | 两台设备互发文字；断网发送重连补齐；`seq` 连续无空洞；真人会话与 AI 会话同列表、可改状态改标签 |
| **M2 完整度** | WS 实时、未读/已读、引用回复、撤回、`@` 提及、附件、输入中、免打扰、置顶、正文搜索 | 观感与 AI 会话一致；1000 条历史滚动不卡 |
| **M3 好友与群** | 好友申请/通过、自动建档、人物详情「发消息」、建群、成员管理、群改名、群 AI 策略 | 加好友后人际关系立刻出现档案；`prohibited` 生效 |
| **M4 AI 分析** | 多选模型 + BundleBuilder + RedactionEngine + 容量判断 + ConsentSheet + 分析会话 + 审计 + 提升队列 | 见 §15 |
| **M5 打磨** | 导出、消息转发、会话封存、通知中心 | — |

---

## 15. 必须写的测试

### 隔离回归（最重要）

```text
✓ 构造 200 条 peer 消息 → 跑 L1 unified projection → 断言 L0/L1 不含任何 peer 正文
✓ loadSession(kind: .direct).messages.isEmpty == true
✓ Agent 发送入口对 kind.isPeer 抛错，而非静默通过
✓ memory_os_search / memory_os_recent_context 无法命中 peer 消息
✓ AppAccountDataSyncCoordinator.projections() 不含 peer 会话
✓ ConnorSyncChange.isSyncable("peer_messages") == false
✓ tasks_create_session_status_message 对 peer 会话拒绝创建
✓ ChatSessionTitleGenerationWorker 跳过 peer 会话
✓ 分析会话 memoryCapturePolicy == .disabled 时首条消息不进 L0
```

### 列表与命名

```text
✓ displayTitle 合成：有/无 title、群/单聊/AI 四类组合
✓ 改名只写 title，不影响 peerName；群改名下发后前缀更新
✓ 状态与标签筛选对真人会话生效
✓ messageCount 对真人会话取自 peer_messages
```

### 分析

```text
✓ 选中 1 条时分析入口禁用
✓ 超预算时返回 tooLarge，且不产生任何网络请求
✓ 无有效 grant 时任何路径都无法把 renderedText 交给 provider
✓ grant 在参与者变化 / 策略变化 / 过期后立即失效
✓ 未选中消息不出现在 renderedText，且留下占位
✓ 别名映射稳定（同一会话多次分析，A 始终是同一个人）
```

### 脱敏

```text
✓ 中国手机号 / 邮箱 / 身份证 / 银行卡 / URL 命中
✓ 不误伤：订单号、版本号、时间戳、代码片段
```

### 传输与好友

```text
✓ 同一 clientID 重发不产生重复消息
✓ WS 丢事件后 REST 补拉，seq 连续性断言
✓ 好友建立后自动创建 PersonProfile；已有绑定则复用
✓ 疑似重复档案给出合并提示，不自动合并
```

---

## 16. 待你确认

1. **`peerName` 与 `title` 的双层命名**是否符合你的预期？特别是"未改名时列表只显示 `（产品组）`"这一条。
2. **服务端归属** —— 现有 `api/v1` 后端由谁维护？本文档给的是契约，需要我一并设计/实现服务端吗？
3. **好友申请流程**是否必须？还是允许凭用户名直接发起会话（无需对方同意）。
4. **消息保留期** —— 服务端保留多久？
