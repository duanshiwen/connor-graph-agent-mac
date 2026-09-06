# Connor Base · Golden Fixtures（M0 首批，canonical 源）

本目录是 Connor Base 三端共享的行为规范事实源（D12 golden fixtures 机制）。

## 职责

- **canonical 源位于本目录**；Mac 仓拷贝在 `Tests/ConnorGraphBaseTests/Golden/`，Android 仓拷贝在 `core/database/src/test/resources/base-golden/`。
- 三仓 SHA-256 一致性由 `scripts/sync-base-golden.sh` 保证（CI 不绿不合入）。
- M1-K8 起由各端 golden 执行器读入并执行，逐条断言 `then`。

## Fixture 格式

单个 JSON 文件即一个 fixture：

```json
{
  "name": "唯一名",
  "given": {
    "schema": { "tables": [ ... ] },
    "methods": [ ... ],
    "input": { "tool": "base.app.create", "args": { ... } },
    "appContext": { "appID": "acct", "visibility": "private", "packageVersion": 1 }
  },
  "then": {
    "envelope": { "ok": true, "data": { ... }, "error": null },
    "errorCode": null
  }
}
```

- `given.input`：工具调用（tool + args），执行目标；方法相关 fixture 用 `given.methods` 提供 App 方法定义。
- `given.schema`：App 结构；`given.appContext`：执行上下文（appID/三态/包版本）。
- `then.envelope`：期望信封。**动态字段规则**：`traceId` 仅断言存在且为字符串；`site` 若在期望中出现则断言一致；`sync` 若出现则断言 `pending>=0` 且类型正确。`ok/data/error` 逐字段严格比较。
- `then.errorCode`：期望的顶层错误码（非 null 时与 `envelope.error.code` 一致）。

## M0 首批 20 条覆盖

| 区间 | 覆盖 | fixture |
|---|---|---|
| 01–05 | schema 校验正/负（app/table create） | 01 valid · 02 表名非法 · 03 字段类型非法 · 04 缺必需字段 · 05 字段重名 |
| 06–12 | filter 编译各操作符 + 非法操作符 | text eq/contains · number gte/between · date range · enum in · relation has · 非法 op |
| 13–18 | mutate 原子批/dryRun/幂等/越界/版本冲突 | insert · 原子批 · dryRun · 幂等 · TABLE_NOT_IN_SCOPE · CONFLICT |
| 19–20 | 方法 DAG 校验 | 只读方法含 mutate 拒 · 跨 App 调用深度超限拒 |

## 维护纪律

- 只增不改已发布 fixture（改 = 新增编号 + 在 README 记录废弃原因）。
- 期望值必须是内核确定输出，禁止把 Agent 心算值写进 `then`。
- 修改 canonical 后必须跑 `scripts/sync-base-golden.sh` 同步三仓并保持零漂移。
