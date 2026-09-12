# 控制电脑（Computer Use）工具族

康纳同学可以像人一样观察屏幕并操作键鼠。工具分三层：**感知**（截图、无障碍树）、**语义操作**（AX/UIA 元素动作）、**原始注入**（鼠标/键盘）。两端工具同名同参，仅前缀不同（`macos_*` / `windows_*`）。

## 工具一览

| 工具 | 权限能力 | 说明 |
|---|---|---|
| `*_screenshot` | `readSystemScreen` | 截取屏幕（可指定区域），返回路径 + 图片尺寸 + 屏幕偏移；Mac 端同时以图片部件回传模型 |
| `*_ax_tree` | `readSystemAccessibility` | 读取前台/指定应用的无障碍树，输出 类型/标题/值/坐标/ID 的缩进文本树 |
| `*_ax_action` | `controlSystemInput` | 对树中元素执行语义动作（invoke/press/setValue/focus 等），免坐标 |
| `*_input_click` / `*_input_type` / `*_input_key` / `*_input_scroll` / `*_input_drag` | `controlSystemInput` | 模拟鼠标点击/键入/组合键/滚轮/拖拽 |

**推荐顺序**：`screenshot`（看）→ `ax_tree`（精确定位）→ `ax_action`（语义操作，最可靠）→ `input_*`（兜底坐标点击）。坐标统一为屏幕绝对坐标；截图结果中给出的换算规则是「屏幕坐标 = 图内像素 + 偏移」。

## 授权模型（会话级一次性授权）

- 未授权时，`controlSystemInput` 类工具走既有审批卡片；**用户批准一次即视为本会话授权**，此后同会话的观察与操作自动执行。
- Windows：托盘右键菜单「允许康纳控制电脑」可随时授予/撤销（`ComputerControlGate`）。
- Mac：授权存续在 `ComputerControlConsent`（应用重启清空）；只读权限模式下操作类一律拒绝。

## 平台实现与权限要求

### macOS
- 实现：`Sources/ConnorGraphAgent/SystemControlAgentTools.swift`（AXUIElement + CGEvent + CoreGraphics）。
- 需要两个 TCC 权限（首次使用会拉起系统引导，错误文案会指路）：
  - **辅助功能**：系统设置 → 隐私与安全性 → 辅助功能（AX 读取与 CGEvent 注入共用）；
  - **屏幕录制**：系统设置 → 隐私与安全性 → 屏幕录制（`*_screenshot`）。
- 键盘虚拟键码按 ANSI 键盘物理布局查表；文本键入走 Unicode 键盘事件，支持中文。

### Windows
- Core 层：`Connor.Core/Agent/WindowsComputerUseTools.cs`（工具定义与授权门）+ `WindowsUiAPowerShell.cs`（UIA 默认通道：临时 .ps1 + 系统自带 UIAutomationClient，零依赖）。
- 宿主层：`Connor.Windows/Services/ComputerControlNative.cs`（SendInput 键鼠注入 + GDI BitBlt 截图，DPI 与坐标空间一致；`AppState` 注入）。
- UIA 通道约 1–2 秒/次；如需更低延迟，可后续在宿主注入原生 UIA 实现覆盖（delegate 已预留）。

## 已知边界

- **自身界面树不可读写**：`macos_ax_tree` / `macos_ax_action` 对康纳同学自己进程的 AX 读写会在后台线程进入 MainActor 隔离的视图 getter，触发 Swift 执行器断言直接崩溃（2026-09-12 已修复为显式拒绝并引导改用 `macos_screenshot`）。观察本应用窗口一律用截图。
- **合成事件节奏约束（重要）**：mouseDown/mouseUp 之间必须留间隔（macOS 菜单在 down 时进入跟踪模式，瞬时事件对会被吞掉，系统会卡在"菜单跟踪/拖拽"状态，表现为所有菜单打不开、滚动被劫持）；滚轮事件必须带 begin/continue/end 相位，否则 SwiftUI/AppKit 滚动视图会忽略。两端实现均已按此约束发出（见 `SystemControlSupport` / `ComputerControlNative` 顶部注释）。若历史上出现过卡死，物理点击一次鼠标即可解除残留的按住状态。
- AX 查询单条消息超时为 2 秒（`AXUIElementSetMessagingTimeout`），AX 支持差的应用（如微信）会快速跳过不响应的节点，不会拖垮整棵树遍历。
- 多显示器/混合 DPI 下，Windows 的 PowerShell 截图兜底通道与虚拟屏坐标可能存在缩放偏差（原生通道一致）；Mac 截图目前取主显示器。
- UAC/管理员权限窗口、安全桌面（锁屏/登录）无法被注入。
- Windows 键入 `KEYEVENTF_UNICODE` 与 Mac `keyboardSetUnicodeString` 对少数接收方（如远程桌面、某些游戏）无效。
