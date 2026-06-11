# Wikidata 种子实体推荐方案

> 文档日期：2026-06-11
> 目标：为 Connor Graph Agent 推荐一组 Wikidata 基础对象，用于初始化图谱

---

## 1. 设计原则

1. **映射到现有枚举**：每个 Wikidata 实体必须能映射到 `GraphEntityKind` 或 `GraphPredicate`
2. **高频引用**：选择 Wikidata 中使用量最高的实体/属性
3. **层次清晰**：从根到叶，形成可传递推理的层次结构
4. **体积最小**：~50 个实体 + ~30 个属性映射，压缩后 ~15KB

---

## 2. 推荐实体清单

### 2.1 根类型（Root Types）— 7 个

| Wikidata ID | 中文名 | 英文名 | 映射到 GraphEntityKind | 说明 |
|---|---|---|---|---|
| Q35120 | 实体 | entity | classNode (layer -1) | 万物根类 |
| Q35120 | 物 | thing | classNode (layer -1) | 实体的别名 |
| Q120077072 | 某物 | something | classNode (layer 0) | 不确定实体 |
| Q121770302 | 概念实体 | conceptual entity | classNode (layer 0) | 抽象概念 |
| Q115095765 | 位置 | location | classNode (layer 0) | 空间位置 |
| Q23958946 | 个体实体 | individual entity | classNode (layer 0) | 具体实例 |
| Q15893266 | 前实体 | former entity | classNode (layer 0) | 已不存在的实体 |

### 2.2 核心实体类（Core Entity Classes）— 20 个

| Wikidata ID | 中文名 | 英文名 | 映射到 GraphEntityKind | Wikidata 使用量 |
|---|---|---|---|---|
| Q5 | 人 | human | person_object | ~11M |
| Q215627 | 人 | person | person_object | ~1M |
| Q43229 | 组织 | organization | entity | ~800K |
| Q17334923 | 位置 | location | place | ~500K |
| Q1190554 | 事件 | occurrence | event | ~400K |
| Q47461344 | 作品 | work | artifact | ~300K |
| Q7725634 | 文学作品 | literary work | document | ~200K |
| Q732577 | 出版物 | publication | document | ~150K |
| Q13442814 | 学术论文 | scholarly article | document | ~100K |
| Q515 | 城市 | city | place | ~5M |
| Q6256 | 国家 | country | place | ~1M |
| Q56061 | 行政区划 | administrative territorial entity | place | ~500K |
| Q1549591 | 大城市 | big city | place | ~100K |
| Q7397 | 软件 | software | artifact | ~200K |
| Q167270 | 网站 | website | artifact | ~100K |
| Q11424 | 电影 | film | artifact | ~500K |
| Q5398426 | 电视剧 | television series | artifact | ~200K |
| Q215380 | 乐队 | musical group | person_object | ~100K |
| Q482994 | 专辑 | album | artifact | ~100K |
| Q134556 | 单曲 | single | artifact | ~100K |

### 2.3 核心属性（Core Properties）— 30 个

| Wikidata ID | 中文名 | 英文名 | 映射到 GraphPredicate | 使用量 | 数据类型 |
|---|---|---|---|---|---|
| P31 | 实例 of | instance of | INSTANCE_OF | 98M | WikibaseItem |
| P279 | 子类 of | subclass of | SUBCLASS_OF | 3M | WikibaseItem |
| P17 | 国家 | country | LOCATED_IN (partial) | 14M | WikibaseItem |
| P131 | 位于行政区域 | located in administrative territorial entity | LOCATED_IN | 11M | WikibaseItem |
| P276 | 位置 | location | LOCATED_IN | 2M | WikibaseItem |
| P27 | 国籍 | country of citizenship | metadata | 4M | WikibaseItem |
| P19 | 出生地 | place of birth | LOCATED_IN | 3M | WikibaseItem |
| P569 | 出生日期 | date of birth | metadata (time) | 5M | Time |
| P570 | 死亡日期 | date of death | metadata (time) | 3M | Time |
| P580 | 开始时间 | start time | STARTS_AT | 7M | Time |
| P582 | 结束时间 | end time | ENDS_AT | 4M | Time |
| P585 | 时间点 | point in time | metadata (time) | 9M | Time |
| P577 | 出版日期 | publication date | metadata (time) | 52M | Time |
| P625 | 坐标位置 | coordinate location | metadata (coordinate) | 9M | GlobeCoordinate |
| P106 | 职业 | occupation | INSTANCE_OF (partial) | 8M | WikibaseItem |
| P21 | 性别 | sex or gender | metadata | 7M | WikibaseItem |
| P735 | 名字 | given name | metadata | 6M | WikibaseItem |
| P734 | 姓氏 | family name | metadata | 3M | WikibaseItem |
| P50 | 作者 | author | CREATED_BY | 21M | WikibaseItem |
| P361 | 属于 | part of | PART_OF | 4M | WikibaseItem |
| P527 | 有部分 | has part | HAS_PART | 2M | WikibaseItem |
| P171 | 父分类 | parent taxon | SUBCLASS_OF (partial) | 3M | WikibaseItem |
| P407 | 语言 | language of work or name | metadata | 18M | WikibaseItem |
| P18 | 图片 | image | metadata | 4M | CommonsMedia |
| P154 | 图片标志 | logo image | metadata | 1M | CommonsMedia |
| P910 | 主题分类 | topic's main category | metadata | 1M | WikibaseItem |
| P373 | Commons 分类 | Commons category | metadata | 3M | String |
| P646 | Freebase ID | Freebase ID | metadata (external) | 4M | ExternalId |
| P214 | VIAF ID | VIAF ID | metadata (external) | 7M | ExternalId |
| P227 | GND ID | GND ID | metadata (external) | 2M | ExternalId |

### 2.4 地理锚点（Geographic Anchors）— 10 个

| Wikidata ID | 中文名 | 英文名 | 类型 | 说明 |
|---|---|---|---|---|
| Q2 | 地球 | Earth | place | 人类居住的星球 |
| Q30 | 美国 | United States | place | 最常用国家 |
| Q148 | 中国 | China | place | 用户所在国家 |
| Q183 | 德国 | Germany | place | 欧洲核心国家 |
| Q145 | 英国 | United Kingdom | place | 英语国家 |
| Q17 | 日本 | Japan | place | 东亚国家 |
| Q142 | 法国 | France | place | 欧洲国家 |
| Q155 | 巴西 | Brazil | place | 南美洲国家 |
| Q159 | 俄罗斯 | Russia | place | 最大国家 |
| Q668 | 印度 | India | place | 人口大国 |

### 2.5 时间/历法锚点（Temporal Anchors）— 5 个

| Wikidata ID | 中文名 | 英文名 | 类型 | 说明 |
|---|---|---|---|---|
| Q573 | 日期 | date | time_expression | 日期概念 |
| Q186158 | 时间段 | period of time | time_expression | 时间区间 |
| Q205892 | 日历日 | calendar day | time_expression | 日历天 |
| Q131191 | 月份 | month | time_expression | 月份 |
| Q3186687 | 年份 | year | time_expression | 年份 |

---

## 3. Wikidata → GraphPredicate 映射表

```swift
// 在 GraphKernelDomain.swift 中添加映射

public extension GraphPredicate {
    /// Wikidata 属性 ID 到 GraphPredicate 的映射
    static let wikidataMapping: [String: GraphPredicate] = [
        "P31": .instanceOf,
        "P279": .subclassOf,
        "P17": .locatedIn,          // country → LOCATED_IN
        "P131": .locatedIn,         // located in administrative territorial entity
        "P276": .locatedIn,         // location
        "P19": .locatedIn,          // place of birth
        "P361": .partOf,            // part of
        "P527": .hasPart,           // has part
        "P50": .createdBy,          // author
        "P171": .subclassOf,        // parent taxon (生物分类)
        "P580": .startsAt,          // start time
        "P582": .endsAt,            // end time
        "P585": .scheduledAt,       // point in time
        "P577": .scheduledAt,       // publication date
        "P569": .scheduledAt,       // date of birth → time
        "P570": .scheduledAt,       // date of death → time
        "P27": .relatedTo,          // country of citizenship → RELATED_TO
        "P106": .instanceOf,        // occupation → INSTANCE_OF
        "P21": .relatedTo,          // sex or gender → RELATED_TO
        "P735": .relatedTo,         // given name → RELATED_TO
        "P734": .relatedTo,         // family name → RELATED_TO
        "P407": .relatedTo,         // language → RELATED_TO
        "P18": .relatedTo,          // image → RELATED_TO
        "P646": .relatedTo,         // Freebase ID → RELATED_TO
        "P214": .relatedTo,         // VIAF ID → RELATED_TO
        "P227": .relatedTo,         // GND ID → RELATED_TO
    ]
}
```

---

## 4. Wikidata → GraphEntityKind 映射表

```swift
// 在 GraphKernelDomain.swift 中添加映射

public extension GraphEntityKind {
    /// Wikidata Q-item 到 GraphEntityKind 的映射
    static let wikidataMapping: [String: GraphEntityKind] = [
        "Q5": .personObject,           // human
        "Q215627": .personObject,      // person
        "Q43229": .entity,             // organization
        "Q17334923": .place,           // location
        "Q1190554": .event,            // occurrence
        "Q47461344": .artifact,        // work
        "Q7725634": .document,         // literary work
        "Q732577": .document,          // publication
        "Q13442814": .document,        // scholarly article
        "Q515": .place,                // city
        "Q6256": .place,               // country
        "Q56061": .place,              // administrative territorial entity
        "Q7397": .artifact,            // software
        "Q167270": .artifact,          // website
        "Q11424": .artifact,           // film
        "Q5398426": .artifact,         // television series
        "Q215380": .personObject,      // musical group
        "Q482994": .artifact,          // album
        "Q134556": .artifact,          // single
    ]
}
```

---

## 5. 实现方案

### 5.1 数据结构

```swift
/// Wikidata 种子实体
struct WikidataSeedEntity: Codable, Sendable {
    let qid: String              // Wikidata Q-item ID (e.g., "Q5")
    let label_zh: String         // 中文标签
    let label_en: String         // 英文标签
    let description_zh: String   // 中文描述
    let graphEntityKind: GraphEntityKind
    let canonicalClassID: String? // 映射到的本体类 ID
    let aliases: [String]
    let metadata: [String: String]
}

/// Wikidata 种子属性
struct WikidataSeedProperty: Codable, Sendable {
    let pid: String              // Wikidata P-item ID (e.g., "P31")
    let label_zh: String
    let label_en: String
    let graphPredicate: GraphPredicate
    let domainEntityKinds: [GraphEntityKind]
    let rangeEntityKinds: [GraphEntityKind]
    let isTransitive: Bool
    let isSymmetric: Bool
    let inversePID: String?      // 反向属性 ID
}
```

### 5.2 种子数据文件

```
Sources/ConnorGraphStore/Seeds/
├── wikidata_root_types.json        # 根类型 (7 entities)
├── wikidata_core_classes.json      # 核心实体类 (20 entities)
├── wikidata_core_properties.json   # 核心属性 (30 properties)
├── wikidata_geographic_anchors.json # 地理锚点 (10 entities)
└── wikidata_temporal_anchors.json   # 时间锚点 (5 entities)
```

### 5.3 加载流程

```swift
// AppGraphBootstrapper.swift

func seedWikidataEntities(store: SQLiteGraphKernelStore, graphID: String) throws {
    // 1. 加载根类型
    let rootTypes = try loadJSON("wikidata_root_types.json", as: [WikidataSeedEntity].self)
    for entity in rootTypes {
        try store.upsert(entity: entity.toGraphEntity(graphID: graphID))
    }
    
    // 2. 加载核心实体类
    let coreClasses = try loadJSON("wikidata_core_classes.json", as: [WikidataSeedEntity].self)
    for entity in coreClasses {
        try store.upsert(entity: entity.toGraphEntity(graphID: graphID))
    }
    
    // 3. 加载地理锚点
    let geoAnchors = try loadJSON("wikidata_geographic_anchors.json", as: [WikidataSeedEntity].self)
    for entity in geoAnchors {
        try store.upsert(entity: entity.toGraphEntity(graphID: graphID))
    }
    
    // 4. 加载时间锚点
    let temporalAnchors = try loadJSON("wikidata_temporal_anchors.json", as: [WikidataSeedEntity].self)
    for entity in temporalAnchors {
        try store.upsert(entity: entity.toGraphEntity(graphID: graphID))
    }
    
    // 5. 建立层次关系（SUBCLASS_OF）
    try buildWikidataHierarchy(store: store, graphID: graphID)
}
```

### 5.4 层次关系（~15 条 SUBCLASS_OF）

```
Q5 (human)             SUBCLASS_OF  Q35120 (entity)
Q215627 (person)       SUBCLASS_OF  Q35120 (entity)
Q43229 (organization)  SUBCLASS_OF  Q35120 (entity)
Q17334923 (location)   SUBCLASS_OF  Q35120 (entity)
Q1190554 (occurrence)  SUBCLASS_OF  Q35120 (entity)
Q47461344 (work)       SUBCLASS_OF  Q35120 (entity)
Q7725634 (literary work) SUBCLASS_OF Q47461344 (work)
Q732577 (publication)  SUBCLASS_OF  Q47461344 (work)
Q13442814 (scholarly article) SUBCLASS_OF Q732577 (publication)
Q515 (city)            SUBCLASS_OF  Q17334923 (location)
Q6256 (country)        SUBCLASS_OF  Q17334923 (location)
Q56061 (admin entity)  SUBCLASS_OF  Q17334923 (location)
Q7397 (software)       SUBCLASS_OF  Q47461344 (work)
Q167270 (website)      SUBCLASS_OF  Q47461344 (work)
Q11424 (film)          SUBCLASS_OF  Q47461344 (work)
Q5398426 (TV series)   SUBCLASS_OF  Q47461344 (work)
Q215380 (musical group) SUBCLASS_OF Q43229 (organization)
Q482994 (album)        SUBCLASS_OF  Q47461344 (work)
Q134556 (single)       SUBCLASS_OF  Q47461344 (work)
```

---

## 6. 体积预算

| 组件 | 实体数 | 属性数 | JSON 体积 | gzip 压缩后 |
|---|---|---|---|---|
| 根类型 | 7 | - | ~2KB | ~0.8KB |
| 核心实体类 | 20 | - | ~5KB | ~2KB |
| 核心属性 | - | 30 | ~8KB | ~3KB |
| 地理锚点 | 10 | - | ~3KB | ~1.2KB |
| 时间锚点 | 5 | - | ~1.5KB | ~0.6KB |
| 层次关系 | - | 15 条语句 | ~2KB | ~0.8KB |
| **合计** | **42** | **45** | **~21.5KB** | **~8.4KB** |

---

## 7. 使用场景示例

### 场景 1: 用户说"我在杭州"

```
输入: "我在杭州"
提取:
  - Entity: "杭州" (Q49923) → kind: place
  - Statement: user LOCATED_IN 杭州
  - 时间: now
```

### 场景 2: 用户说"我读了一篇关于 AI 的论文"

```
输入: "我读了一篇关于 AI 的论文"
提取:
  - Entity: "AI 论文" → kind: document (subclass of scholarly article)
  - Statement: user READS AI 论文
  - Statement: AI 论文 ABOUT AI
  - Statement: AI 论文 INSTANCE_OF scholarly article
```

### 场景 3: 用户说"明天下午 3 点开会"

```
输入: "明天下午 3 点开会"
提取:
  - Entity: "会议" → kind: calendar_object
  - Statement: meeting SCHEDULED_AT tomorrow 15:00
  - Statement: meeting ATTENDS user
```

### 场景 4: 跨实体推理

```
已知:
  - 杭州 INSTANCE_OF city
  - city SUBCLASS_OF location (Wikidata Q515 → Q17334923)
  - 杭州 LOCATED_IN 中国

推理:
  - 東州 is_a location (传递性)
  - 杭州 LOCATED_IN 中国 (直接)
```

---

## 8. 扩展建议

### 8.1 动态同步机制

```swift
/// 从 Wikidata API 动态获取实体标签
func fetchWikidataLabels(qids: [String]) async throws -> [String: String] {
    let url = URL(string: "https://www.wikidata.org/w/api.php?action=wbgetentities&ids=\(qids.joined(separator: "|"))&props=labels&languages=zh|en&format=json")!
    let (data, _) = try await URLSession.shared.data(from: url)
    // 解析返回的 JSON
    return try parseLabels(from: data)
}
```

### 8.2 置信度衰减

```swift
/// Wikidata 实体的置信度随时间衰减
func decayConfidence(entity: GraphEntity, now: Date) -> Double {
    let age = now.timeIntervalSince(entity.updatedAt)
    let days = age / 86400
    return max(0.5, 1.0 - days * 0.01)  // 每天衰减 1%，最低 0.5
}
```

### 8.3 冲突检测

```swift
/// 检测 Wikidata 实体与本地实体的冲突
func detectConflict(wikidataEntity: WikidataSeedEntity, localEntity: GraphEntity) -> Bool {
    // 1. 检查 canonicalClassID 是否冲突
    if let wdClass = wikidataEntity.canonicalClassID,
       let localClass = localEntity.canonicalClassID,
       wdClass != localClass {
        return true
    }
    
    // 2. 检查 entityKind 是否冲突
    if wikidataEntity.graphEntityKind != localEntity.entityKind {
        return true
    }
    
    return false
}
```

---

## 9. 下一步

1. [ ] 创建 `Sources/ConnorGraphStore/Seeds/` 目录
2. [ ] 生成 5 个 JSON 种子文件
3. [ ] 在 `GraphKernelDomain.swift` 中添加 Wikidata 映射表
4. [ ] 在 `AppGraphBootstrapper.swift` 中添加加载逻辑
5. [ ] 编写单元测试验证种子数据加载
6. [ ] 添加 Wikidata API 动态标签获取
