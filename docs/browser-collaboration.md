# 浏览器第二阶段：与康纳协作

## 已接通的流程

- 在浏览器内询问当前页或选区；复用当前会话和模型连接，答案留在浏览器内。
- 明确选择同会话的 2–8 个普通标签进行比较，带上每页的标题、网址和截断标记，要求按来源引用。资料总量有上限，可通过 `browser_read` 分页继续读取。
- 先选普通可编辑字段，再生成可修改草稿；用户点击“确认填入，不提交”后才修改网页。敏感字段交由用户处理。写入前检查原值，写入后检查字段是否被网页校验回退。
- “暂停 / 我来操作”和 Agent 的 `browser_handoff` 会暂停当前会话的自动操作。继续时清除旧节点引用；新的暂停不能被较早的继续动作撤销。
- `browser_verify` 根据明确的文本、网址、标题、字段值或勾选状态核对结果。点击后的页面变化只算观察证据，不代表业务已经完成。

页内问答、比较和表单草稿使用单轮只读工具集合；浏览器提交、文件操作仍走原有权限流程。网页内容作为不可信资料传入，私密标签不参加自动问答和比较。暂停无法撤销已发出的网页请求，界面和工具结果会提醒用户核对。

## 验证范围

真实网页测试使用本地 HTTP fixture；Agent 回复使用可控回调/事件，验证页面、会话、资料来源、流式回复和草稿填入链路。未发起真实付费模型请求或外部业务提交。

macOS：`swift test --filter 'BrowserAssistedWebToolTests|BrowserAutomationQualityAuditTests|DefaultSearchEngineTests|BrowserFormAssistantTests'`，并执行 `swift build`。

新增 WKWebView fixture 测试覆盖字段验证、用户编辑冲突、框架回退、旧节点、暂停/继续与 handoff；工具测试覆盖只读集合及动态工具刷新，Foundation 测试覆盖比较来源和截断。

当前开发主机是 Windows，没有 Swift/macOS SDK。仅执行了 Swift 语法解析检查；未执行上述原生编译与测试，必须在 Mac 上补跑。`python Scripts/test-browser-daily-portable.py` 可在有 Swift 6 的主机单独验证 Foundation 浏览器策略及比较提示构造，不能代替原生测试。
