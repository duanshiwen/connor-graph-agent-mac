import Foundation
import CoreGraphics
import ApplicationServices
import AppKit
import ConnorGraphCore

/// 控制电脑（Computer Use）会话级授权存续：用户在权限卡片上批准过一次
/// controlSystemInput（或处于 trustedWrite/allowAll）后，AgentPolicyEngine 对同会话
/// 后续调用直接放行。应用重启即清空；Windows 端等价物是 Connor.Core 的 ComputerControlGate。
public actor ComputerControlConsent {
    public static let shared = ComputerControlConsent()

    private var grantedSessions: Set<String> = []

    public func grant(sessionID: String) { grantedSessions.insert(sessionID) }
    public func revokeAll() { grantedSessions.removeAll() }
    public func isGranted(sessionID: String) -> Bool { grantedSessions.contains(sessionID) }
}

/// AgentToolArguments 缺少 double 取值器（number 参数可能来自 .double 或 .int）。
extension AgentToolArguments {
    func double(_ key: String) -> Double? {
        switch values[key] {
        case .double(let value): return value
        case .int(let value): return Double(value)
        default: return nil
        }
    }
}

/// macOS 系统控制工具族的公共底座：TCC 权限预检、屏幕截图（CoreGraphics）、
/// AXUIElement 无障碍树读取与语义操作、CGEvent 键鼠注入。
enum SystemControlSupport {
    // ---- TCC 权限预检 ----

    /// 辅助功能权限（AX 读取与 CGEvent 注入都需要）。prompt=true 会拉起系统授权引导。
    static func ensureAccessibilityPermission(prompt: Bool) throws {
        // kAXTrustedCheckOptionPrompt 全局变量在 Swift 6 严格并发下不可直接引用，用其字面值
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }
        throw AgentToolError.permissionDenied(
            "康纳同学还没有辅助功能权限。请到 系统设置 → 隐私与安全性 → 辅助功能 中勾选康纳同学，然后重试。")
    }

    /// 屏幕录制权限。首次调用会拉起系统授权弹窗；未授权时截屏返回空白/失败。
    static func ensureScreenCapturePermission() throws {
        if CGPreflightScreenCaptureAccess() { return }
        _ = CGRequestScreenCaptureAccess()
        throw AgentToolError.permissionDenied(
            "康纳同学还没有屏幕录制权限。请到 系统设置 → 隐私与安全性 → 屏幕录制 中勾选康纳同学，然后重试。")
    }

    // ---- 截图 ----

    struct ScreenshotOutput {
        let pngData: Data
        /// 编码后图片尺寸（长边超过 maxDimension 时已降采样）
        let width: Int
        let height: Int
        let offsetX: Int
        let offsetY: Int
        /// 屏幕点 / 图内像素 的换算系数：屏幕坐标 = 图内坐标 × scale + 偏移
        let scale: Double
    }

    /// 降采样系数（纯函数）：长边超过 maxDimension 时缩放。Anthropic 官方建议喂给模型的
    /// 截图宽度控制在 1024-1366（内部极限 1568），更大的图会被模型端二次缩放，慢且损精度。
    static func downscaleFactor(width: Int, height: Int, maxDimension: Int) -> Double {
        let longest = max(width, height)
        guard maxDimension > 0, longest > maxDimension, longest > 0 else { return 1 }
        return Double(maxDimension) / Double(longest)
    }

    /// 截取主显示器（可指定区域，坐标为主显示器全局坐标，原点为主显示器左上角），
    /// 长边超过 maxDimension 时降采样。
    static func captureMainDisplay(region: CGRect?, maxDimension: Int = 1568) throws -> ScreenshotOutput {
        let displayID = CGMainDisplayID()
        let bounds = CGDisplayBounds(displayID)
        let captureRect: CGRect
        let offsetX: Int
        let offsetY: Int
        if let region, region.width > 0, region.height > 0 {
            captureRect = region
            offsetX = Int(region.minX)
            offsetY = Int(region.minY)
        } else {
            captureRect = bounds
            offsetX = Int(bounds.minX)
            offsetY = Int(bounds.minY)
        }
        guard var image = CGDisplayCreateImage(displayID, rect: captureRect) else {
            throw AgentToolError.invalidArguments("屏幕截图失败：可能缺少屏幕录制权限或区域超出屏幕。")
        }
        let scale = downscaleFactor(
            width: Int(captureRect.width),
            height: Int(captureRect.height),
            maxDimension: maxDimension)
        if scale < 1 {
            let scaledWidth = max(1, Int((Double(captureRect.width) * scale).rounded()))
            let scaledHeight = max(1, Int((Double(captureRect.height) * scale).rounded()))
            if let context = CGContext(
                data: nil, width: scaledWidth, height: scaledHeight,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                context.interpolationQuality = .medium
                context.draw(image, in: CGRect(x: 0, y: 0, width: scaledWidth, height: scaledHeight))
                if let scaled = context.makeImage() { image = scaled }
            }
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw AgentToolError.invalidArguments("PNG 编码失败。")
        }
        return ScreenshotOutput(
            pngData: png,
            width: image.width,
            height: image.height,
            offsetX: offsetX,
            offsetY: offsetY,
            scale: Double(captureRect.width) / Double(max(1, image.width)))
    }

    static func savePNG(_ output: ScreenshotOutput) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("connor-screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("screenshot-\(formatter.string(from: Date())).png")
        try output.pngData.write(to: url)
        return url
    }

    // ---- AX 无障碍树 ----

    struct AXNodeText {
        var lines: [String] = []
        var count = 0
    }

    /// 对自身进程的 AX 属性读写会在调用线程（后台协程）同步进入本应用 MainActor 隔离的
    /// 视图 getter，Swift 6 执行器断言失败会直接 EXC_BREAKPOINT 崩溃（2026-09-12 崩溃报告：
    /// SubmitAwareTextView.string getter）。因此读写自身界面树一律拒绝，引导改用截图。
    static func ensureNotSelf(_ application: AXUIElement) throws {
        var pid: pid_t = 0
        AXUIElementGetPid(application, &pid)
        guard pid != 0, pid != ProcessInfo.processInfo.processIdentifier else {
            throw AgentToolError.invalidArguments(
                "目标应用是康纳同学自己，读取/操作自身界面树不受支持（会触发主线程隔离断言导致本应用崩溃）。" +
                "观察本应用窗口请改用 macos_screenshot；操作其他应用请通过 targetApp 指定目标。")
        }
        // 对 AX 响应慢的应用（如微信）限制单条消息超时，避免逐属性等待拖垮整棵树遍历
        AXUIElementSetMessagingTimeout(application, 2.0)
    }

    /// 目标应用：按 bundleID/名称匹配运行中的应用；都缺省时取系统聚焦的应用。
    static func targetApplication(bundleID: String?, name: String?) throws -> AXUIElement {
        let wantedBundleID = bundleID.flatMap { $0.isEmpty ? nil : $0 }
        let wantedName = name.flatMap { $0.isEmpty ? nil : $0 }
        if wantedBundleID != nil || wantedName != nil {
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { continue }
                if let wantedBundleID, app.bundleIdentifier == wantedBundleID {
                    return AXUIElementCreateApplication(app.processIdentifier)
                }
                if wantedBundleID == nil, let wantedName, let localizedName = app.localizedName,
                   localizedName.contains(wantedName) {
                    return AXUIElementCreateApplication(app.processIdentifier)
                }
            }
            throw AgentToolError.invalidArguments("未找到运行中的应用（bundleID/name：\(wantedBundleID ?? wantedName ?? "")）。")
        }
        let systemWide = AXUIElementCreateSystemWide()
        if let focused = value(of: systemWide, attribute: kAXFocusedApplicationAttribute),
           CFGetTypeID(focused) == AXUIElementGetTypeID() {
            return focused as! AXUIElement
        }
        if let active = NSWorkspace.shared.runningApplications.first(where: { $0.isActive }) {
            return AXUIElementCreateApplication(active.processIdentifier)
        }
        throw AgentToolError.invalidArguments("没有聚焦的应用，请指定 targetApp。")
    }

    static func applicationTitle(of application: AXUIElement) -> String {
        if let title = stringAttribute(of: application, attribute: kAXTitleAttribute), !title.isEmpty { return title }
        var pid: pid_t = 0
        AXUIElementGetPid(application, &pid)
        return NSRunningApplication(processIdentifier: pid)?.localizedName ?? "未知应用"
    }

    /// 每节点一次 IPC 批量读取的属性集：AXUIElementCopyMultipleAttributeValues 把
    /// 原先约 9 次 Mach 往返合并为 1 次（角色/标题/描述/值/标识/坐标/尺寸/可用/子节点）。
    private static let walkedAttributes: [String] = [
        kAXRoleAttribute as String,
        kAXTitleAttribute as String,
        kAXDescriptionAttribute as String,
        kAXValueAttribute as String,
        kAXIdentifierAttribute as String,
        kAXPositionAttribute as String,
        kAXSizeAttribute as String,
        kAXEnabledAttribute as String,
        kAXChildrenAttribute as String,
    ]

    /// interactiveOnly 模式输出的可交互角色；AXStaticText 作为标签上下文保留（截断）。
    static let interactiveRoles: Set<String> = [
        "AXButton", "AXTextField", "AXTextArea", "AXSecureTextField", "AXSearchField",
        "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton", "AXComboBox",
        "AXSlider", "AXMenuItem", "AXMenu", "AXLink", "AXTabGroup", "AXTab",
        "AXTable", "AXList", "AXOutline", "AXRow", "AXProgressIndicator", "AXPicker",
    ]

    /// 交互模式行长度上限（静态文本上下文截断，省 token）
    private static let interactiveLabelLimit = 60

    /// 深度优先遍历 AX 树，输出缩进文本（含类型/标题/值/坐标/子元素计数）；节点超限即停。
    /// interactiveOnly=true 时只输出可交互角色（静态文本作为标签上下文保留），大幅减少输出与模型推理成本。
    static func walkTree(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        interactiveOnly: Bool = false,
        output: inout AXNodeText
    ) {
        guard depth <= maxDepth, output.count < maxNodes else { return }
        var rawValues: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(
            element, walkedAttributes as CFArray, [], &rawValues) == .success,
            let values = rawValues as? [CFTypeRef?],
            values.count == walkedAttributes.count
        else { return }
        let role = stringValue(values[0]) ?? "Unknown"
        let title = stringValue(values[1]) ?? ""
        let description = stringValue(values[2]) ?? ""
        let nodeValue = stringValue(values[3]) ?? ""
        let identifier = stringValue(values[4]) ?? ""
        let frame = axFrame(position: values[5], size: values[6])
        let enabled = boolValue(values[7])

        if interactiveOnly,
           !interactiveRoles.contains(role), role != "AXStaticText" {
            // 容器角色不输出但继续下钻（交互控件藏在里面）
            recurseIntoChildren(values[8], depth: depth, maxDepth: maxDepth, maxNodes: maxNodes, interactiveOnly: interactiveOnly, output: &output)
            return
        }

        var line = String(repeating: "  ", count: depth) + "[\(role)]"
        var label = description.isEmpty ? title : description
        if interactiveOnly, role == "AXStaticText", label.count > interactiveLabelLimit {
            label = String(label.prefix(interactiveLabelLimit)) + "…"
        }
        if !label.isEmpty { line += " " + label.replacingOccurrences(of: "\n", with: " ") }
        if !nodeValue.isEmpty { line += " =\(nodeValue.replacingOccurrences(of: "\n", with: " "))" }
        if !identifier.isEmpty { line += " #\(identifier)" }
        if let frame {
            line += String(format: " (%.0f,%.0f %.0fx%.0f)", frame.minX, frame.minY, frame.width, frame.height)
        }
        if enabled == false { line += " [disabled]" }
        output.lines.append(line)
        output.count += 1

        recurseIntoChildren(values[8], depth: depth, maxDepth: maxDepth, maxNodes: maxNodes, interactiveOnly: interactiveOnly, output: &output)
    }

    /// 遍历批量读取结果中的子节点数组（对应 kAXChildrenAttribute 位）。
    private static func recurseIntoChildren(
        _ childrenRaw: CFTypeRef?,
        depth: Int, maxDepth: Int, maxNodes: Int,
        interactiveOnly: Bool, output: inout AXNodeText
    ) {
        guard output.count < maxNodes,
              let children = childrenRaw as? [CFTypeRef] else { return }
        for child in children.prefix(200) {
            guard output.count < maxNodes, CFGetTypeID(child) == AXUIElementGetTypeID() else { continue }
            walkTree(
                child as! AXUIElement, depth: depth + 1, maxDepth: maxDepth, maxNodes: maxNodes,
                interactiveOnly: interactiveOnly, output: &output)
        }
    }

    /// 在目标应用的 AX 树中按标题/描述查找第一个匹配元素（深度优先）。
    static func findElement(in element: AXUIElement, matching text: String, maxDepth: Int, maxNodes: Int) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(element, 0)]
        var visited = 0
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            guard depth <= maxDepth else { continue }
            visited += 1
            guard visited < maxNodes else { return nil }
            let title = stringAttribute(of: current, attribute: kAXTitleAttribute) ?? ""
            let description = stringAttribute(of: current, attribute: kAXDescriptionAttribute) ?? ""
            if title == text || description == text || title.contains(text) || description.contains(text) {
                return current
            }
            if let children = arrayAttribute(of: current, attribute: kAXChildrenAttribute) {
                for child in children.prefix(200) {
                    guard CFGetTypeID(child) == AXUIElementGetTypeID() else { continue }
                    queue.append((child as! AXUIElement, depth + 1))
                }
            }
        }
        return nil
    }

    /// 对元素执行语义动作，返回执行是否成功。
    static func perform(action: String, on element: AXUIElement, value: String?) -> Bool {
        switch action {
        case "setValue":
            guard let value else { return false }
            return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFTypeRef) == .success
        case "focus":
            return AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success
        default:
            // AX 动作常量在 Swift 里桥接为 String，需要显式转 CFString
            let axAction: CFString? = switch action {
            case "press": kAXPressAction as CFString
            case "confirm": kAXConfirmAction as CFString
            case "increment": kAXIncrementAction as CFString
            case "decrement": kAXDecrementAction as CFString
            case "raise": kAXRaiseAction as CFString
            case "showMenu": kAXShowMenuAction as CFString
            case "pick": kAXPickAction as CFString
            default: nil
            }
            guard let axAction else { return false }
            return AXUIElementPerformAction(element, axAction) == .success
        }
    }

    private static func value(of element: AXUIElement, attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func stringAttribute(of element: AXUIElement, attribute: String) -> String? {
        guard let raw = value(of: element, attribute: attribute) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        if let url = raw as? URL { return url.absoluteString }
        return nil
    }

    /// 批量读取（CopyMultipleAttributeValues 未设 StopOnError）中缺失属性以 kCFNull 占位
    private static func isMissing(_ raw: CFTypeRef?) -> Bool {
        guard let raw else { return true }
        return CFGetTypeID(raw) == CFNullGetTypeID()
    }

    private static func stringValue(_ raw: CFTypeRef?) -> String? {
        guard let raw, !isMissing(raw) else { return nil }
        if let string = raw as? String { return string }
        if let number = raw as? NSNumber { return number.stringValue }
        if let url = raw as? URL { return url.absoluteString }
        return nil
    }

    private static func boolValue(_ raw: CFTypeRef?) -> Bool? {
        guard let raw, !isMissing(raw) else { return nil }
        return raw as? Bool
    }

    private static func axFrame(position rawPosition: CFTypeRef?, size rawSize: CFTypeRef?) -> CGRect? {
        guard let rawPosition, let rawSize, !isMissing(rawPosition), !isMissing(rawSize),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              CFGetTypeID(rawSize) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point),
            AXValueGetValue(rawSize as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func arrayAttribute(of element: AXUIElement, attribute: String) -> [CFTypeRef]? {
        guard let raw = value(of: element, attribute: attribute), let array = raw as? [CFTypeRef] else { return nil }
        return array
    }

    // ---- CGEvent 键鼠注入 ----
    // 合成事件的节奏约束（违反会导致系统卡在菜单跟踪/拖拽模式，表现为所有菜单打不开、
    // 滚动被劫持）：
    // 1. mouseDown 与 mouseUp 之间必须留间隔（菜单在 down 时进入跟踪模式，瞬时事件对会被吞掉）；
    // 2. mouseMoved 不得携带 clickState（带点击态的移动会打断菜单跟踪）；
    // 3. 滚轮事件必须带 begin/continue/end 滚动相位，否则 SwiftUI/AppKit 滚动视图忽略事件，
    //    模型会因"没滚成功"反复重试形成事件风暴。

    static func click(x: Double, y: Double, button: CGMouseButton, doubleClick: Bool) {
        let position = CGPoint(x: x, y: y)
        func post(_ type: CGEventType, clickState: Int64? = nil) {
            guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: button) else { return }
            if let clickState { event.setIntegerValueField(.mouseEventClickState, value: clickState) }
            event.post(tap: .cghidEventTap)
        }
        let downType: CGEventType = button == .left ? .leftMouseDown : (button == .right ? .rightMouseDown : .otherMouseDown)
        let upType: CGEventType = button == .left ? .leftMouseUp : (button == .right ? .rightMouseUp : .otherMouseUp)
        // 一次完整的按下-抬起（间隔让接收方完成点击/菜单跟踪状态机）
        func pressPair(clickState: Int64) {
            post(downType, clickState: clickState)
            usleep(50_000)
            post(upType, clickState: clickState)
        }
        post(.mouseMoved)
        if doubleClick {
            pressPair(clickState: 1)
            usleep(120_000) // 第二击落在双击间隔（≤500ms）内
            pressPair(clickState: 2)
        } else {
            pressPair(clickState: 1)
        }
    }

    static func scroll(x: Double, y: Double, delta: Int, horizontal: Bool) {
        let position = CGPoint(x: x, y: y)
        if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: position, mouseButton: .left) {
            move.post(tap: .cghidEventTap)
        }
        // 拆成多个带相位的事件（begin → continue×n → end），行单位，正值向上/向右；
        // 一格滚轮约 10 行
        let totalLines = Double(delta) / 10.0
        let steps = 5
        let linesPerStep = totalLines / Double(steps)
        for step in 0..<steps {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil, units: .line,
                wheelCount: horizontal ? 2 : 1,
                wheel1: horizontal ? 0 : Int32(clamping: Int(linesPerStep.rounded())),
                wheel2: horizontal ? Int32(clamping: Int(linesPerStep.rounded())) : 0,
                wheel3: 0)
            else { return }
            let phase: Int64
            if step == 0 { phase = 1 }                     // kCGScrollWheelEventScrollPhaseBegin
            else if step == steps - 1 { phase = 4 }        // kCGScrollWheelEventScrollPhaseEnd
            else { phase = 2 }                             // kCGScrollWheelEventScrollPhaseContinue
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.post(tap: .cghidEventTap)
            usleep(15_000)
        }
    }

    static func drag(fromX: Double, fromY: Double, toX: Double, toY: Double) {
        let from = CGPoint(x: fromX, y: fromY)
        func post(_ type: CGEventType, at position: CGPoint) {
            if let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: position, mouseButton: .left) {
                event.post(tap: .cghidEventTap)
            }
        }
        post(.leftMouseDown, at: from)
        // 无论中途发生什么都必须抬起，否则系统卡在拖拽模式（按钮被视为一直按住）
        var released = false
        defer {
            if !released { post(.leftMouseUp, at: CGPoint(x: toX, y: toY)) }
        }
        usleep(60_000)
        let steps = 20
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            post(.leftMouseDragged, at: CGPoint(x: fromX + (toX - fromX) * t, y: fromY + (toY - fromY) * t))
            usleep(10_000)
        }
        post(.leftMouseUp, at: CGPoint(x: toX, y: toY))
        released = true
    }

    static func typeText(_ text: String) {
        // 常规字符走 Unicode 键盘事件（支持中文）；换行/制表符用虚拟键码更可靠
        for scalar in text.unicodeScalars {
            let keyDown: Bool
            let virtualKey: CGKeyCode
            switch scalar {
            case "\n", "\r": keyDown = true; virtualKey = 36 // kVK_Return
            case "\t": keyDown = true; virtualKey = 48       // kVK_Tab
            default: keyDown = false; virtualKey = 0
            }
            if keyDown {
                postKeyEvent(virtualKey: virtualKey, down: true)
                postKeyEvent(virtualKey: virtualKey, down: false)
                continue
            }
            var characters = [UniChar](String(scalar).utf16)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: &characters)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    /// 组合键（修饰键在前，如 ["command","c"]）。
    static func keyCombo(_ keys: [String]) throws {
        let codes = try keys.map { try virtualKeyCode(for: $0) }
        let modifiers = codes.filter(isModifier)
        let plain = codes.filter { !isModifier($0) }
        for modifier in modifiers { postKeyEvent(virtualKey: modifier, down: true) }
        for key in plain {
            postKeyEvent(virtualKey: key, down: true)
            postKeyEvent(virtualKey: key, down: false)
        }
        for modifier in modifiers.reversed() { postKeyEvent(virtualKey: modifier, down: false) }
    }

    private static func isModifier(_ code: CGKeyCode) -> Bool {
        [56, 60, 58, 62, 59, 61, 55, 54, 63].contains(code) // 左右 shift/option/control/command/fn
    }

    /// 键名 → macOS 虚拟键码（kVK_*；字母/数字按 ANSI 键盘物理布局，需查表）。
    private static let letterKeyCodes: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "i": 34, "o": 31, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "u": 32
    ]

    private static let digitKeyCodes: [Character: CGKeyCode] = [
        "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25, "0": 29
    ]

    private static let functionKeyCodes: [String: CGKeyCode] = [
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]

    static func virtualKeyCode(for key: String) throws -> CGKeyCode {
        let normalized = key.lowercased()
        switch normalized {
        case "command", "cmd", "win": return 55
        case "shift": return 56
        case "option", "alt": return 58
        case "control", "ctrl": return 59
        case "return", "enter": return 36
        case "tab": return 48
        case "esc", "escape": return 53
        case "space": return 49
        case "backspace", "delete": return 51
        case "forwarddelete", "del": return 117
        case "home": return 115
        case "end": return 119
        case "pageup": return 116
        case "pagedown": return 121
        case "up": return 126
        case "down": return 125
        case "left": return 123
        case "right": return 124
        case "capslock": return 57
        default:
            if let code = functionKeyCodes[normalized] { return code }
            if normalized.count == 1 {
                let scalar = normalized.first!
                if let code = letterKeyCodes[scalar] { return code }
                if let code = digitKeyCodes[scalar] { return code }
            }
            throw AgentToolError.invalidArguments("无法识别的键名：\(key)")
        }
    }

    private static func postKeyEvent(virtualKey: CGKeyCode, down: Bool) {
        if let event = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: down) {
            event.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - 工具定义

/// macos_screenshot：截取屏幕（默认主显示器全屏，可指定区域），返回路径 + 图片部件 + 坐标换算说明。
public struct MacosScreenshotTool: AgentTool {
    public init() {}

    public let name = "macos_screenshot"
    public let description = "Capture the screen (main display by default, or an explicit region) to a PNG, downscaled to at most 1568px on the long edge. Returns the file path, image size, the downscale factor, and the on-screen origin offset. Screen coordinate = image coordinate × scale + offset. For a combined screenshot plus interactive-element list in one call, prefer macos_observe."
    public let permission: AgentPermissionCapability = .readSystemScreen
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "x": .number(description: "Region origin X in screen coordinates. Omit x/width to capture the whole main display."),
        "y": .number(description: "Region origin Y in screen coordinates."),
        "width": .number(description: "Region width in points."),
        "height": .number(description: "Region height in points.")
    ], required: [])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureScreenCapturePermission()
        let region: CGRect?
        if arguments.double("width") != nil, arguments.double("height") != nil {
            region = CGRect(
                x: arguments.double("x") ?? 0,
                y: arguments.double("y") ?? 0,
                width: arguments.double("width")!,
                height: arguments.double("height")!)
        } else {
            region = nil
        }
        let output = try SystemControlSupport.captureMainDisplay(region: region)
        let url = try SystemControlSupport.savePNG(output)
        let dataURL = "data:image/png;base64,\(output.pngData.base64EncodedString())"
        let scaleNote = output.scale < 1
            ? String(format: "图片已降采样，scale=%.3f（屏幕坐标 = 图内坐标 × scale + 偏移）", output.scale)
            : "scale=1（屏幕坐标 = 图内坐标 + 偏移）"
        let summary = "截图已保存：\(url.path)（\(output.width)x\(output.height)，左上角屏幕偏移 \(output.offsetX),\(output.offsetY)）。\(scaleNote)。"
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: summary,
            modelContentParts: [.imageDataURL(dataURL, mimeType: "image/png")])
    }
}

/// macos_ax_tree：读取聚焦应用（或指定应用）的无障碍树，返回控件的结构化文本树。
public struct MacosAXTreeTool: AgentTool {
    public init() {}

    public let name = "macos_ax_tree"
    public let description = "Read the accessibility tree (AX) of the frontmost application, or a named application, as an indented text tree with role, label, value, screen coordinates, and identifier for each element. Use it to locate the exact control to act on via macos_ax_action, or to get precise coordinates for macos_input_click. Coordinates are screen points (macOS top-left origin). Interactive-only mode keeps buttons/fields/menus and label text, which is much faster to reason about; for a screenshot + interactive list in one call prefer macos_observe."
    public let permission: AgentPermissionCapability = .readSystemAccessibility
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "targetApp": .string(description: "Application bundleID or localized name substring. Defaults to the frontmost application."),
        "maxDepth": .integer(description: "Maximum tree depth, default 10, clamped to 1-30."),
        "maxNodes": .integer(description: "Maximum number of nodes returned, default 300, clamped to 1-2000."),
        "interactiveOnly": .boolean(description: "Keep only interactive controls (plus label text) when true. Default false for a full tree.")
    ], required: [])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        let app = try SystemControlSupport.targetApplication(
            bundleID: arguments.string("targetApp"),
            name: arguments.string("targetApp"))
        try SystemControlSupport.ensureNotSelf(app)
        var output = SystemControlSupport.AXNodeText()
        SystemControlSupport.walkTree(
            app,
            depth: 0,
            maxDepth: min(max(arguments.int("maxDepth") ?? 10, 1), 30),
            maxNodes: min(max(arguments.int("maxNodes") ?? 300, 1), 2000),
            interactiveOnly: arguments.bool("interactiveOnly") ?? false,
            output: &output)
        let title = SystemControlSupport.applicationTitle(of: app)
        let text = ("应用: \(title)\n" + output.lines.joined(separator: "\n"))
        return AgentToolResult(toolCallID: context.toolCallID, toolName: name, contentText: text)
    }
}

/// macos_ax_action：对 AX 树中的元素执行语义动作（免坐标）。
public struct MacosAXActionTool: AgentTool {
    public init() {}

    public let name = "macos_ax_action"
    public let description = "Perform a semantic accessibility action on a UI element without coordinates: press, confirm, increment, decrement, raise, showMenu, pick, setValue, or focus. Locate the element by its label (title/description) inside the frontmost or named application — read macos_ax_tree first. Prefer this over coordinate clicking whenever the element is visible in the AX tree."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "action": .stringEnumeration(
            values: ["press", "confirm", "increment", "decrement", "raise", "showMenu", "pick", "setValue", "focus"],
            description: "The semantic action to perform."),
        "label": .string(description: "Exact or substring match against the element's title/description (from macos_ax_tree)."),
        "value": .string(description: "For setValue: the text to write into the element."),
        "targetApp": .string(description: "Optional application bundleID or name substring; defaults to the frontmost application.")
    ], required: ["action", "label"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        let action = arguments.string("action") ?? ""
        let label = arguments.string("label") ?? ""
        let app = try SystemControlSupport.targetApplication(
            bundleID: arguments.string("targetApp"),
            name: arguments.string("targetApp"))
        try SystemControlSupport.ensureNotSelf(app)
        guard let element = SystemControlSupport.findElement(in: app, matching: label, maxDepth: 30, maxNodes: 3000) else {
            return AgentToolResult(
                toolCallID: context.toolCallID, toolName: name,
                contentText: "未找到标签匹配「\(label)」的元素。请先用 macos_ax_tree 确认元素的准确标题/描述。",
                error: nil)
        }
        guard SystemControlSupport.perform(action: action, on: element, value: arguments.string("value")) else {
            return AgentToolResult(
                toolCallID: context.toolCallID, toolName: name,
                contentText: "元素「\(label)」不支持 \(action)（或执行被拒绝）。可尝试 press/focus，或改用坐标点击。",
                error: nil)
        }
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)
        return AgentToolResult(
            toolCallID: context.toolCallID, toolName: name,
            contentText: "已对元素「\(label)」执行 \(action)。建议用 macos_screenshot 或 macos_ax_tree 确认结果。")
    }
}

/// macos_input_click：屏幕坐标点击。
public struct MacosInputClickTool: AgentTool {
    public init() {}

    public let name = "macos_input_click"
    public let description = "Simulate a mouse click at absolute screen coordinates (points, top-left origin). Convert from a macos_screenshot by adding the reported origin offset, or read coordinates from macos_ax_tree. Prefer macos_ax_action when the control is in the accessibility tree."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "x": .number(description: "Screen coordinate X in points."),
        "y": .number(description: "Screen coordinate Y in points."),
        "button": .stringEnumeration(values: ["left", "right"], description: "Mouse button, default left."),
        "doubleClick": .boolean(description: "Double click when true, default false.")
    ], required: ["x", "y"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        guard let x = arguments.double("x"), let y = arguments.double("y") else {
            throw AgentToolError.invalidArguments("缺少屏幕坐标 x/y（points，来自截图换算或无障碍树）。")
        }
        let button = arguments.string("button") == "right" ? CGMouseButton.right : CGMouseButton.left
        SystemControlSupport.click(x: x, y: y, button: button, doubleClick: arguments.bool("doubleClick") ?? false)
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)
        let verb = (arguments.bool("doubleClick") ?? false) ? "双击" : "单击"
        return AgentToolResult(
            toolCallID: context.toolCallID, toolName: name,
            contentText: "已在 (\(Int(x)), \(Int(y))) 执行\(verb)（\(arguments.string("button") ?? "left")）。")
    }
}

/// macos_input_type：向聚焦控件键入文本（支持中文）。
public struct MacosInputTypeTool: AgentTool {
    public init() {}

    public let name = "macos_input_type"
    public let description = "Type text into the currently focused control via Unicode keyboard events (supports Chinese). Click the input field first with macos_input_click, or focus it with macos_ax_action. Prefer macos_ax_action setValue when the control supports values."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "text": .string(description: "Text to type, appended to the focused control.")
    ], required: ["text"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        guard let text = arguments.string("text"), !text.isEmpty else {
            throw AgentToolError.invalidArguments("缺少 text 参数。")
        }
        SystemControlSupport.typeText(text)
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)
        return AgentToolResult(
            toolCallID: context.toolCallID, toolName: name,
            contentText: "已键入 \(text.count) 个字符到当前聚焦的控件。")
    }
}

/// macos_input_key：按键 / 组合键。
public struct MacosInputKeyTool: AgentTool {
    public init() {}

    public let name = "macos_input_key"
    public let description = "Press a key or key combo, modifiers first: enter / tab / escape / command+c / option+f4 / control+shift+t. Key names: command shift option control enter tab esc space backspace forwarddelete home end pageup pagedown up down left right letters digits f1-f12."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "keys": .string(description: "Key or combo, for example command+c.")
    ], required: ["keys"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        guard let keys = arguments.string("keys"), !keys.isEmpty else {
            throw AgentToolError.invalidArguments("缺少 keys 参数（如 command+c）。")
        }
        let parts = keys.split(whereSeparator: { $0 == "+" || $0 == "," }).map(String.init)
        guard !parts.isEmpty else { throw AgentToolError.invalidArguments("keys 不能为空。") }
        try SystemControlSupport.keyCombo(parts)
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)
        return AgentToolResult(
            toolCallID: context.toolCallID, toolName: name,
            contentText: "已发送按键：\(parts.joined(separator: "+"))。")
    }
}

/// macos_input_scroll：滚轮滚动。
public struct MacosInputScrollTool: AgentTool {
    public init() {}

    public let name = "macos_input_scroll"
    public let description = "Scroll the mouse wheel at screen coordinates (x, y): delta positive scrolls up, negative scrolls down (one notch is about 120). horizontal=true scrolls sideways."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "x": .number(description: "Wheel position X in screen points."),
        "y": .number(description: "Wheel position Y in screen points."),
        "delta": .integer(description: "Scroll amount: positive up, negative down."),
        "horizontal": .boolean(description: "Horizontal scrolling when true, default false.")
    ], required: ["x", "y", "delta"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        guard let x = arguments.double("x"), let y = arguments.double("y"), let delta = arguments.int("delta"), delta != 0 else {
            throw AgentToolError.invalidArguments("需要 x/y 坐标与非零 delta（正值向上，负值向下）。")
        }
        SystemControlSupport.scroll(x: x, y: y, delta: delta, horizontal: arguments.bool("horizontal") ?? false)
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)
        return AgentToolResult(
            toolCallID: context.toolCallID, toolName: name,
            contentText: "已在 (\(Int(x)), \(Int(y))) 滚动 \(delta)。")
    }
}

/// macos_input_drag：按住左键拖拽。
public struct MacosInputDragTool: AgentTool {
    public init() {}

    public let name = "macos_input_drag"
    public let description = "Hold the left mouse button and drag from (fromX, fromY) to (toX, toY) in stepped moves (sliders, files, selections)."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "fromX": .number(description: "Start X in screen points."),
        "fromY": .number(description: "Start Y in screen points."),
        "toX": .number(description: "End X in screen points."),
        "toY": .number(description: "End Y in screen points.")
    ], required: ["fromX", "fromY", "toX", "toY"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        guard
            let fromX = arguments.double("fromX"), let fromY = arguments.double("fromY"),
            let toX = arguments.double("toX"), let toY = arguments.double("toY")
        else {
            throw AgentToolError.invalidArguments("缺少 fromX/fromY/toX/toY 屏幕坐标（points）。")
        }
        SystemControlSupport.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY)
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)
        return AgentToolResult(
            toolCallID: context.toolCallID, toolName: name,
            contentText: "已从 (\(Int(fromX)), \(Int(fromY))) 拖拽到 (\(Int(toX)), \(Int(toY)))。")
    }
}

/// macos_observe：一次调用同时返回截图 + 交互元素列表，替代 screenshot + ax_tree 两个往返。
public struct MacosObserveTool: AgentTool {
    public init() {}

    public let name = "macos_observe"
    public let description = "One-call screen observation: captures a downscaled screenshot (max 1568px long edge) AND returns the interactive-element accessibility list (buttons, fields, menus with labels and screen-point coordinates) of the frontmost or named application. Prefer this over separate macos_screenshot + macos_ax_tree calls — it saves a full model round trip per observation. Screen coordinate = image coordinate × scale + offset."
    public let permission: AgentPermissionCapability = .readSystemScreen
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "targetApp": .string(description: "Application bundleID or localized name substring for the element list. Defaults to the frontmost application."),
        "x": .number(description: "Region origin X. Omit x/width to capture the whole main display."),
        "y": .number(description: "Region origin Y."),
        "width": .number(description: "Region width in points."),
        "height": .number(description: "Region height in points."),
        "maxNodes": .integer(description: "Maximum interactive elements returned, default 120, clamped to 1-500.")
    ], required: [])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureScreenCapturePermission()
        let region: CGRect?
        if arguments.double("width") != nil, arguments.double("height") != nil {
            region = CGRect(
                x: arguments.double("x") ?? 0,
                y: arguments.double("y") ?? 0,
                width: arguments.double("width")!,
                height: arguments.double("height")!)
        } else {
            region = nil
        }
        let output = try SystemControlSupport.captureMainDisplay(region: region)
        let url = try SystemControlSupport.savePNG(output)
        let dataURL = "data:image/png;base64,\(output.pngData.base64EncodedString())"

        var lines: [String] = []
        lines.append(String(
            format: "截图：%@（%dx%d，左上角屏幕偏移 %d,%d，scale=%.3f；屏幕坐标 = 图内坐标 × scale + 偏移）",
            url.path, output.width, output.height, output.offsetX, output.offsetY, output.scale))

        let axAvailable = (try? SystemControlSupport.ensureAccessibilityPermission(prompt: false)) != nil
        if axAvailable, let app = try? SystemControlSupport.targetApplication(
            bundleID: arguments.string("targetApp"),
            name: arguments.string("targetApp")) {
            if (try? SystemControlSupport.ensureNotSelf(app)) != nil {
                var tree = SystemControlSupport.AXNodeText()
                SystemControlSupport.walkTree(
                    app,
                    depth: 0,
                    maxDepth: 20,
                    maxNodes: min(max(arguments.int("maxNodes") ?? 120, 1), 500),
                    interactiveOnly: true,
                    output: &tree)
                let title = SystemControlSupport.applicationTitle(of: app)
                if tree.lines.isEmpty {
                    lines.append("交互元素：目标应用「\(title)」没有暴露可交互元素（该应用 AX 支持较弱），请直接按截图坐标操作。")
                } else {
                    lines.append("交互元素（应用: \(title)，坐标为屏幕点，可直接传给 macos_input_click / macos_ax_action）：")
                    lines.append(contentsOf: tree.lines)
                }
            } else {
                lines.append("交互元素：目标是康纳同学自身，跳过（自身界面请直接看截图）。")
            }
        } else {
            lines.append(axAvailable
                ? "交互元素：未找到目标应用，仅返回截图。"
                : "交互元素：尚未授予辅助功能权限，仅返回截图（授权后可用）。")
        }

        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: lines.joined(separator: "\n"),
            modelContentParts: [.imageDataURL(dataURL, mimeType: "image/png")])
    }
}

/// macos_input_batch：一次调用顺序执行多个键鼠动作，把「点击输入框 → 键入 → 回车」这类
/// 序列从多个模型往返压缩为一个工具调用。
public struct MacosInputBatchTool: AgentTool {
    public init() {}

    public let name = "macos_input_batch"
    public let description = "Execute up to 10 mouse/keyboard actions in order within ONE call (click → type → key sequences, form filling, navigation). Stops at the first failure and reports per-action results. Actions: click (x,y,button,doubleClick), type (text), key (keys), scroll (x,y,delta,horizontal), drag (fromX,fromY,toX,toY). Use this instead of several macos_input_* calls whenever the steps are known in advance."
    public let permission: AgentPermissionCapability = .controlSystemInput
    public let inputSchema = AgentToolInputSchema.closedObject(properties: [
        "actions": .array(
            items: .object(properties: [
                "type": .stringEnumeration(values: ["click", "type", "key", "scroll", "drag"], description: "Action kind."),
                "x": .number(description: "click/scroll: screen coordinate X in points."),
                "y": .number(description: "click/scroll: screen coordinate Y in points."),
                "button": .stringEnumeration(values: ["left", "right"], description: "click: mouse button, default left."),
                "doubleClick": .boolean(description: "click: double click when true."),
                "text": .string(description: "type: text to enter."),
                "keys": .string(description: "key: key combo, for example command+a."),
                "delta": .integer(description: "scroll: positive up, negative down."),
                "horizontal": .boolean(description: "scroll: horizontal when true."),
                "fromX": .number(description: "drag: start X."),
                "fromY": .number(description: "drag: start Y."),
                "toX": .number(description: "drag: end X."),
                "toY": .number(description: "drag: end Y.")
            ], required: ["type"]),
            description: "Ordered actions, 1-10 items."),
    ], required: ["actions"])

    public func execute(arguments: AgentToolArguments, context: AgentToolExecutionContext) async throws -> AgentToolResult {
        try SystemControlSupport.ensureAccessibilityPermission(prompt: true)
        guard let actions = arguments.array("actions"), !actions.isEmpty else {
            throw AgentToolError.invalidArguments("缺少 actions 参数（1-10 个动作）。")
        }
        guard actions.count <= 10 else {
            throw AgentToolError.invalidArguments("actions 最多 10 个，请拆分多次调用。")
        }
        await ComputerControlConsent.shared.grant(sessionID: context.sessionID)

        var reports: [String] = []
        for (index, action) in actions.enumerated() {
            guard let object = action.objectValue else {
                reports.append("\(index + 1). 非对象动作，已跳过")
                continue
            }
            let args = AgentToolArguments(values: object)
            let kind = args.string("type") ?? ""
            do {
                let summary = try Self.perform(kind: kind, arguments: args)
                reports.append("\(index + 1). \(summary)")
            } catch {
                reports.append("\(index + 1). \(kind) 失败：\(error.localizedDescription)")
                reports.append("后续 \(actions.count - index - 1) 个动作未执行。")
                break
            }
        }
        return AgentToolResult(
            toolCallID: context.toolCallID,
            toolName: name,
            contentText: "批量动作执行结果：\n" + reports.joined(separator: "\n"))
    }

    /// 单个动作的执行与参数校验（与对应的单个工具行为一致）。
    private static func perform(kind: String, arguments args: AgentToolArguments) throws -> String {
        switch kind {
        case "click":
            guard let x = args.double("x"), let y = args.double("y") else {
                throw AgentToolError.invalidArguments("click 缺少 x/y")
            }
            let button = args.string("button") == "right" ? CGMouseButton.right : CGMouseButton.left
            let doubleClick = args.bool("doubleClick") ?? false
            SystemControlSupport.click(x: x, y: y, button: button, doubleClick: doubleClick)
            return "单击 (\(Int(x)), \(Int(y)))\(doubleClick ? " 双击" : "")"
        case "type":
            guard let text = args.string("text"), !text.isEmpty else {
                throw AgentToolError.invalidArguments("type 缺少 text")
            }
            SystemControlSupport.typeText(text)
            return "键入 \(text.count) 字符"
        case "key":
            guard let keys = args.string("keys"), !keys.isEmpty else {
                throw AgentToolError.invalidArguments("key 缺少 keys")
            }
            let parts = keys.split(whereSeparator: { $0 == "+" || $0 == "," }).map(String.init)
            try SystemControlSupport.keyCombo(parts)
            return "按键 \(parts.joined(separator: "+"))"
        case "scroll":
            guard let x = args.double("x"), let y = args.double("y"), let delta = args.int("delta"), delta != 0 else {
                throw AgentToolError.invalidArguments("scroll 需要 x/y 与非零 delta")
            }
            SystemControlSupport.scroll(x: x, y: y, delta: delta, horizontal: args.bool("horizontal") ?? false)
            return "滚动 \(delta)"
        case "drag":
            guard let fromX = args.double("fromX"), let fromY = args.double("fromY"),
                  let toX = args.double("toX"), let toY = args.double("toY") else {
                throw AgentToolError.invalidArguments("drag 缺少 fromX/fromY/toX/toY")
            }
            SystemControlSupport.drag(fromX: fromX, fromY: fromY, toX: toX, toY: toY)
            return "拖拽 (\(Int(fromX)),\(Int(fromY))) → (\(Int(toX)),\(Int(toY)))"
        default:
            throw AgentToolError.invalidArguments("未知动作类型：\(kind)")
        }
    }
}
