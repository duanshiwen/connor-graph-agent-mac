# Connor Base · M3-K9 同步 golden fixtures（三端 SHA-256 对账）

本目录为**同步对象对账**类 golden fixture（独立于 `../golden/` 的工具执行类，避免污染 20 条计数断言）。

## 语义
给定同一 AppPackage（四件套 + 版本）与种子数据，三端（Mac/Android/后端）各自在真实内核上产出**字节一致**的确定性结果：

- `then.packageFingerprint`：包快照确定性 JSON 的 SHA-256（同包同指纹）
- `then.cardFingerprint`：编译 Card 规范化 JSON（去时间戳）的 SHA-256（同包同 Card）
- `then.guideFingerprint`：指南全文规范化 JSON 的 SHA-256（指南全文一致）
- `then.methodResult`：方法 DAG 在种子数据上的确定性执行结果（同方法同结果）

## 纪律
- 期望值**必须来自内核实际输出**（Mac 为参考实现，数字必出内核），禁止手写。
- canonical 为事实源；改 canonical 后必须跑 `scripts/sync-base-golden.sh`（copy）→ `--check` 零漂移三仓一致。
- 首次新增 fixture：先写骨架（then 占位），跑参考端 runner 拿实际值回填固化。
