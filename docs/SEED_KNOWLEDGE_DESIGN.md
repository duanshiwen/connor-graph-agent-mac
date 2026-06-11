# Connor Graph Agent — 种子知识设计方案

> 文档日期：2026-06-11
> 目标：以最小体积（~30-50KB）提供最大启动价值

---

## 1. 现状分析

### 已有
- 58 个本体类（3 层：general / personal-life / knowledge-project）
- 基础约束验证器（时间范围、自环、justification、class 类型检查）
- GraphPredicate 枚举（~50 个谓词，含 edgeKind / transitive / symmetric / inverse 属性）

### 缺失
- ❌ 本体类之间的层次关系（SUBCLASS_OF 语句）
- ❌ 自模型（agent 自身、能力、限制）
- ❌ 用户模型（用户实体、偏好、上下文）
- ❌ 时间/空间原语（今天、本周、当前位置）
- ❌ 谓词约束（domain/range、基数、时态）
- ❌ 推理脚手架（传递性、矛盾检测模式、推断规则）
- ❌ 常见实体种子（高频出现的核心概念）

---

## 2. 种子知识分层设计

### Layer 0: 元知识（Meta-Knowledge）— 最高优先级

**目标**：让 agent 理解自己是谁、能做什么、不能做什么。

#### 实体（5 个）

| ID | 名称 | Kind | 说明 |
|---|---|---|---|
| `self:agent` | Connor Agent | entity | agent 自身 |
| `self:user` | User | person_object | 用户 |
| `self:graph` | Knowledge Graph | concept | agent 的知识图谱 |
| `self:session` | Current Session | concept | 当前会话 |
| `self:memory` | Memory System | concept | 记忆系统 |

#### 语句（~12 条）

```
self:agent  INSTANCE_OF  class:person         # agent 是一种 person_object（元认知）
self:agent  RELATED_TO   self:graph            # agent 关联知识图谱
self:agent  RELATED_TO   self:memory           # agent 关联记忆系统
self:user   PREFERS      (metadata: language=zh, timezone=Asia/Shanghai)
self:user   RELATED_TO   self:agent            # 用户使用 agent
self:graph  HAS_PART     class:entity          # 图谱包含实体
self:graph  HAS_PART     class:statement       # 图谱包含语句
self:graph  HAS_PART     class:episode         # 图谱包含事件
self:memory DEPENDS_ON   self:graph            # 记忆依赖图谱
self:session ABOUT        self:user             # 会话关于用户
self:session PART_OF      self:memory           # 会话是记忆的一部分
```

#### 约束规则（3 条）

```
SELF_MODEL_NO_SELF_REFERENCE: agent 不能 SUBCLASS_OF 自己
USER_PREFERENCE_CONSISTENCY: 用户偏好不能自相矛盾
SESSION_SINGLE_USER: 一个 session 只能 ABOUT 一个 user
```

---

### Layer 1: 本体层次关系（Ontology Hierarchy）— 高优先级

**目标**：将 58 个本体类组织成层次结构，支持传递性推理。

#### 层次结构（~60 条 SUBCLASS_OF 语句）

**general 层次：**
```
person         SUBCLASS_OF  entity
organization   SUBCLASS_OF  entity
location       SUBCLASS_OF  entity
event          SUBCLASS_OF  entity
artifact       SUBCLASS_OF  entity
software       SUBCLASS_OF  artifact
hardware       SUBCLASS_OF  artifact
concept        SUBCLASS_OF  entity
data_structure SUBCLASS_OF  concept
process        SUBCLASS_OF  concept
metric         SUBCLASS_OF  concept
time_expression SUBCLASS_OF concept
publication    SUBCLASS_OF  artifact
law_policy     SUBCLASS_OF  concept
natural_object SUBCLASS_OF  entity
```

**personal-life 层次：**
```
email                SUBCLASS_OF  communication_object
message              SUBCLASS_OF  communication_object
conversation_thread  SUBCLASS_OF  communication_object
contact              SUBCLASS_OF  person_object
calendar_event       SUBCLASS_OF  calendar_object
reminder             SUBCLASS_OF  calendar_object
task                 SUBCLASS_OF  work_object
commitment           SUBCLASS_OF  work_object
preference           SUBCLASS_OF  concept
habit                SUBCLASS_OF  concept
goal                 SUBCLASS_OF  concept
address              SUBCLASS_OF  location
home                 SUBCLASS_OF  location
family_member        SUBCLASS_OF  person_object
bill                 SUBCLASS_OF  document
subscription         SUBCLASS_OF  document
health_record        SUBCLASS_OF  document
device               SUBCLASS_OF  artifact
account              SUBCLASS_OF  artifact
credential_reference SUBCLASS_OF  artifact
purchase             SUBCLASS_OF  event
travel_plan          SUBCLASS_OF  calendar_object
meal                 SUBCLASS_OF  event
exercise             SUBCLASS_OF  event
```

**knowledge-project 层次：**
```
question         SUBCLASS_OF  concept
answer           SUBCLASS_OF  concept
decision         SUBCLASS_OF  concept
sop              SUBCLASS_OF  document
runbook          SUBCLASS_OF  document
work_object      SUBCLASS_OF  concept
project          SUBCLASS_OF  work_object
milestone        SUBCLASS_OF  work_object
issue            SUBCLASS_OF  work_object
repository       SUBCLASS_OF  artifact
code_module      SUBCLASS_OF  artifact
design_doc       SUBCLASS_OF  document
research_note    SUBCLASS_OF  document
source_document  SUBCLASS_OF  document
claim            SUBCLASS_OF  concept
argument         SUBCLASS_OF  concept
constraint       SUBCLASS_OF  concept
risk             SUBCLASS_OF  concept
requirement      SUBCLASS_OF  concept
```

#### 需要补充的本体类（~5 个）

```swift
// 添加到 baseOntologySpecs()
("entity", "entity", -1, "meta", .classNode)              // 根类
("communication_object", "communication object", 0, "general", .classNode)
("calendar_object", "calendar object", 0, "general", .classNode)
("person_object", "person object", 0, "general", .classNode)
("work_object", "work object", 0, "general", .classNode)
("document", "document", 0, "general", .classNode)
```

---

### Layer 2: 谓词约束（Predicate Constraints）— 高优先级

**目标**：定义每个谓词的合法 subject/object 类型，防止无效写入。

#### Domain/Range 约束（~30 条）

| 谓词 | Subject Domain | Object Range | 说明 |
|---|---|---|---|
| SUBCLASS_OF | classNode | classNode | ✅ 已有 |
| INSTANCE_OF | entity | classNode | ✅ 已有 |
| ALIAS_OF | entity | entity | 同一实体的别名 |
| SAME_AS | entity | entity | 跨图谱等价 |
| PART_OF | entity | entity | 部分-整体 |
| HAS_PART | entity | entity | 整体-部分 |
| DEPENDS_ON | entity | entity | 依赖关系 |
| RELATED_TO | entity | entity | 通用关联 |
| CREATED_BY | artifact | person_object | 创建者 |
| DEVELOPED_BY | software | organization | 开发者 |
| OWNED_BY | entity | entity | 所有者 |
| LOCATED_IN | entity | location | 位置 |
| OCCURRED_AT | event | location | 发生地点 |
| SCHEDULED_AT | calendar_object | time_expression | 计划时间 |
| STARTS_AT | event | time_expression | 开始时间 |
| ENDS_AT | event | time_expression | 结束时间 |
| PREFERS | person_object | concept | 偏好 |
| DISLIKES | person_object | concept | 不喜欢 |
| HAS_HABIT | person_object | habit | 习惯 |
| HAS_GOAL | person_object | goal | 目标 |
| COMMITTED_TO | person_object | commitment | 承诺 |
| RESPONSIBLE_FOR | person_object | task | 负责 |
| SENT_BY | communication_object | person_object | 发送者 |
| SENT_TO | communication_object | person_object | 接收者 |
| ABOUT | communication_object | entity | 关于 |
| MENTIONS | communication_object | entity | 提及 |
| ATTENDS | person_object | calendar_object | 参加 |
| ORGANIZER_OF | calendar_object | person_object | 组织者 |
| ASSIGNED_TO | task | person_object | 分配给 |
| DUE_AT | task | time_expression | 截止时间 |
| ANSWERS | answer | question | 回答 |
| DERIVED_FROM | entity | entity | 来源 |
| IMPLEMENTS | code_module | requirement | 实现 |
| SUPERSEDES | entity | entity | 取代 |

#### 实现方式

在 `GraphConstraintValidator` 中添加 domain/range 检查：

```swift
struct PredicateConstraint {
    let predicate: GraphPredicate
    let subjectKinds: Set<GraphEntityKind>  // 允许的 subject 类型
    let objectKinds: Set<GraphEntityKind>   // 允许的 object 类型
    let subjectClassIDs: Set<String>?       // 可选：限制 subject 的 canonicalClassID
    let objectClassIDs: Set<String>?        // 可选：限制 object 的 canonicalClassID
}
```

---

### Layer 3: 时间/空间原语（Temporal/Spatial Primitives）— 中优先级

**目标**：提供时间锚点和位置上下文，支持日历和任务推理。

#### 实体（~8 个）

| ID | 名称 | Kind | 说明 |
|---|---|---|---|
| `temporal:today` | Today | time_expression | 动态锚点，每日更新 |
| `temporal:this_week` | This Week | time_expression | 动态锚点 |
| `temporal:this_month` | This Month | time_expression | 动态锚点 |
| `temporal:now` | Now | time_expression | 动态锚点 |
| `spatial:home` | Home | location | 用户家 |
| `spatial:work` | Work | location | 用户工作地点 |
| `spatial:current` | Current Location | location | 动态锚点 |
| `status:active` | Active | concept | 状态：活跃 |
| `status:pending` | Pending | concept | 状态：待处理 |
| `status:done` | Done | concept | 状态：已完成 |

#### 动态更新机制

时间锚点需要每日/每周/每月更新。在 `AppGraphBootstrapper` 中添加：

```swift
func refreshTemporalAnchors(graphID: String) throws {
    let now = Date()
    let calendar = Calendar.current
    
    // 更新 today
    try store.upsert(entity: GraphEntity(
        id: "temporal:today",
        graphID: graphID,
        name: "Today",
        entityKind: .timeExpression,
        scope: .publicScope,
        summary: calendar.startOfDay(for: now).ISO8601Format(),
        metadata: ["type": "temporal_anchor", "precision": "day"]
    ))
    
    // 类似更新 this_week, this_month, now
}
```

---

### Layer 4: 推理脚手架（Reasoning Scaffolds）— 中优先级

**目标**：定义常见推理模式，让 agent 能从已有知识推导新知识。

#### 传递性推理（3 条规则）

```swift
// SUBCLASS_OF 传递性
// 如果 A SUBCLASS_OF B 且 B SUBCLASS_OF C，则 A SUBCLASS_OF C
// ✅ 已有 isTransitive 标记

// PART_OF 传递性
// 如果 A PART_OF B 且 B PART_OF C，则 A PART_OF C
// ✅ 已有 isTransitive 标记

// DEPENDS_ON 传递性
// 如果 A DEPENDS_ON B 且 B DEPENDS_ON C，则 A DEPENDS_ON C
// ✅ 已有 isTransitive 标记
```

#### 推断规则（~7 条）

```swift
enum InferenceRule: String, Codable {
    case locationInheritance
    // 如果 A LOCATED_IN B 且 B PART_OF C，则 A LOCATED_IN C
    // 例：卧室 LOCATED_IN 家，家 LOCATED_IN 杭州 → 卧室 LOCATED_IN 杭州
    
    case creatorOwnership
    // 如果 A CREATED_BY B，则 A RELATED_TO B（弱推断）
    
    case temporalContainment
    // 如果 A STARTS_AT T1 且 A ENDS_AT T2 且 T1 <= now <= T2，则 A is "active"
    
    case taskResponsibility
    // 如果 A ASSIGNED_TO B 且 A DUE_AT T，则 B RESPONSIBLE_FOR A
    
    case communicationAbout
    // 如果 A ABOUT B 且 A MENTIONS C，则 B RELATED_TO C（弱推断）
    
    case familySymmetry
    // 如果 A FAMILY_OF B，则 B FAMILY_OF A
    // ✅ 已有 isSymmetric 标记
    
    case goalDecomposition
    // 如果 A HAS_GOAL B 且 B DEPENDS_ON C，则 A RELATED_TO C
}
```

#### 矛盾检测模式（~5 条）

```swift
enum ContradictionPattern: String, Codable {
    case temporalOverlap
    // 两个 calendar_event 在同一时间段且 CONFLICTS_WITH
    
    case statusInconsistency
    // entity 同时有 status:active 和 status:done
    
    case preferenceContradiction
    // person 同时 PREFERS 和 DISLIKES 同一个 concept
    
    case assignmentConflict
    // 同一个 task ASSIGNED_TO 两个不同 person
    
    case locationImpossibility
    // 同一实体在同一时间 LOCATED_IN 两个不同 location（除非有 MENTIONS 关系）
}
```

---

### Layer 5: 高频实体种子（Frequent Entity Seeds）— 低优先级

**目标**：预置常见实体，减少首次交互的提取负担。

#### 通信相关（~5 个）

| ID | 名称 | Kind | 说明 |
|---|---|---|---|
| `seed:inbox` | Inbox | concept | 收件箱 |
| `seed:sent` | Sent | concept | 已发送 |
| `seed:drafts` | Drafts | concept | 草稿 |
| `seed:archive` | Archive | concept | 归档 |
| `seed:trash` | Trash | concept | 垃圾箱 |

#### 任务状态（~5 个）

| ID | 名称 | Kind | 说明 |
|---|---|---|---|
| `seed:todo` | To Do | concept | 待办 |
| `seed:in_progress` | In Progress | concept | 进行中 |
| `seed:blocked` | Blocked | concept | 阻塞 |
| `seed:review` | In Review | concept | 审核中 |
| `seed:completed` | Completed | concept | 已完成 |

#### 常见关系（~3 条）

```
seed:inbox    INSTANCE_OF  class:email
seed:sent     INSTANCE_OF  class:email
seed:drafts   INSTANCE_OF  class:email
```

---

## 3. 实现优先级

### Phase 1: 最小可用（~15KB）
1. ✅ 自模型（5 实体 + 12 语句）
2. ✅ 本体层次关系（60 语句）
3. ✅ 补充 5 个缺失的本体类

### Phase 2: 约束强化（~10KB）
4. ✅ 谓词 domain/range 约束（30 规则）
5. ✅ 矛盾检测模式（5 规则）

### Phase 3: 推理能力（~10KB）
6. ✅ 推断规则（7 规则）
7. ✅ 时间/空间原语（8 实体）

### Phase 4: 体验优化（~5KB）
8. ✅ 高频实体种子（10 实体 + 3 语句）

---

## 4. 存储格式

### 方案 A: JSON 种子文件（推荐）

```
Sources/ConnorGraphStore/Seeds/
├── seed_ontology_hierarchy.json    # 本体层次
├── seed_self_model.json            # 自模型
├── seed_predicate_constraints.json # 谓词约束
├── seed_inference_rules.json       # 推断规则
├── seed_contradiction_patterns.json # 矛盾模式
├── seed_temporal_primitives.json   # 时间原语
└── seed_frequent_entities.json     # 高频实体
```

**优点**：
- 可读性强，易于维护
- 可以版本化（git）
- 可以按需加载（只加载 Phase 1）

**体积估算**：
- Phase 1: ~15KB
- Phase 1+2: ~25KB
- Phase 1+2+3: ~35KB
- 全部: ~40KB

### 方案 B: Swift 枚举/结构体

将种子数据硬编码在 Swift 代码中。

**优点**：
- 编译时检查
- 无文件 I/O
- 类型安全

**缺点**：
- 可读性差
- 修改需要重新编译
- 代码膨胀

### 方案 C: SQLite 预填充数据库

创建一个预填充的 SQLite 数据库文件，安装时复制。

**优点**：
- 零启动时间
- 无解析开销

**缺点**：
- 二进制文件不可 diff
- 更新困难

**推荐方案 A**，理由：
1. 体积小（~40KB），不影响安装包
2. 可读可维护
3. 可以渐进加载
4. 可以版本化

---

## 5. 加载流程

```swift
// AppGraphBootstrapper.swift

func bootstrapStore() throws -> SQLiteGraphKernelStore {
    // ... 现有代码 ...
    
    // Phase 1: 种子本体层次
    try seedOntologyHierarchy(store: store, graphID: "default")
    
    // Phase 2: 自模型
    try seedSelfModel(store: store, graphID: "default")
    
    // Phase 3: 谓词约束
    try loadPredicateConstraints(store: store)
    
    // Phase 4: 推断规则
    try loadInferenceRules(store: store)
    
    // Phase 5: 时间原语
    try seedTemporalPrimitives(store: store, graphID: "default")
    
    return store
}
```

---

## 6. 体积预算

| 组件 | 实体 | 语句 | 约束 | 估算体积 |
|---|---|---|---|---|
| 自模型 | 5 | 12 | 3 | ~3KB |
| 本体层次 | 0 | 60 | 0 | ~8KB |
| 谓词约束 | 0 | 0 | 30 | ~5KB |
| 推断规则 | 0 | 0 | 7 | ~3KB |
| 矛盾模式 | 0 | 0 | 5 | ~2KB |
| 时间原语 | 8 | 0 | 0 | ~2KB |
| 高频实体 | 10 | 3 | 0 | ~3KB |
| **合计** | **23** | **75** | **45** | **~26KB** |

压缩后（gzip）预计 **~8-10KB**，完全不影响安装包大小。

---

## 7. 验证清单

- [ ] 所有 SUBCLASS_OF 语句的 subject/object 都是 classNode
- [ ] 所有 INSTANCE_OF 语句的 object 都是 classNode
- [ ] 谓词约束的 domain/range 类型都存在于本体类中
- [ ] 推断规则不会导致无限循环（检查传递性边界）
- [ ] 矛盾检测模式不会产生误报（检查边界条件）
- [ ] 时间原语的动态更新不会破坏已有语句
- [ ] 种子实体的 ID 不会与用户创建的实体冲突（使用 `self:` / `seed:` / `temporal:` / `spatial:` 前缀）
