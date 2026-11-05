# macOS 同步卡顿与中断恢复检查（2026-11-04）

## 基线与结论

- `main` 已从 `84cc6fae` 快进到远端 `f8475d03`；拉取前工作区干净。
- 本轮在 Windows 上检查 macOS 源码，没有连接到 Mac，也没有拿到 Mac 故障数据库或崩溃日志。因此不能宣称复现或修好了某台 Mac 的“强退后打不开”。
- 同步主体已有 actor、后台任务、取消传播和串行调度；本轮发现并修复下列具体风险。

## 修改

1. **会话写入原子性。** `SQLiteGraphKernelStore.upsertSession` 原先分开提交会话元数据、删除旧分页消息、插入新分页消息。中途失败或进程退出可能造成元数据与分页消息不一致。现在整个写入持有数据库锁，并使用 `BEGIN IMMEDIATE` / `COMMIT`，出错回滚。既有迁移会回填没有分页行的历史会话，但不能替代写入原子性。
2. **长文本排版。** 限行预览现在只解析有界前缀；超过 20,000 UTF-16 单位的内容展开后以约 4,000 单位的纯文本页显示，单个超长段落也受限。分页不拆开 UTF-16 代理对，支持中文和 emoji，原始消息及全文复制来源不变。超大等宽文件预览也走分页。预览边界按 UTF-16 计算，避免一个包含大量组合符的 grapheme 绕过长度限制。同步导入不再为这类消息预编译整份 Markdown。
3. **主线程数据库访问。** 同步前的好友绑定投影批次，以及同步后的全量人物实体读取，移到后台任务执行；界面状态快照与更新仍留在主线程。

## 验证状态

已完成：

- 8 个新增/修改 Swift 文件的 tree-sitter 语法检查，无语法错误。
- `git diff --check` 通过。
- Windows、Android、Linux、macOS 四份 `session-chunks-v1.json` SHA-256 一致。

已增加但**尚未执行**的原生回归测试：

- `AppLargeTextPageTests`：空内容、页码越界、多兆中文/emoji 无损重组、跨页代理对、超长组合字符。
- `AgentMarkdownPreviewStrategyTests`：超长展开及等宽内容分页，适中长度的中文仍可使用富文本。
- `ChatSessionAtomicWriteTests`：使用 SQLite 触发器注入消息插入失败，检查旧元数据和分页消息回滚；首次插入失败无残留；多兆消息关闭重开一致。

本机没有 Swift/Xcode。尝试下载官方 Swift 6 Docker 镜像以运行纯逻辑测试，下载停滞后取消，不能记为测试通过。新增 `Scripts/test-portable-text-preview.py` 可在具备 Swift 6 和 Python 3 的 Linux/macOS 环境运行实际文本策略及相应 Swift 测试，不构建 SwiftUI 应用，也不替代原生数据库测试。

## Mac 上仍需完成

```sh
python3 Scripts/test-portable-text-preview.py
swift test --filter AppLargeTextPageTests
swift test --filter AgentMarkdownPreviewStrategyTests
swift test --filter ChatSessionAtomicWriteTests
swift test --filter AccountSyncRecoveryTests
swift build -c release
```

随后使用独立测试账号和数据库，在 Mac 上进行 Windows/Android 往返同步、长消息折叠/展开/翻页、同步期间界面响应、下载/写入过程中强退后重开，以及重复同步不回传的验证。现有数据库写入回归使用触发器失败和重开，不等同于原生应用进程强退测试。

待进一步评估的风险：同步状态仍以较大的 UserDefaults 数据保存（包含待处理变更与分片）；本轮没有重做状态存储或对其进行崩溃持久性验证。HTML 笔记仍使用 WebKit 专用预览，未计入普通 Markdown/等宽文本分页覆盖范围。
