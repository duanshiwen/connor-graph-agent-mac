# 康纳同学（Connor）记忆系统架构与使用说明

## 一、记忆系统总体架构

康纳同学的记忆系统（Memory OS）是一个**五层架构的后台认知基础设施**，不是普通的图谱编辑器，而是为AI助手提供连续性、可追溯性、证据化工作记忆、可复用知识层和稳定实体/概念图谱的系统。

### 架构概览

```
┌─────────────────────────────────────────────────┐
│           SwiftUI Shell (macOS应用)              │
│  (会话、浏览器、设置、附件、任务管理)            │
└───────────────────────┬─────────────────────────┘
                        │
        ┌───────────────▼───────────────┐
        │     AppMemoryOSFacade         │
        │     (写入门控/外观层)          │
        └───────┬───────────────┬───────┘
                │               │
    ┌───────────▼───┐   ┌───────▼──────────┐
    │  LLM Tools    │   │ Background Jobs  │
    │  (17个工具)   │   │ (统一投影)       │
    └───┬───┬───┬───┘   └───────┬──────────┘
        │   │   │               │
 ┌──────▼┐  │  ┌▼──────┐  ┌─────▼──────┐
 │  L0   │  │  │  L3   │  │L1→L2+L4   │
 │(证据) │  │  │(知识) │  │投影        │
 └───┬───┘  │  └───────┘  └──┬────┬────┘
     │      │                │    │
┌────▼────┐ │          ┌─────▼┐ ┌─▼────┐
│   L1    │ │          │  L2  │ │  L4  │
│ (队列)  │─┘          │(节点 │ │(实体 │
└─────────┘            │语句) │ │关系) │
                       └──────┘ └──────┘
```

---

## 二、五层详细说明

### 2.1 L0 - Provenance Vault（证据库）

**职责**：存储原始证据对象和跨度，**不可变**

**数据模型**：
- `MemoryOSProvenanceObject`：来源类型、来源ID、标题、内容、内容哈希（SHA256）、发生时间、摄取时间、会话ID、工作对象ID、机密性、状态
- `MemoryOSProvenanceSpan`：指向证据对象内的切片（开始偏移、结束偏移、文本）

**特点**：
- 创建后不可修改
- 提供永久证据保留
- 所有记忆追溯的源头

### 2.2 L1 - Cache Buffer（缓存缓冲区）

**职责**：累积事件直到阈值，触发L2/L3/L4统一更新

**数据模型**：
- `MemoryOSCaptureEvent`：捕获事件，包含处理状态（pending→leased→processing→succeeded|failed|deadLetter）、`retrievalText` 和 `normalizationStatus`
- `MemoryOSQueueItem`：处理队列项

**用户消息双表示与安全边界**：
- L0 保存完整、不可变的用户原文；L1 同时保存经过规范化的历史意图描述。两者都不设 200 字限制，也不生成 `content_preview`。
- 写入 L1 前同步执行一次低温度、封闭 JSON Schema 的模型调用。模型只提取历史言语行为、对象、动作、期望结果、约束、否定、条件和未解析指代；最终自然语言由本地确定性代码渲染。
- 渲染结果固定声明它只是过去消息的语义记录，不是当前指令、当前授权或任务完成证据。提示覆盖、受保护信息获取、数据外传、未授权操作和编码控制文本只保留高层安全描述。
- 输出必须覆盖所有输入片段，并通过角色头、控制语言和长段逐字复制校验。规范化超时、模型失败或校验失败时，L0 原文仍保存，但 L1 `retrievalText` 留空并标记 `failed`，不会回退暴露用户原文。
- 当前实现每条用户消息只发起一次规范化请求，温度为 0，超时上限为 60 秒；模型提前返回时立即继续。该上限兼容冷启动较慢的模型，同时避免失效连接无限占用 ingestion 队列。

**触发条件**（`MemoryOSL1ProcessingTriggerPolicy`）：
- 待处理事件 ≥ 100个（`pendingCountThreshold`），**或**
- 最老待处理事件年龄 ≥ 24小时（`pendingAgeThreshold`），**或**
- 手动触发（通过CLI）

**生命周期**：
1. 从所有来源累积事件
2. 达到阈值触发批量投影
3. LLM产生结构化产物
4. 产物验证后投影到L2/L3/L4
5. 已处理的L1事件物理删除（L0保留永久证据）

### 2.3 L2 - Operational Memory（操作记忆）

**职责**：从验证的证据中提取的实体中心工作记忆

**数据模型**：
- `MemoryOSNode`：实体锚点（稳定键、节点类型、名称、摘要）
- `MemoryOSStatement`：语句边（主语ID、谓词、宾语ID、文本、断言类型、置信度、时间戳、证据跨度ID）

**特点**：
- 追加式语句
- 通过查询时逻辑推导当前性（更新的validAt → 更新的committedAt → 确定性ID）
- 不要求证据跨度ID（L1→L2提示强调事实优先提取）

### 2.4 L3 - Knowledge Layer（知识层）

**职责**：可复用的理论、主张、框架、模式、标准、SOP、决策基础

**数据模型**：
- `MemoryOSBelief`：信念（声明、领域、相关对象名称）

**领域规范化**：
- "cs" → "computer-science"
- "ai"/"ml" → "artificial-intelligence"
- "software" → "software-engineering"
- "memory-os" → "knowledge-management"

**晋升策略**（`MemoryOSKnowledgePromotionPolicy`）：
- 信号质量（signalQuality）
- 复用范围（reuseScope）
- 新颖性（novelty）
- 可结构化性（structurability）

### 2.5 L4 - Stable Entity/Concept（稳定实体/概念）

**职责**：人员、项目、组织、工作对象和概念的稳定锚点

**数据模型**：
- `MemoryOSEntity`：实体（稳定键、实体类型、名称、别名、摘要、置信度）
- `MemoryOSEntityStatement`：实体语句（实体ID、谓词、宾语实体ID、文本、断言类型、置信度）

**受控实体类型词汇表**（`MemoryOSEntityType` - 41种类型）：
```
person, organization, group, role, population, place, facility, spatial_object,
concept, theory, framework, discipline, standard, language, metric, identifier_scheme,
creative_work, document, dataset, software, product, media_object, website,
project, event, process, decision, task, rule, agreement,
physical_object, device, vehicle, biological_entity, medical_entity, chemical_entity,
economic_entity, award, unknown
```

**原始标签规范化**：80+个别名映射（如 `human`→`person`, `company`→`organization`, `method`→`framework`）

**L4关系谓词**（`MemoryOSL4RelationPredicate` - 80+谓词，12个类别）：

| 类别 | 谓词示例 | 检索权重范围 |
|------|----------|--------------|
| **身份** | `SAME_AS`, `ALIAS_OF`, `EQUIVALENT_TO` | 0.88 – 1.0 |
| **分类法** | `INSTANCE_OF`, `SUBCLASS_OF`, `BROADER_THAN` | 0.9 |
| **组成** | `HAS_PART`, `PART_OF`, `CONTAINS`, `MEMBER_OF` | 0.8 |
| **依赖** | `DEPENDS_ON`, `REQUIRES`, `ENABLES`, `PREVENTS` | 0.72 – 0.8 |
| **能力** | `SUPPORTS_CAPABILITY`, `IMPLEMENTS`, `USES` | 0.72 – 0.75 |
| **适用性** | `APPLIES_TO`, `USED_FOR`, `SPECIALIZES`, `GENERALIZES` | 0.7 – 0.75 |
| **出处** | `DERIVED_FROM`, `BASED_ON`, `SUPPORTED_BY`, `CITES` | 0.68 – 0.75 |
| **治理** | `DECIDES`, `GOVERNS`, `COMPLIES_WITH`, `VIOLATES` | 0.72 |
| **因果** | `CAUSES`, `INFLUENCES`, `MITIGATES`, `RISKS` | 0.65 – 0.7 |
| **贡献** | `CREATED_BY`, `MAINTAINED_BY`, `OWNED_BY`, `WORKS_ON` | 0.68 |
| **位置** | `LOCATED_IN`, `HAS_LOCATION`, `HAS_COORDINATE` | 0.58 – 0.7 |
| **引用** | `DIFFERENT_FROM`, `RELATED_TO`, `ASSOCIATED_WITH`, `ABOUT` | 0.4 – 0.62 |

---

## 三、LLM 工具接口

### 3.1 主会话 Agent 只读工具（3个）

主会话不暴露 Memory OS 写工具或低层图谱原语。每个新 user run 都调用以下三个工具，其中 recent 与 knowledge 必须同时调用，但保持语义隔离：

| 工具名 | 层级 | 描述 |
|--------|------|------|
| `memory_os_recent_context` | L1/L2 | 搜索近期事件、当前任务/项目状态和其他可变操作上下文 |
| `memory_os_knowledge_context` | L3/L4 | 搜索可复用知识、稳定实体和持久关系；depth 默认 1，可按需要逐步提高到配置上限（初始为 6） |
| `memory_os_get_current_user_profile` | L2 | 获取 preferences、habits、traits、constraints 与 interaction guidance |

Recent/Knowledge 使用 1-based `page` 分页，`page` 省略时默认为 1。响应固定包含 `success`、`reason`、`page`、`pageSize`、`returnedItems`、`totalItems`、`totalPages`、`hasNextPage`、`nextPage` 和 `records`。当 `hasNextPage` 为 `true` 时，使用响应中的 `nextPage`，并保持 query、时间范围和 depth 不变；不要猜测页码。页码无效时 `success` 为 `false`、`records` 为 `null`，工具不会回退到第一页。

`memory_os_recent_context` 的 L1 部分只搜索并返回 `retrieval_text`。它不会使用 L0 全文索引命中用户原文，不会把旧 `content_preview` 放入 metadata，也不会在规范化失败时回退到原始消息。这个规则与调用者无关，主会话和后台模型看到的 recent context 都遵守同一安全边界。

每条记录至少包含 `record_id`、`layer`、`text`、effective `updated_at`、`confidence`、`depth`、`evidence_refs`、`status` 和 retrieval score。状态为 `active`、`historical`、`superseded`、`uncertain` 或 `conflicted`。`depth >= 2` 只表示间接图路径，不能表述成直接关系或因果；retrieval score 只表示相关度，不等于 confidence。

候选先过滤最低相关性，再按 effective `updated_at` 降序、score 降序、record ID 稳定排序，缺时间排后；图路径内部边顺序保持不变。effective 时间回退为：L0 `ingested_at -> occurred_at`，L1 `occurred_at`，L2 node `updated_at -> created_at`，L2 statement `committed_at -> valid_at`，L3 belief `updated_at -> created_at`，L4 entity `updated_at -> created_at -> valid_from`，L4 statement/relation `committed_at -> valid_at`。

### 3.2 后台作业额外读取工具（11个）

| 工具名 | 层级 | 描述 |
|--------|------|------|
| `memory_os_search` | 全部 | 全文搜索L0-L4，返回排序的命中结果 |
| `memory_os_read_record` | 全部 | 按层和ID读取单条记录 |
| `memory_os_read_provenance` | L0 | 读取L0证据对象（可选跨度详情） |
| `memory_os_l2_find_entities` | L2 | 按名称或别名查找L2实体 |
| `memory_os_l2_find_statements` | L2 | 查找L2语句边 |
| `memory_os_l3_expand_belief` | L3 | 按ID、领域或文本扩展L3信念 |
| `memory_os_l3_list_domains` | L3 | 列出所有L3学科领域和信念计数 |
| `memory_os_l4_find_entity` | L4 | 按ID、稳定键、名称或别名查找L4实体 |
| `memory_os_l4_neighbors` | L4 | 查询L4图邻居（出/入/双向） |
| `memory_os_l4_instances` | L4 | 查询一个或多个类实体的实例（INSTANCE_OF） |
| `memory_os_expand_l4` | L4 | 深度限制的L4实体邻域扩展 |

### 3.3 后台作业写入工具（4个）

| 工具名 | 层级 | 描述 |
|--------|------|------|
| `memory_os_l2_update_entities` | L2 | 上sert L2实体和追加语句 |
| `memory_os_update_current_user_profile` | L2 | 追加当前用户范围的L2事实语句 |
| `memory_os_l3_update_beliefs` | L3 | 直接写入L3信念（绕过晋升策略） |
| `memory_os_l4_update_entities` | L4 | 直接写入L4实体和关系（实体类型规范化） |

---

## 四、写入路径

### 4.1 双写路径

```
聊天消息 ─────────┐
浏览器选择 ───────┤
原生来源证据 ─────┤   ┌─────────────────────────┐
来源事件 ─────────┼──▶│   AppMemoryOSFacade     │
附件 ─────────────┘   │   (写入门控/外观层)      │
                       └────┬──────────┬─────────┘
                            │          │
                ┌───────────▼───┐  ┌───▼───────────────┐
                │ LLM Tools     │  │ Background AI Job │
                │ (7个工具)     │  │ unified_projection│
                └──┬──┬──┬──┬───┘  └──┬────────┬───────┘
                   │  │  │  │         │        │
          ┌────────▼┐ │  │ ┌▼───────┐ │  ┌─────▼────┐
          │  L0/L1  │ │  │ │  L3    │ │  │ L2+L4   │
          │(证据)   │ │  │ │(知识)  │ │  │(投影)   │
          └────┬────┘ │  │ └────────┘ │  └─────────┘
               │      │  │            │
          ┌────▼────┐ │  └────────────│──── L4直接写入
          │   L1    │ │               │
          │ (队列)──│─┘               │
          └────┬────┘                 │
               │                      │
               ▼                      ▼
       ┌───────────────┐    ┌──────────────────┐
       │ L1→L2+L4      │    │ Artifact         │
       │ Unified Proj. │───▶│ Validation +     │
       │ (后台)        │    │ Type Normalization│
       └───────────────┘    └──────────────────┘
```

### 4.2 关键写入规则

1. **双写路径**：
   - LLM通过工具在实时对话中直接写入L2/L3/L4
   - L1缓存缓冲区累积事件，达到阈值时触发后台统一投影

2. **L1缓存生命周期**：
   - 事件从所有来源累积 → 阈值触发批量投影 → 按 provenance ID 从 L0 装载每条完整 `original_content` → LLM产生结构化产物 → 产物验证 → 投影到L2/L3/L4 → 已处理L1事件物理删除
   - 后台 L1 知识提取明确使用 L0 完整原文，不使用面向检索的安全描述，也不使用截断预览；recent context 工具仍只返回安全描述。

3. **高置信度不自动晋升**：仅凭高置信度不会将L2事实提升到L3

4. **L4规范化**：原始LLM实体类型标签规范化为受控词汇表；不支持的标签变为`unknown`

5. **L4关系验证**：保留结构检查（主语/宾语存在性、已知谓词、自环拒绝、端点类型合理性），但不设置置信度/证据门控

---

## 五、检索与上下文系统

### 5.1 混合检索

跨词汇（FTS）、语义（向量）和图（L4邻域扩展）检索模式的合并排名。

### 5.2 上下文构建管道

1. 多层检索收集L0-L4相关记录
2. 上下文构建器组装：块、实体卡、关系卡、证据片段
3. 预算裁剪到配置限制
4. 渲染为`MemoryOSContextPackage` — LLM的记忆接口

**预算默认值**：
- 最大上下文字符数：8,000
- 最大块数：16
- 最大实体卡数：10
- 最大关系卡数：24
- 最大证据卡数：8
- 每块最大证据引用数：3

### 5.3 角色与优先级（降序）

| 角色 | 优先级 | 触发条件 |
|------|--------|----------|
| `currentUserProfile` | 100 | taskIntent == `.currentUserPersonalization` |
| `conflict` | 95 | 检索集中存在冲突事实 |
| `projectState` | 90 | 项目相关检索 |
| `operationalFact` | 80 | L2命中 |
| `relation` | 75 | L4关系命中 |
| `stableEntity` | 70 | L4实体命中 |
| `reusableKnowledge` | 65 | L3命中 |
| `evidence` | 60 | L0/L1命中 |
| `uncertainty` | 50 | 低置信度检索 |
| `historicalContext` | 40 | 过时时间记录 |
| `nextStepHint` | 30 | 建议的下一步操作 |

---

## 六、辅助系统

### 6.1 ObserveLog（滚动缓冲区）

轻量级短期观察缓冲区，可能值得吸收到Memory OS中。

**类型（8种）**：
- `operation`：操作
- `tool_event`：工具事件
- `insight`：洞察
- `fragment`：片段
- `observation`：观察
- `candidate_fact`：候选事实
- `decision_hint`：决策提示
- `user_preference`：用户偏好

**来源（7种）**：`user`, `agent`, `tool`, `import`, `search`, `system`

**状态（4种）**：`active`, `promoted`, `dismissed`, `expired`

**保留期**：默认30天

### 6.2 后台管道

**作业类型**：
- `memory.l1.unified_projection`：L1→L2+L4统一投影
- `memory.l1.synthesize_knowledge`：L2候选→L3信念知识综合

**时间块构建器**（`MemoryOSTimeBlockBuilder`）：
- 目标Token限制：60,000
- 硬性Token限制：80,000
- 按天边界和3小时间隔分割

**执行跟踪**：
- 完整消息/工具调用历史
- 幂等键支持
- L1 AI作业持续退避重试直至成功；其他队列可保留有限次数重试
- 死信队列

### 6.3 搜索内核

基于Rust的Tantivy嵌入式搜索内核（`SearchKernel/`），编译为进程内C-ABI侧车。

**职责**：
- 中文/全文候选检索（Jieba/CJK分词）
- Tantivy索引模式和查询执行
- C ABI供Swift进程内调用

---

## 七、存储层

### 7.1 SQLite存储

**数据库路径**：`~/Library/Application Support/Connor/graph/connor.sqlite`

**Schema版本**：6

**所需表**（38个）：
- L0：`memory_l0_provenance_objects`, `memory_l0_provenance_spans`, `memory_l0_derivations`, `memory_l0_content_hashes`
- L1：`memory_l1_capture_events`, `memory_l1_time_blocks`, `memory_l1_processing_queue`, `memory_l1_dead_letter_queue`
- L2：`memory_l2_nodes`, `memory_l2_edges`, `memory_l2_statements`, `memory_l2_episodes`
- L3：`memory_l3_beliefs`, `memory_l3_belief_evidence`, `memory_l3_belief_relations`
- L4：`memory_l4_entities`, `memory_l4_entity_aliases`, `memory_l4_entity_statements`
- 全文搜索：`memory_l0_provenance_fts`, `memory_l2_nodes_fts`, `memory_l2_statements_fts`, `memory_l3_beliefs_fts`, `memory_l4_entities_fts`, `memory_l4_statements_fts`

**所需索引**（23个）：
- 时间索引、状态索引、外键索引、全文搜索索引等

### 7.2 查询缓存

**内存LRU缓存**（`MemoryOSQueryCache`）：
- 线程安全
- 可配置容量和TTL
- 当前用户配置文件缓存（长TTL）

---

## 八、使用方法

### 8.1 基本使用流程

1. **获取当前时间**（任务启动工作流）：
   ```
   get_current_time
   ```

2. **检索近期与知识上下文**：
   ```
   memory_os_recent_context(query: "搜索词1;搜索词2", page: 1)
   memory_os_knowledge_context(query: "搜索词1;搜索词2", page: 1, depth: 1)
   ```

3. **获取用户配置文件**：
   ```
   memory_os_get_current_user_profile()
   ```

4. **后台低层搜索（主会话不注册）**：
   ```
   memory_os_search(query: "搜索查询", layers: ["L2", "L3", "L4"], limit: 20)
   ```

5. **写入L2实体**：
   ```
   memory_os_l2_update_entities(entities: [{
     name: "实体名称",
     type: "concept",
     summary: "摘要",
     statements: [{text: "语句内容", relation: "RELATED_TO"}]
   }])
   ```

6. **写入当前用户事实**：
   ```
   memory_os_update_current_user_profile(facts: [{
     statement: "事实内容",
     factType: "profile_preference",
     relation: "PREFERS"
   }])
   ```

7. **写入L3知识**：
   ```
   memory_os_l3_update_beliefs(beliefs: [{
     statement: "知识声明",
     domain: "computer-science",
     relatedEntityNames: "实体1, 实体2"
   }])
   ```

8. **写入L4实体和关系**：
   ```
   memory_os_l4_update_entities(
     entities: [{
       name: "实体名称",
       entityType: "concept",
       summary: "摘要"
     }],
     relations: [{
       subjectName: "主语实体",
       predicate: "INSTANCE_OF",
       objectName: "宾语实体",
       text: "关系描述"
     }]
   )
   ```

### 8.2 CLI命令

```bash
# 查看帮助
swift run connor --help

# 查看Memory OS状态
swift run connor memory --help

# 查看待处理L1事件
swift run connor memory l1 pending

# 用当前模型规范化并摄取一条CLI测试用户消息
swift run connor memory ingest-chat --content "请记住：L1端到端测试标记为 MEMORY-L1-E2E"

# 摄取一条助手消息以构造完整对话；该路径不调用用户意图规范化
swift run connor memory ingest-chat --role assistant --content "这里是需要参与L1提取的助手回复"

# 按生产阈值触发L1投影
swift run connor memory pipeline plan-l1

# 测试时仅对本次规划覆盖阈值，不修改生产策略
swift run connor memory pipeline plan-l1 --min-pending-count 1

# 用当前CLI模型连接实时执行下一个后台作业
swift run connor memory pipeline debug-run-next --format text

# 查看运行消息
swift run connor memory run <run-id> messages

# 查看工具调用
swift run connor memory run <run-id> tool-calls
```

`ingest-chat` 还支持 `--role user|assistant`、`--file <path>`、`--session-id <id>`、`--message-id <id>` 和仅用于诊断的 `--normalization-timeout-seconds <秒>`。默认角色为 `user`：命令返回规范化状态、`retrieval_text`、模型ID、L0 provenance ID 和 L1 capture ID；规范化失败时仍保存 L0 原文，但 L1 `retrieval_text` 为空。`assistant` 角色用于构造端到端测试对话，保存完整原文但不调用用户意图规范化。超时覆盖只影响本次CLI用户消息调用，生产写入默认上限仍为 60 秒；特殊模型可在测试时单次设置为 100 秒。

L1 后台知识提取会把用户指令和话语、助手消息及网页、邮件、日历、RSS 等外部知识性数据统一放入按时间排序的输入包，并从 L0 读取完整原文。它们是同等重要的历史参考信息：系统不得因来源忽略、降级或优先处理任何一类，也不设置来源权重、优先级或 `context_only`；用户历史指令仍是重要信息，但不构成当前命令。模型从全面上下文中自行判断应写入 L2、L3 或 L4。每条事件保留 `source_kind`，但它只用于理解语义和正确归因，不决定信息能否被提取。

`plan-l1` 的 `--min-pending-count`、`--max-events-per-block` 和 `--max-tokens-per-block` 只影响本次CLI调用，适合端到端验收，不会更改 `MemoryOSL1ProcessingTriggerPolicy` 的生产默认值。

### 8.3 运行时布局

```
Connor/
├── config/                    # 配置文件
│   ├── session-governance.json
│   ├── product-os-registry.json
│   ├── runtime-settings.json
│   └── llm-settings.json
├── sessions/                  # 会话数据
│   └── {sessionID}/
│       ├── manifest.json
│       ├── state/
│       ├── browser/
│       ├── plans/
│       ├── data/
│       ├── attachments/
│       ├── exports/
│       └── logs/
├── sources/                   # 数据源配置
├── skills/                    # 技能包
├── tasks/                     # 任务定义
├── labels/                    # 标签
├── statuses/                  # 状态定义
├── artifacts/                 # 产物
├── search/                    # 搜索索引
│   └── native-source-index.json
├── graph/                     # 图数据库
│   ├── connor.sqlite          # SQLite数据库
│   ├── indexes/
│   ├── search-index/
│   │   └── memory-os-tantivy/
│   ├── exports/
│   ├── snapshots/
│   └── evaluations/
└── logs/                      # 日志
    ├── audit/
    └── runtime/
```

---

## 九、关键设计原则

1. **记忆系统是后台认知基础设施**：不是普通用户的前台图谱编辑器
2. **本地优先**：所有数据存储在本地SQLite数据库
3. **证据追溯**：L0层保留永久证据，支持完整追溯
4. **查询时推导当前性**：历史语义记录是追加式的；当前性通过查询时逻辑推导
5. **受控词汇表**：L4实体类型使用41种受控类型，80+个别名映射
6. **双写路径**：LLM实时写入 + L1缓存批量投影
7. **预算控制**：上下文构建有严格的预算限制（8000字符、16块等）
8. **图引导发现**：通过关系卡片发现实体间连接，支持假设生成和验证

---

## 十、总结

康纳同学的记忆系统是一个完整的、生产级的五层记忆架构，通过17个LLM工具提供读写接口，支持：
- 原始证据保留（L0）
- 事件累积和批量处理（L1）
- 实体中心工作记忆（L2）
- 可复用知识层（L3）
- 稳定实体和概念图谱（L4）

系统通过混合检索（词汇+语义+图）提供上下文，支持智能的上下文预算控制和优先级排序，是一个强大的AI助手记忆基础设施。
