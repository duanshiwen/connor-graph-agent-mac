# Connor Graph Agent Mac 内存泄露风险检查报告

检查时间：2026-06-25 23:57 GMT+8  
检查对象：`/Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac`  
检查范围：Swift / SwiftUI macOS 应用、SwiftPM targets、WebKit bridge、Timer / Task / Notification / cache / SQLite/FFI 资源生命周期。

## 1. 结论摘要

本次没有发现“确定会持续无限泄露”的严重问题，但发现并修复了 1 个明确的 WebKit 生命周期兜底缺口；同时识别出 3 类需要持续治理的中低风险点。

### 风险评级

- **高风险：未发现。**
- **中风险：1 项已修复。** 后台 `WKWebView` 在 SwiftUI 移除 `NSViewRepresentable` 时缺少 `dismantleNSView` 兜底清理。
- **中低风险：2 项建议后续治理。**
  - `AppViewModel` 是长生命周期根对象，持有 `Timer`、`Task`、continuation、active backend、location coordinator 等资源；当前依赖应用级生命周期，建议增加显式 `shutdown()` 而不是直接在 Swift 6 `deinit` 中处理 MainActor/非 Sendable 对象。
  - 浏览器 selection thread / workspace snapshot / event timeline cache 依赖业务入口清理，当前有局部限制和清理，但仍建议增加可观测的容量策略。
- **低风险：多项已有良好实践。** WebView live store 有预算驱逐、tab close 清理、脚本 message handler 移除；NotificationCenter 主要使用 SwiftUI `.onReceive` 或被 feature flag 禁用；SQLite/FFI 对象有 `deinit` close/free。

## 2. 本次实际修改

### 已修复：后台 WKWebView 移除时断开 delegate 并停止加载

文件：`Sources/ConnorGraphAgentMac/BrowserBackgroundTaskRunnerView.swift`

新增：

```swift
static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
    if nsView.isLoading { nsView.stopLoading() }
    nsView.navigationDelegate = nil
    nsView.removeFromSuperview()
}
```

### 为什么这是必要的

`BrowserBackgroundTaskWebView` 是 `NSViewRepresentable`，用于后台浏览器辅助任务。`makeNSView` 中创建 `WKWebView` 并设置：

```swift
webView.navigationDelegate = context.coordinator
```

虽然多数任务完成后会从 `runningTasks` 中消失，SwiftUI 会移除对应 view，但没有 `dismantleNSView` 时，清理动作依赖对象释放顺序，缺少显式断开 delegate 和停止加载的兜底。对于 `WKWebView` 这种多进程、异步导航、delegate 回调密集的对象，显式 dismantle 是更安全的生命周期边界。

## 3. 审计方法

### 3.1 项目规模和技术栈

- Swift files：约 696 个。
- Swift tools：6.0。
- 平台：macOS 14+。
- 关键框架：SwiftUI、AppKit、WebKit、SQLite、Security、EventKit、Contacts、AVFoundation、Speech、CoreLocation。

### 3.2 扫描维度

重点检索和人工审计了以下高风险模式：

- `Timer.scheduledTimer` / repeating timer。
- `NotificationCenter.addObserver` / `.onReceive`。
- `Task {}` / `Task.detached` / 长生命周期 task handle。
- `WKWebView`、`WKScriptMessageHandler`、`navigationDelegate`、`uiDelegate`。
- `NSViewRepresentable` / coordinator 生命周期。
- `AnyCancellable` / Combine sink。
- 缓存、字典、数组、timeline、history、transcript 等集合增长。
- SQLite / FFI / native resource 的 close/free。

## 4. 详细发现

### 4.1 WebKit 生命周期

#### 4.1.1 `BrowserLiveWebViewStore`：整体设计较安全

文件：`Sources/ConnorGraphAgentMac/BrowserLiveWebViewStore.swift`

已有安全点：

- `remove(_:)` 会调用 `cleanup(_:)`。
- `evict(_:)` 会调用 `cleanup(_:)`。
- `cleanup(_:)` 会执行：
  - `pauseBrowserMediaPlayback()`
  - `stopLoading()`
  - `navigationDelegate = nil`
  - `uiDelegate = nil`
  - `removeScriptMessageHandler(forName:)`
  - `removeFromSuperview()`
- 有 `BrowserLiveWebViewBudgetPolicy`，会根据隐藏 WebView 数量和内存压力驱逐隐藏 WebView。

结论：主浏览器 WebView store 当前没有明显 delegate/message handler retain cycle 泄露。

#### 4.1.2 `BrowserWorkspaceView`：tab close 与 disappear 有清理

文件：`Sources/ConnorGraphAgentMac/BrowserWorkspaceView.swift`

已有安全点：

- `closeTab(_:)` 调用 `prepareWebViewForTabClose` 和 `browserLiveWebViewStore.remove(...)`。
- `onDisappear` 调用：
  - `captureRestorationSnapshotsForLiveTabs()`
  - `pauseAllBrowserMedia()`
  - `markAllBrowserTabsHidden()`
  - 延迟 `enforceBudget()`
  - `removeBrowserKeyMonitor()`
- `NSEvent.addLocalMonitorForEvents` 有对应 `NSEvent.removeMonitor`。

结论：主浏览器交互层有较完整生命周期处理。

#### 4.1.3 `BrowserBackgroundTaskRunnerView`：已修复

问题：后台 WebView 缺少 `dismantleNSView`。  
修复：已新增 `dismantleNSView`，停止加载并断开 `navigationDelegate`。

风险等级：修复前中风险；修复后低风险。

### 4.2 Timer / Task 生命周期

#### 4.2.1 `AppViewModel.startTaskSchedulerTimer()`

文件：`Sources/ConnorGraphAgentMac/AppViewModel.swift`

现状：

- 使用 `guard taskSchedulerTimer == nil` 防止重复 timer。
- timer closure 使用 `[weak self]`，避免 timer 强引用 `AppViewModel`。
- 有 `stopTaskSchedulerTimer()`，但未看到应用退出/scene disappear 中调用。

风险判断：

- 因 `AppViewModel` 是 `@StateObject` 应用级根对象，生命周期通常等同 App 主窗口，不太会产生用户可见的重复泄露。
- 但如果未来支持多窗口、view model 热重载、测试中频繁创建销毁，建议引入显式 `shutdown()`，由 App lifecycle 调用，统一停止 timer、取消 autosave/global search task、取消 pending continuation。

为什么没有直接在 `deinit` 修：

- Swift 6 中 `@MainActor` 类的 `deinit` 是非隔离上下文，访问 `Timer?`、`CLLocationManager` 等非 Sendable 对象会触发编译错误。
- 因此更正确的方案不是硬塞 `deinit`，而是新增 `@MainActor func shutdown()` 并在应用生命周期中显式调用。

建议后续补充：

```swift
@MainActor
func shutdown() {
    stopTaskSchedulerTimer()
    runtimeSettingsAutosaveTask?.cancel()
    globalSearchPreviewTask?.cancel()
    // resume/cancel pending continuations with explicit failure result
    // release active backend references
    // nil out location coordinator after stopping geocoder/location updates if needed
}
```

### 4.3 NotificationCenter / AppKit monitor

#### 4.3.1 NotificationCenter

发现：

- `AppShellViews.swift` 使用 `.onReceive(NotificationCenter.default.publisher(...))`，SwiftUI 管理订阅生命周期。
- `ConnorGraphAgentMacApp.swift` 中 `NotificationCenter.default.addObserver(...)` 被 `isRuntimeMenuLocalizationEnabled = false` feature flag 包住，当前不会执行。

结论：当前没有明显 NotificationCenter observer 泄露。

#### 4.3.2 NSEvent local monitor

`BrowserWorkspaceView` 的 `browserKeyMonitor` 在 `onDisappear` 中移除。结论：风险低。

### 4.4 Combine

扫描结果：没有发现 `AnyCancellable` / `.sink(...)` 风险点。结论：低风险。

### 4.5 Continuation / browser-assisted web_fetch

文件：`Sources/ConnorGraphAgentMac/AppViewModel.swift`

已有安全点：

- web_fetch 完成后清理：`browserAssistedWebFetchContinuationsByTaskID[taskID] = nil`。
- timeout 后清理 continuation 和 request。
- user intervention / failed 都会 resume 并清理。

潜在建议：

- 如果未来增加显式 `shutdown()`，应统一 resume 所有 pending continuation，避免任务等待。
- 可增加测试覆盖：模拟 shutdown 时 pending web_fetch 返回 failed/cancelled。

风险：低到中低。

### 4.6 缓存 / 集合增长

#### 已有保护

- Browser history store 有 `Max record count is enforced` 测试。
- Browser live WebView 有隐藏 WebView budget policy 测试。
- Attachment / PDF / mail parser 有 oversize budget 测试。
- Native source search 有分页、limit、cursor 测试。

#### 建议关注

`AppViewModel` 中以下集合是长生命周期内存增长关注点：

- `agentEventTimelinesBySessionID`
- `agentEventTimelinesByProcessKey`
- `chatInputDraftsBySessionID`
- `pendingAttachmentRefsBySessionID`
- `browserWorkspaceSnapshotsBySessionID`
- `lastSessionNotificationAt`

当前有一些局部清理，例如切换 session 时 `agentEventTimelinesByProcessKey.removeAll(keepingCapacity: true)`。但建议后续为长生命周期缓存增加统一容量策略，例如：

- 最大 session cache 数。
- LRU eviction。
- app background / memory pressure 时清理非当前 session 的 UI-only cache。
- debug build 中增加 cache count diagnostics。

风险：中低；更像长期运行内存增长治理，不是确定泄露。

### 4.7 SQLite / FFI / native resource

扫描到以下对象已有 `deinit`：

- `SQLiteGraphKernelStore`
- `SQLiteMemoryOSStore`
- `SQLiteNativeSourceSearchBackend`
- `MemoryOSSearchKernel`
- `MemoryOSSearchKernelFFI`
- seed builder SQLite db

结论：底层 native resource 释放路径存在，未发现明显遗漏。

## 5. 验证证据

### 5.1 编译

命令：

```bash
swift build
```

结果：通过。

### 5.2 定向测试

命令：

```bash
swift test --filter 'Browser|AppViewModel'
```

结果：91 个测试通过，0 失败。

### 5.3 全量测试

命令：

```bash
swift test
```

结果：1277 个测试中 1 个失败。失败项：

```text
bashToolTimesOutLongRunningCommand()
LocalShellCommandPolicyTests.swift:44:11
Expectation failed: an error was expected but none was thrown
```

该失败在本次修改前的初始全量测试中也存在，且与本次 WebView 生命周期修复无关。建议单独排查 shell timeout 测试在当前 macOS / SwiftPM 并发环境下的稳定性。

## 6. 建议修改清单

### 6.1 已完成

- [x] 为 `BrowserBackgroundTaskWebView` 增加 `dismantleNSView`，停止加载、断开 `navigationDelegate`、移除 view。

### 6.2 建议下一步做

1. **为 `AppViewModel` 增加显式 `shutdown()` 生命周期方法。**
   - 不建议在 Swift 6 `deinit` 中直接访问 MainActor/非 Sendable 资源。
   - 应由 App/scene lifecycle 在应用退出或根对象销毁前主动调用。

2. **为 UI-only cache 增加容量诊断。**
   - 输出 `agentEventTimelinesBySessionID.count`、`browserWorkspaceSnapshotsBySessionID.count`、draft cache count 等。
   - 后续根据真实使用情况决定 LRU 策略。

3. **增加 Instruments 验证脚本 / SOP。**
   - 场景 A：连续打开/关闭 50 个 browser tabs。
   - 场景 B：连续执行 100 次 browser-assisted web_fetch。
   - 场景 C：切换 100 个 sessions 并恢复 transcript。
   - 观察 Allocations / Leaks / VM Tracker 中 `WKWebView`、`WebContent` process、`AppViewModel`、coordinator 是否回落。

4. **单独修复或稳定化 `bashToolTimesOutLongRunningCommand()`。**
   - 当前测试期望 timeout 抛错但未抛错，可能是本机 shell timeout 行为/时序问题。

## 7. 总体判断

项目整体在内存治理上已有较多成熟边界：WebView store 有预算驱逐和清理，Notification/monitor 大多有生命周期处理，native resource 有 deinit，输入/附件/邮件解析有大小预算。当前最值得做的是把这些局部治理上升为“应用生命周期 shutdown + cache diagnostics”两件事。这样更符合 Connor 作为长期运行本地 Agent OS 的形态：不是只防止单个对象泄露，而是给长期运行状态建立可观测、可回收、可验证的内存治理闭环。
