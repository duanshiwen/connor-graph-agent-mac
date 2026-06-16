import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

private enum SettingsListTypography {
    static let header: Font = .system(size: 15.5, weight: .semibold)
    static let rowTitle: Font = .system(size: 14.5, weight: .regular)
    static let rowTitleSelected: Font = .system(size: 14.5, weight: .semibold)
    static let rowSubtitle: Font = .system(size: 12.5)
    static let rowCaption: Font = .system(size: 12.5)
    static let rowCaptionEmphasized: Font = .system(size: 12.5, weight: .semibold)
    static let actionTitle: Font = .system(size: 13.5, weight: .regular)
    static let icon: Font = .system(size: 16, weight: .medium)
    static let largeIcon: Font = .system(size: 22, weight: .semibold)
}

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("模型提供方", selection: $viewModel.llmProviderMode) {
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
                Text("Claude Sidecar").tag(AppLLMProviderMode.governedClaudeSidecar)
            }
            .pickerStyle(.segmented)

            if viewModel.llmProviderMode == .governedClaudeSidecar {
                GroupBox("Governed Claude SDK Sidecar") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Sidecar executable path，例如 /usr/local/bin/node", text: $viewModel.sidecarExecutablePath)
                            .textFieldStyle(.roundedBorder)
                        TextField("Sidecar arguments，例如 sidecars/claude-agent-engine/claude-sidecar.mjs", text: $viewModel.sidecarArguments)
                            .textFieldStyle(.roundedBorder)
                        TextField("Working directory", text: $viewModel.sidecarWorkingDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                        Picker("康纳同学权限模式", selection: $viewModel.sidecarPermissionMode) {
                            Text("只读").tag(AgentPermissionMode.readOnly)
                            Text("询问").tag(AgentPermissionMode.askToWrite)
                            Text("执行").tag(AgentPermissionMode.trustedWrite)
                        }
                        .pickerStyle(.segmented)
                        Text("安全边界：SDK permissionMode 固定为 bypassPermissions；康纳同学保留 session、pending approval、audit、graph memory 和 product state 主权。Sidecar 模式不允许 allowAll。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                TextField("Base URL", text: $viewModel.llmBaseURLString)
                    .textFieldStyle(.roundedBorder)
                TextField("模型列表（逗号分隔）", text: $viewModel.llmModel)
                    .textFieldStyle(.roundedBorder)
                SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("保存设置") { viewModel.saveLLMSettings() }
                Button("清除 API Key") { viewModel.clearLLMAPIKey() }
                Button("重新加载") { viewModel.loadLLMSettings() }
                Button(viewModel.isTestingLLMConnection ? "测试中…" : "测试连接") {
                    Task { await viewModel.testLLMConnection() }
                }
                .disabled(viewModel.isTestingLLMConnection)
            }

            Text(viewModel.llmHasAPIKey ? "API Key：已本地加密保存" : "API Key：尚未保存")
                .foregroundStyle(viewModel.llmHasAPIKey ? .green : .secondary)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("安全提示：API Key 会保存到康纳同学 Home 的本地加密凭据文件", systemImage: "lock.shield")
                        .font(SettingsListTypography.rowCaptionEmphasized)
                    Text("为减少钥匙串弹窗，康纳同学会使用本机生成的 master key 对 API Key 进行 AES-GCM 加密，并写入 Application Support/Connor/config/credentials。")
                    Text("API Key 不会以明文写入应用设置、项目文件或 Git 仓库；删除 API Key 会移除对应加密凭据文件。")
                    Text("这是本机本地加密存储，不依赖 macOS 钥匙串授权弹窗。")
                }
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let message = viewModel.llmSettingsMessage {
                Text(message).foregroundStyle(.secondary)
            }
            if let message = viewModel.llmHealthCheckMessage {
                Text(message).foregroundStyle(message.contains("OK") || message.contains("available") ? .green : .secondary)
            }
            if let error = viewModel.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle("模型设置")
    }
}

struct ConnorSettingsDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    Text(viewModel.selectedSettingsSection.title)
                        .font(SettingsListTypography.header)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Button(action: { viewModel.resetRuntimeSettings() }) {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.borderless)
                    .help("更多")
                }

                Group {
                    switch viewModel.selectedSettingsSection {
                    case .app:
                        SettingsAppSection(viewModel: viewModel)
                    case .ai:
                        SettingsAISection(viewModel: viewModel)
                    case .permissions:
                        SettingsPermissionsSection(viewModel: viewModel)
                    case .labels:
                        SettingsLabelsSection(viewModel: viewModel)
                    case .statuses:
                        SettingsStatusesSection(viewModel: viewModel)
                    case .shortcuts:
                        SettingsShortcutsSection(viewModel: viewModel)
                    case .preferences:
                        SettingsPreferencesSection(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity, alignment: .center)

                if let message = viewModel.appSettingsMessage {
                    Text(message)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .padding(.horizontal, 44)
            .padding(.vertical, 18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.12))
        .task {
            viewModel.loadRuntimeSettings()
        }
    }
}

private struct SettingsAppSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "通知") {
                SettingsToggleRow(title: "桌面通知", subtitle: "AI 在聊天中完成工作时发送通知。", isOn: $viewModel.desktopNotificationsEnabled)
            }
            SettingsGroup(title: "电源") {
                SettingsToggleRow(title: "保持屏幕常亮", subtitle: "会话运行时防止屏幕关闭。", isOn: $viewModel.keepScreenAwake)
            }
            SettingsGroup(title: "页面显示主题") {
                SettingsAppearanceModeRow(selection: $viewModel.appearanceMode)
            }
            SettingsGroup(title: "网络") {
                SettingsToggleRow(title: "HTTP 代理", subtitle: "通过代理服务器路由网络流量。", isOn: $viewModel.httpProxyEnabled)
                if viewModel.httpProxyEnabled {
                    Divider()
                    SettingsTextFieldRow(title: "代理地址", subtitle: "例如 http://127.0.0.1:7890", text: $viewModel.httpProxyURLString)
                }
            }
            SettingsGroup(title: "关于") {
                SettingsValueRow(title: "版本", value: "0.1.0")
                Divider()
                HStack {
                    Text("检查更新")
                    Spacer()
                    Button("立即检查") { viewModel.appSettingsMessage = "当前为本地开发版本。" }
                }
                .font(SettingsListTypography.rowTitle)
            }
        }
    }
}

private struct SettingsAISection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingAddConnectionGuide = false
    @State private var setupOption: AIConnectionOnboardingOption?

    var body: some View {
        Group {
            if let setupOption {
                AIConnectionSetupView(
                    viewModel: viewModel,
                    option: setupOption,
                    complete: { addConnection(from: setupOption) },
                    back: { self.setupOption = nil },
                    cancel: {
                        self.setupOption = nil
                        isShowingAddConnectionGuide = false
                    }
                )
            } else if isShowingAddConnectionGuide {
                AIConnectionOnboardingView(
                    choose: beginConnectionSetup(from:),
                    cancel: { isShowingAddConnectionGuide = false }
                )
            } else {
                connectionList
            }
        }
    }

    private var connectionList: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("连接")
                    .font(SettingsListTypography.header)
                Text("管理 AI 提供商连接。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(viewModel.llmConnectionConfigs) { connection in
                    AIConnectionEntryRow(
                        connection: connection,
                        isDefault: connection.id == viewModel.llmDefaultConnectionID,
                        canDelete: viewModel.llmConnectionConfigs.count > 1,
                        select: { viewModel.selectDefaultLLMConnection(connection.id) },
                        makeDefault: { viewModel.selectDefaultLLMConnection(connection.id) },
                        delete: {
                            viewModel.selectDefaultLLMConnection(connection.id)
                            viewModel.deleteSelectedLLMConnection()
                        }
                    )
                    if connection.id != viewModel.llmConnectionConfigs.last?.id {
                        Divider()
                            .padding(.leading, 32)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

            Button(action: { isShowingAddConnectionGuide = true }) {
                Label("添加连接", systemImage: "plus")
                    .font(SettingsListTypography.actionTitle)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func beginConnectionSetup(from option: AIConnectionOnboardingOption) {
        setupOption = option
    }

    private func addConnection(from option: AIConnectionOnboardingOption) {
        setupOption = nil
        isShowingAddConnectionGuide = false
    }
}

private enum AIConnectionAuthenticationKind: Equatable {
    case authorizationCode
    case browserCallback
    case deviceCode(code: String, verificationURL: String)
    case direct
}

private enum AIConnectionCustomProtocol: String, CaseIterable, Equatable {
    case openAICompatible
    case anthropicCompatible

    var title: String {
        switch self {
        case .openAICompatible: "OpenAI Compatible"
        case .anthropicCompatible: "Anthropic Compatible"
        }
    }
}

private struct AIConnectionProviderPreset: Identifiable, Equatable {
    var id: String
    var title: String
    var endpoint: String
    var defaultModel: String
    var supportedModels: [String] = []
    var keyPlaceholder: String
    var protocolKind: AIConnectionCustomProtocol
    var authHeaderKind: AnthropicCompatibleAuthHeaderKind = .xAPIKey
    var openAIAPIKeyHeaderKind: OpenAICompatibleAPIKeyHeaderKind = .bearer
    var hidesEndpoint: Bool = false

    var availableModels: [String] {
        if !supportedModels.isEmpty { return supportedModels }
        return defaultModel.isEmpty ? [] : [defaultModel]
    }

    static let chinaProviderPresetIDs: Set<String> = [
        "qwen", "doubao", "moonshot", "zhipu", "minimax", "stepfun"
    ]

    static var chinaProviderPresets: [AIConnectionProviderPreset] {
        otherProviderPresets.filter { chinaProviderPresetIDs.contains($0.id) }
    }

    static let otherProviderPresets: [AIConnectionProviderPreset] = [
        AIConnectionProviderPreset(id: "openai", title: "OpenAI", endpoint: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini", keyPlaceholder: "sk-...", protocolKind: .openAICompatible, hidesEndpoint: true),
        AIConnectionProviderPreset(id: "openai-eu", title: "OpenAI EU", endpoint: "https://eu.api.openai.com/v1", defaultModel: "gpt-4o-mini", keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "openai-us", title: "OpenAI US", endpoint: "https://us.api.openai.com/v1", defaultModel: "gpt-4o-mini", keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "google", title: "Google AI Studio", endpoint: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-2.5-flash", keyPlaceholder: "AIza...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "openrouter", title: "OpenRouter", endpoint: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini", keyPlaceholder: "sk-or-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "groq", title: "Groq", endpoint: "https://api.groq.com/openai/v1", defaultModel: "llama-3.3-70b-versatile", keyPlaceholder: "gsk_...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "mistral", title: "Mistral", endpoint: "https://api.mistral.ai/v1", defaultModel: "mistral-large-latest", keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "deepseek", title: "DeepSeek", endpoint: "https://api.deepseek.com", defaultModel: "deepseek-v4-flash", supportedModels: ["deepseek-v4-flash", "deepseek-v4-pro"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "xiaomi-mimo", title: "Xiaomi MiMo", endpoint: "https://api.xiaomimimo.com/v1", defaultModel: "mimo-v2.5-pro", supportedModels: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-flash"], keyPlaceholder: "MIMO_API_KEY", protocolKind: .openAICompatible, openAIAPIKeyHeaderKind: .apiKey),
        AIConnectionProviderPreset(id: "qwen", title: "阿里百炼 · Qwen", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", supportedModels: ["qwen-plus", "qwen-max", "qwen-turbo", "qwen-long", "qwen3-coder-plus"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "doubao", title: "火山方舟 · 豆包", endpoint: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-seed-1-6", supportedModels: ["doubao-seed-1-6", "doubao-seed-1-6-thinking", "doubao-seed-1-6-flash", "doubao-1-5-pro-32k"], keyPlaceholder: "Paste your ARK_API_KEY...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "moonshot", title: "Moonshot · Kimi", endpoint: "https://api.moonshot.cn/v1", defaultModel: "kimi-k2-0711-preview", supportedModels: ["kimi-k2-0711-preview", "kimi-latest", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "zhipu", title: "智谱 GLM", endpoint: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-4.5", supportedModels: ["glm-4.5", "glm-4.5-air", "glm-4-plus", "glm-4-flash"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "minimax", title: "MiniMax", endpoint: "https://api.minimax.chat/v1", defaultModel: "MiniMax-M1", supportedModels: ["MiniMax-M1", "abab6.5s-chat", "abab6.5g-chat", "abab6.5t-chat"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "stepfun", title: "阶跃星辰 StepFun", endpoint: "https://api.stepfun.com/v1", defaultModel: "step-2-mini", supportedModels: ["step-2-mini", "step-2-16k", "step-1-8k", "step-1-32k", "step-1-128k"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "xai", title: "xAI (Grok)", endpoint: "https://api.x.ai/v1", defaultModel: "grok-3-mini", keyPlaceholder: "xai-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "cerebras", title: "Cerebras", endpoint: "https://api.cerebras.ai/v1", defaultModel: "llama3.1-8b", keyPlaceholder: "csk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "zai", title: "z.ai (GLM)", endpoint: "https://api.z.ai/api/paas/v4", defaultModel: "glm-4.5", keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "huggingface", title: "Hugging Face", endpoint: "https://router.huggingface.co/v1", defaultModel: "openai/gpt-oss-120b", keyPlaceholder: "hf_...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "anthropic", title: "Anthropic API", endpoint: "https://api.anthropic.com", defaultModel: "claude-sonnet-4-5", keyPlaceholder: "sk-ant-...", protocolKind: .anthropicCompatible, authHeaderKind: .xAPIKey),
        AIConnectionProviderPreset(id: "openrouter-anthropic", title: "OpenRouter · Anthropic", endpoint: "https://openrouter.ai/api", defaultModel: "anthropic/claude-sonnet-4.5", keyPlaceholder: "sk-or-...", protocolKind: .anthropicCompatible, authHeaderKind: .bearer),
        AIConnectionProviderPreset(id: "vercel-anthropic", title: "Vercel AI Gateway · Anthropic", endpoint: "https://ai-gateway.vercel.sh/v1", defaultModel: "anthropic/claude-sonnet-4", keyPlaceholder: "vck_...", protocolKind: .anthropicCompatible, authHeaderKind: .bearer),
        AIConnectionProviderPreset(id: "custom", title: "Custom", endpoint: "", defaultModel: "", keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible)
    ]
}

private struct AIConnectionOnboardingOption: Identifiable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var providerMode: AppLLMProviderMode
    var connectionName: String
    var baseURLString: String
    var model: String
    var selectedModel: String
    var supportedModels: [String] = []
    var setupTitle: String
    var setupSubtitle: String
    var setupInstruction: String
    var loginButtonTitle: String
    var authURLString: String
    var authenticationKind: AIConnectionAuthenticationKind

    var requiresWebAuthentication: Bool { authenticationKind != .direct }

    var modelOptionsFallback: [String] {
        if !supportedModels.isEmpty { return supportedModels }
        let parsed = model.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !parsed.isEmpty { return parsed }
        return selectedModel.isEmpty ? [] : [selectedModel]
    }

    static let all: [AIConnectionOnboardingOption] = [
        AIConnectionOnboardingOption(
            id: "claude-pro-max",
            title: "Claude Pro / Max",
            subtitle: "已经有 Claude Pro / Max？用它来驱动康纳同学。",
            systemImage: "asterisk",
            tint: .orange,
            providerMode: .governedClaudeSidecar,
            connectionName: "Claude Pro / Max",
            baseURLString: "",
            model: "claude-sdk-default",
            selectedModel: "claude-sdk-default",
            setupTitle: "连接 Claude",
            setupSubtitle: "使用 Claude Pro / Max 订阅驱动康纳同学。",
            setupInstruction: "点击下方按钮打开 Claude 登录页。完成登录后，复制浏览器页面显示的授权码并粘贴到这里。",
            loginButtonTitle: "使用 Claude 登录",
            authURLString: "https://claude.ai/login",
            authenticationKind: .authorizationCode
        ),
        AIConnectionOnboardingOption(
            id: "codex-chatgpt-plus",
            title: "Codex · ChatGPT Plus",
            subtitle: "已经有 ChatGPT Plus？用 Codex 模式连接康纳同学。",
            systemImage: "sparkles",
            tint: .primary,
            providerMode: .openAICompatible,
            connectionName: "Codex · ChatGPT Plus",
            baseURLString: AppLLMSettings.default.baseURLString,
            model: AppLLMSettings.default.model,
            selectedModel: AppLLMSettings.default.effectiveModel,
            setupTitle: "连接 ChatGPT",
            setupSubtitle: "使用 ChatGPT Plus 订阅驱动康纳同学。",
            setupInstruction: "点击下方按钮使用 OpenAI 账号登录。登录完成后，康纳同学会自动验证并保存连接。",
            loginButtonTitle: "使用 ChatGPT 登录",
            authURLString: "https://auth.openai.com/oauth/authorize",
            authenticationKind: .browserCallback
        ),
        AIConnectionOnboardingOption(
            id: "github-copilot",
            title: "GitHub Copilot",
            subtitle: "已经有 GitHub Copilot？用它作为康纳同学的模型入口。",
            systemImage: "face.smiling.inverse",
            tint: .primary,
            providerMode: .openAICompatible,
            connectionName: "GitHub Copilot",
            baseURLString: "",
            model: "gpt-4.1",
            selectedModel: "gpt-4.1",
            setupTitle: "连接 GitHub Copilot",
            setupSubtitle: "使用 GitHub Copilot 订阅驱动康纳同学。",
            setupInstruction: "在 GitHub 页面输入此代码以授权。浏览器会打开 github.com/login/device。",
            loginButtonTitle: "打开 GitHub 授权页",
            authURLString: "https://github.com/login/device",
            authenticationKind: .deviceCode(code: "B3D1-87D5", verificationURL: "https://github.com/login/device")
        ),
        AIConnectionOnboardingOption(
            id: "deepseek",
            title: "DeepSeek",
            subtitle: "使用 DeepSeek API，适合国内开发、Agent 和高性价比推理。",
            systemImage: "bolt.horizontal.circle",
            tint: .blue,
            providerMode: .openAICompatible,
            connectionName: "DeepSeek",
            baseURLString: "https://api.deepseek.com",
            model: "deepseek-v4-flash",
            selectedModel: "deepseek-v4-flash",
            supportedModels: ["deepseek-v4-flash", "deepseek-v4-pro"],
            setupTitle: "连接 DeepSeek",
            setupSubtitle: "使用 DeepSeek OpenAI Compatible API 驱动康纳同学。",
            setupInstruction: "选择 DeepSeek 模型并填写 API Key。Endpoint 已按官方文档预设。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "xiaomi-mimo",
            title: "Xiaomi MiMo",
            subtitle: "使用小米 MiMo API，专为 Agent 与软件工程模型场景准备。",
            systemImage: "sparkle.magnifyingglass",
            tint: .orange,
            providerMode: .openAICompatible,
            connectionName: "Xiaomi MiMo",
            baseURLString: "https://api.xiaomimimo.com/v1",
            model: "mimo-v2.5-pro",
            selectedModel: "mimo-v2.5-pro",
            supportedModels: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2-omni", "mimo-v2-flash"],
            setupTitle: "连接 Xiaomi MiMo",
            setupSubtitle: "使用小米 MiMo OpenAI Compatible API 驱动康纳同学。",
            setupInstruction: "选择 MiMo 文本生成模型并填写 API Key。Endpoint 与 api-key 请求头已按官方文档预设。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "china-provider",
            title: "中国常用模型",
            subtitle: "接入 Qwen、豆包、Kimi、GLM、MiniMax、阶跃等国内常用 API。",
            systemImage: "globe.asia.australia",
            tint: .red,
            providerMode: .openAICompatible,
            connectionName: "阿里百炼 · Qwen",
            baseURLString: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-plus",
            selectedModel: "qwen-plus",
            setupTitle: "连接中国常用模型",
            setupSubtitle: "从国内常用模型 API 中选择一个兼容服务。",
            setupInstruction: "选择服务商和模型并填写 API Key。Endpoint 已按常用 OpenAI Compatible 地址预设。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "other-provider",
            title: "使用其他提供商",
            subtitle: "接入 Anthropic、AWS Bedrock、OpenRouter、Google 或其他兼容服务。",
            systemImage: "key",
            tint: .secondary,
            providerMode: .openAICompatible,
            connectionName: "其他提供商",
            baseURLString: AppLLMSettings.default.baseURLString,
            model: AppLLMSettings.default.model,
            selectedModel: AppLLMSettings.default.effectiveModel,
            setupTitle: "连接其他提供商",
            setupSubtitle: "接入 Anthropic、AWS Bedrock、OpenRouter、Google 或其他兼容服务。",
            setupInstruction: "下一步将填写 Base URL、模型和 API Key。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        ),
        AIConnectionOnboardingOption(
            id: "local-model",
            title: "本地模型",
            subtitle: "通过 Ollama 等本地服务，让康纳同学在你的电脑上运行模型。",
            systemImage: "desktopcomputer",
            tint: .secondary,
            providerMode: .openAICompatible,
            connectionName: "本地模型",
            baseURLString: "http://localhost:11434/v1",
            model: "llama3.2",
            selectedModel: "llama3.2",
            setupTitle: "连接本地模型",
            setupSubtitle: "通过 Ollama 等本地服务，让康纳同学在你的电脑上运行模型。",
            setupInstruction: "下一步将检查本地模型服务地址。",
            loginButtonTitle: "继续",
            authURLString: "",
            authenticationKind: .direct
        )
    ]
}

private struct AIConnectionSetupView: View {
    @ObservedObject var viewModel: AppViewModel
    var option: AIConnectionOnboardingOption
    var complete: () -> Void
    var back: () -> Void
    var cancel: () -> Void

    @State private var authorizationCode = ""
    @State private var didOpenBrowser = false
    @State private var isAuthenticating = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var claudeFlow: AppLLMOAuthService.ClaudePreparedFlow?
    @State private var githubDeviceCode: AppLLMGitHubDeviceCode?
    @State private var connectionName = ""
    @State private var baseURLString = ""
    @State private var model = ""
    @State private var selectedModel = ""
    @State private var selectedModelIDs: Set<String> = []
    @State private var apiKey = ""
    @State private var showAPIKey = false
    @State private var selectedProviderPresetID = "openai"
    @State private var customProtocol: AIConnectionCustomProtocol = .openAICompatible
    @State private var sidecarExecutablePath = Self.defaultSidecarExecutablePath()
    @State private var sidecarArguments = Self.defaultSidecarArguments()
    @State private var sidecarWorkingDirectoryPath = Self.defaultSidecarWorkingDirectoryPath()
    @State private var sidecarPermissionMode: AgentPermissionMode = .readOnly

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 72)

            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(option.setupTitle)
                        .font(SettingsListTypography.header)
                    Text(option.setupSubtitle)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                setupContent
                    .frame(maxWidth: 560)

                if let statusMessage {
                    Text(statusMessage)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: 560)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 14) {
                    Button(action: back) {
                        Text("返回")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Button(action: primaryAction) {
                        Label(primaryButtonTitle, systemImage: primaryButtonIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isPrimaryButtonDisabled || isAuthenticating)
                }
                .frame(maxWidth: 560)
            }

            Spacer(minLength: 96)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 760)
        .onAppear(perform: initializeDrafts)
    }

    @ViewBuilder
    private var setupContent: some View {
        switch option.authenticationKind {
        case .authorizationCode:
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(option.tint)
                    Text(option.setupInstruction)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(action: startClaudeOAuth) {
                    Label(didOpenBrowser ? "重新打开 Claude 登录页" : option.loginButtonTitle, systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                VStack(alignment: .leading, spacing: 8) {
                    Text("授权码")
                        .font(SettingsListTypography.header)
                    TextField("粘贴 Claude 页面显示的授权码", text: $authorizationCode)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsListTypography.rowSubtitle)
                        .textContentType(.oneTimeCode)
                    Text("授权码只用于完成本次连接。康纳同学会先验证，再保存连接。")
                        .font(SettingsListTypography.rowTitle)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .browserCallback:
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(option.tint)
                    Text(option.setupInstruction)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                if didOpenBrowser {
                    Text("浏览器已打开。完成网页认证后，康纳同学会自动验证并保存连接。")
                        .font(SettingsListTypography.header)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        case .deviceCode:
            VStack(spacing: 24) {
                Text(option.setupInstruction)
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if option.id == "github-copilot" {
                    githubCopilotAutomaticConfigurationSummary
                } else {
                    openAICompatibleFields(includeAPIKey: false)
                }
                if let githubDeviceCode {
                    Text(githubDeviceCode.userCode)
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .kerning(4)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
                        )
                        .textSelection(.enabled)
                    Text(didOpenBrowser ? "浏览器已打开 \(displayURL(githubDeviceCode.verificationURI))" : "点击下方按钮打开 \(displayURL(githubDeviceCode.verificationURI))")
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                } else {
                    Text("点击下方按钮获取 GitHub 授权码。")
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                }
            }
        case .direct:
            if option.id == "china-provider" {
                curatedChinaProviderAPIFields
            } else if option.id == "deepseek" || option.id == "xiaomi-mimo" {
                curatedSingleProviderAPIFields
            } else if option.id == "other-provider" {
                otherProviderAPIFields
            } else {
                VStack(spacing: 16) {
                    Text(option.setupInstruction)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    openAICompatibleFields(includeAPIKey: true)
                }
            }
        }
    }

    private var githubCopilotAutomaticConfigurationSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(option.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("自动配置 GitHub Copilot")
                        .font(SettingsListTypography.header)
                    Text("授权成功后，康纳同学会使用 Copilot token 中的 proxy endpoint 自动选择正确 API 地址，不需要手动填写 Base URL 或 API Key。")
                        .font(SettingsListTypography.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("连接名称")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(connectionName)
            }
            HStack {
                Text("Endpoint")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("由 Copilot 授权自动派生")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("默认模型")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? model : selectedModel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var curatedSingleProviderAPIFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(option.setupInstruction)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            modelMultiSelect(title: "启用模型", models: option.supportedModels.isEmpty ? [option.selectedModel] : option.supportedModels)
            apiKeyField(placeholder: option.id == "xiaomi-mimo" ? "MIMO_API_KEY" : "sk-...")
        }
    }

    private var curatedChinaProviderAPIFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(option.setupInstruction)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 8) {
                Text("服务商")
                    .font(SettingsListTypography.header)
                Picker("服务商", selection: $selectedProviderPresetID) {
                    ForEach(chinaProviderPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
            }

            modelMultiSelect(title: "启用模型", models: activeProviderPreset.availableModels)
            apiKeyField(placeholder: activeProviderPreset.keyPlaceholder)
        }
    }

    private var otherProviderAPIFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(option.setupInstruction)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            apiKeyField(placeholder: activeProviderPreset.keyPlaceholder)

            VStack(alignment: .leading, spacing: 8) {
                Text("服务商")
                    .font(SettingsListTypography.header)
                Picker("服务商", selection: $selectedProviderPresetID) {
                    ForEach(AIConnectionProviderPreset.otherProviderPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
            }

            if selectedProviderPresetID == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoint")
                        .font(SettingsListTypography.header)
                    TextField("https://your-api-endpoint.com", text: $baseURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsListTypography.rowSubtitle)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Protocol")
                        .font(SettingsListTypography.header)
                    Picker("Protocol", selection: $customProtocol) {
                        ForEach(AIConnectionCustomProtocol.allCases, id: \.self) { protocolKind in
                            Text(protocolKind.title).tag(protocolKind)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(customProtocol == .anthropicCompatible ? "Anthropic Compatible 使用 /v1/messages 协议，适合 Anthropic API、OpenRouter Anthropic Skin、Vercel AI Gateway 等兼容服务。" : "大多数第三方接口（Ollama、vLLM、DashScope 等）使用 OpenAI Compatible。")
                        .font(SettingsListTypography.rowTitle)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Model · required")
                    .font(SettingsListTypography.header)
                if selectedProviderPresetID != "custom" && !activeProviderPreset.supportedModels.isEmpty {
                    modelMultiSelect(title: "", models: activeProviderPreset.availableModels)
                } else {
                    TextField("例如 gpt-4o-mini、deepseek-v4-flash、google/gemini-2.5-flash", text: $model)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsListTypography.rowSubtitle)
                }
                Text("使用服务商自己的模型 ID。当前 Connor 会用该模型执行一次真实连接校验。")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func apiKeyField(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API Key")
                .font(SettingsListTypography.header)
            HStack(spacing: 8) {
                Group {
                    if showAPIKey {
                        TextField(placeholder, text: $apiKey)
                    } else {
                        SecureField(placeholder, text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(SettingsListTypography.rowSubtitle)
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func modelMultiSelect(title: String, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty {
                Text(title)
                    .font(SettingsListTypography.header)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(models, id: \.self) { modelID in
                    Toggle(isOn: Binding(
                        get: { selectedModelIDs.contains(modelID) },
                        set: { isOn in updateSelectedModels(modelID: modelID, isSelected: isOn, availableModels: models) }
                    )) {
                        HStack {
                            Text(modelID)
                            Spacer()
                            if selectedModel == modelID {
                                Text("默认")
                                    .font(SettingsListTypography.rowCaptionEmphasized)
                                    .foregroundStyle(option.tint)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack {
                Text("默认模型")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("默认模型", selection: $selectedModel) {
                    ForEach(enabledModels(in: models), id: \.self) { modelID in
                        Text(modelID).tag(modelID)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
                .onChange(of: selectedModel) { _, newValue in
                    if !selectedModelIDs.contains(newValue) { selectedModelIDs.insert(newValue) }
                    syncModelListFromSelection(fallbackModels: models)
                }
            }
            Text("可启用多个模型；默认模型用于首次 health check 和新会话默认选择。")
                .font(SettingsListTypography.rowTitle)
                .foregroundStyle(.secondary)
        }
    }

    private var activeProviderPreset: AIConnectionProviderPreset {
        AIConnectionProviderPreset.otherProviderPresets.first { $0.id == selectedProviderPresetID }
            ?? AIConnectionProviderPreset.otherProviderPresets[0]
    }

    private var chinaProviderPresets: [AIConnectionProviderPreset] {
        AIConnectionProviderPreset.chinaProviderPresets
    }

    private func openAICompatibleFields(includeAPIKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("连接名称", text: $connectionName)
                .textFieldStyle(.roundedBorder)
            TextField("Base URL", text: $baseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("模型", text: $model)
                .textFieldStyle(.roundedBorder)
            TextField("默认模型", text: $selectedModel)
                .textFieldStyle(.roundedBorder)
            if includeAPIKey {
                SecureField(option.id == "local-model" ? "API Key（本地模型可留空）" : "API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var primaryButtonTitle: String {
        if isAuthenticating { return "正在认证…" }
        switch option.authenticationKind {
        case .authorizationCode:
            return "验证并添加连接"
        case .browserCallback:
            return option.loginButtonTitle
        case .deviceCode:
            return githubDeviceCode == nil ? option.loginButtonTitle : "等待授权…"
        case .direct:
            return "验证并添加连接"
        }
    }

    private var primaryButtonIcon: String {
        if isAuthenticating { return "hourglass" }
        switch option.authenticationKind {
        case .authorizationCode:
            return "checkmark.shield"
        case .browserCallback:
            return "arrow.up.right.square"
        case .deviceCode:
            return githubDeviceCode == nil ? "arrow.up.right.square" : "circle.grid.3x3"
        case .direct:
            return "arrow.right"
        }
    }

    private var isPrimaryButtonDisabled: Bool {
        switch option.authenticationKind {
        case .authorizationCode:
            return authorizationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .direct:
            return connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || effectiveModelListForSubmit().isEmpty
                || (apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoopbackEndpoint(baseURLString))
        default:
            return false
        }
    }

    private func primaryAction() {
        switch option.authenticationKind {
        case .authorizationCode:
            exchangeClaudeCodeAndAddConnection()
        case .browserCallback:
            authenticateChatGPTAndAddConnection()
        case .deviceCode:
            authenticateGitHubCopilotAndAddConnection()
        case .direct:
            setupDirectOpenAICompatibleConnection()
        }
    }

    private func startClaudeOAuth() {
        do {
            let flow = try AppLLMOAuthService.shared.prepareClaudeOAuth()
            claudeFlow = flow
            NSWorkspace.shared.open(flow.authURL)
            didOpenBrowser = true
            statusMessage = "浏览器已打开。完成 Claude 登录后，复制授权码并粘贴到这里。"
            errorMessage = nil
        } catch {
            errorMessage = displayError(error)
        }
    }

    private func exchangeClaudeCodeAndAddConnection() {
        isAuthenticating = true
        statusMessage = "正在验证 Claude 授权码…"
        errorMessage = nil
        Task {
            do {
                let tokens = try await AppLLMOAuthService.shared.exchangeClaudeCode(authorizationCode)
                let input = AppLLMConnectionSetupInput(
                    id: stableConnectionID,
                    kind: .claudeSidecar,
                    name: connectionName,
                    model: model,
                    selectedModel: selectedModel,
                    oauthTokens: tokens,
                    sidecarExecutablePath: sidecarExecutablePath,
                    sidecarArguments: sidecarArguments,
                    sidecarWorkingDirectoryPath: sidecarWorkingDirectoryPath,
                    sidecarPermissionMode: sidecarPermissionMode
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func authenticateChatGPTAndAddConnection() {
        isAuthenticating = true
        didOpenBrowser = true
        statusMessage = "正在打开 ChatGPT 登录页，并等待浏览器回调…"
        errorMessage = nil
        Task {
            do {
                let result = try await AppLLMOAuthService.shared.authenticateChatGPT { url in
                    NSWorkspace.shared.open(url)
                }
                let input = AppLLMConnectionSetupInput(
                    id: stableConnectionID,
                    kind: .chatGPTCodex,
                    name: connectionName,
                    baseURLString: baseURLString,
                    model: model,
                    selectedModel: selectedModel,
                    apiKey: result.apiKey,
                    oauthTokens: result.tokens
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func authenticateGitHubCopilotAndAddConnection() {
        isAuthenticating = true
        statusMessage = githubDeviceCode == nil ? "正在向 GitHub 申请设备码…" : "正在等待 GitHub 授权完成…"
        errorMessage = nil
        Task {
            do {
                let code = try await AppLLMOAuthService.shared.startGitHubCopilotDeviceFlow()
                await MainActor.run {
                    githubDeviceCode = code
                    didOpenBrowser = true
                    if let url = URL(string: code.verificationURI) {
                        NSWorkspace.shared.open(url)
                    }
                    statusMessage = "在 GitHub 页面输入授权码后，康纳同学会自动继续。"
                }
                let tokens = try await AppLLMOAuthService.shared.pollGitHubCopilotTokens(deviceCode: code)
                let input = AppLLMConnectionSetupInput(
                    id: stableConnectionID,
                    kind: .githubCopilot,
                    name: connectionName,
                    baseURLString: "",
                    model: model,
                    selectedModel: selectedModel,
                    apiKey: tokens.accessToken,
                    oauthTokens: tokens
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func setupDirectOpenAICompatibleConnection() {
        isAuthenticating = true
        statusMessage = "正在验证连接…"
        errorMessage = nil
        Task {
            do {
                let usesProviderPreset = option.id == "other-provider" || option.id == "china-provider"
                let connectionKind: AppLLMConnectionKind = usesProviderPreset && customProtocol == .anthropicCompatible ? .anthropicCompatible : .openAICompatible
                let submittedModelList = effectiveModelListForSubmit()
                let submittedSelectedModel = selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? submittedModelList : selectedModel
                let input = AppLLMConnectionSetupInput(
                    id: nil,
                    kind: connectionKind,
                    name: connectionName,
                    baseURLString: baseURLString,
                    model: submittedModelList,
                    selectedModel: submittedSelectedModel,
                    apiKey: apiKey,
                    anthropicAuthHeaderKind: activeProviderPreset.authHeaderKind,
                    openAIAPIKeyHeaderKind: openAIAPIKeyHeaderKindForCurrentDraft()
                )
                _ = try await viewModel.setupLLMConnection(input)
                await MainActor.run {
                    isAuthenticating = false
                    complete()
                }
            } catch {
                await MainActor.run {
                    isAuthenticating = false
                    statusMessage = nil
                    errorMessage = displayError(error)
                }
            }
        }
    }

    private func initializeDrafts() {
        guard connectionName.isEmpty else { return }
        connectionName = option.connectionName
        baseURLString = option.baseURLString
        model = option.model
        selectedModel = option.selectedModel
        selectedModelIDs = Set(option.modelOptionsFallback)
        if selectedModelIDs.isEmpty, !selectedModel.isEmpty { selectedModelIDs = [selectedModel] }
        if option.id == "other-provider" {
            selectedProviderPresetID = "openai"
            applySelectedProviderPreset()
        }
        if option.id == "china-provider" {
            selectedProviderPresetID = "qwen"
            applySelectedProviderPreset()
        }
        if option.id == "claude-pro-max" {
            sidecarExecutablePath = sidecarExecutablePath.isEmpty ? Self.defaultSidecarExecutablePath() : sidecarExecutablePath
            sidecarArguments = sidecarArguments.isEmpty ? Self.defaultSidecarArguments() : sidecarArguments
            sidecarWorkingDirectoryPath = sidecarWorkingDirectoryPath.isEmpty ? Self.defaultSidecarWorkingDirectoryPath() : sidecarWorkingDirectoryPath
        }
    }

    private func applySelectedProviderPreset() {
        let preset = activeProviderPreset
        if preset.id != "custom" {
            connectionName = preset.title
            baseURLString = preset.endpoint
            model = preset.availableModels.joined(separator: ",")
            selectedModel = preset.defaultModel
            selectedModelIDs = Set(preset.availableModels)
            customProtocol = preset.protocolKind
        } else {
            connectionName = option.connectionName
            baseURLString = ""
            model = ""
            selectedModel = ""
            selectedModelIDs = []
            customProtocol = .openAICompatible
        }
    }

    private func updateSelectedModels(modelID: String, isSelected: Bool, availableModels: [String]) {
        if isSelected {
            selectedModelIDs.insert(modelID)
            if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { selectedModel = modelID }
        } else {
            selectedModelIDs.remove(modelID)
            if selectedModelIDs.isEmpty, let fallback = availableModels.first {
                selectedModelIDs.insert(fallback)
            }
            if selectedModel == modelID || !selectedModelIDs.contains(selectedModel) {
                selectedModel = enabledModels(in: availableModels).first ?? ""
            }
        }
        syncModelListFromSelection(fallbackModels: availableModels)
    }

    private func enabledModels(in availableModels: [String]) -> [String] {
        let selected = availableModels.filter { selectedModelIDs.contains($0) }
        return selected.isEmpty ? Array(availableModels.prefix(1)) : selected
    }

    private func syncModelListFromSelection(fallbackModels: [String]) {
        let models = enabledModels(in: fallbackModels)
        model = models.joined(separator: ",")
        if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !models.contains(selectedModel) {
            selectedModel = models.first ?? ""
        }
    }

    private func effectiveModelListForSubmit() -> String {
        if !selectedModelIDs.isEmpty {
            let sourceModels = currentPresetModelOptions()
            let enabled = sourceModels.filter { selectedModelIDs.contains($0) }
            if !enabled.isEmpty { return enabled.joined(separator: ",") }
        }
        return model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentPresetModelOptions() -> [String] {
        if option.id == "deepseek" || option.id == "xiaomi-mimo" {
            return option.supportedModels.isEmpty ? [option.selectedModel] : option.supportedModels
        }
        if option.id == "china-provider" || (option.id == "other-provider" && selectedProviderPresetID != "custom") {
            return activeProviderPreset.availableModels
        }
        return model.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func openAIAPIKeyHeaderKindForCurrentDraft() -> OpenAICompatibleAPIKeyHeaderKind {
        if option.id == "xiaomi-mimo" { return .apiKey }
        if option.id == "other-provider" || option.id == "china-provider" { return activeProviderPreset.openAIAPIKeyHeaderKind }
        return .bearer
    }

    private func isLoopbackEndpoint(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func defaultSidecarExecutablePath() -> String {
        for candidate in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "/opt/homebrew/bin/node"
    }

    private static func defaultSidecarArguments() -> String {
        let projectRoot = "/Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac"
        return "\(projectRoot)/sidecars/claude-agent-engine/claude-sidecar.mjs"
    }

    private static func defaultSidecarWorkingDirectoryPath() -> String {
        "/Users/duanshiwen/code/agent-os/agents/connor-graph-agent-mac"
    }

    private var stableConnectionID: String {
        switch option.id {
        case "claude-pro-max": "claude-pro-max"
        case "codex-chatgpt-plus": "codex-chatgpt-plus"
        case "github-copilot": "github-copilot"
        default: option.id
        }
    }

    private func displayError(_ error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty { return localized }
        return String(describing: error)
    }

    private func displayURL(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct AIConnectionOnboardingView: View {
    var choose: (AIConnectionOnboardingOption) -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: cancel) {
                    Label("返回", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 6)

            Spacer(minLength: 42)

            VStack(spacing: 18) {
                VStack(spacing: 12) {
                    ConnorConnectionMark()
                    VStack(spacing: 14) {
                        Text("欢迎使用康纳同学")
                            .font(SettingsListTypography.header)
                        Text("先选择一种连接方式，康纳同学会在下一步帮你完成配置。")
                            .font(SettingsListTypography.rowSubtitle)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                VStack(spacing: 14) {
                    ForEach(AIConnectionOnboardingOption.all) { option in
                        AIConnectionOnboardingOptionRow(option: option) {
                            choose(option)
                        }
                    }
                }
                .frame(maxWidth: 760)
            }

            Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 760)
    }
}

private struct ConnorConnectionMark: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 82, height: 82)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            .accessibilityLabel("康纳同学应用图标")
    }
}

private struct AIConnectionOnboardingOptionRow: View {
    var option: AIConnectionOnboardingOption
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.09))
                    Image(systemName: option.systemImage)
                        .font(SettingsListTypography.icon)
                        .foregroundStyle(option.tint)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.title)
                        .font(SettingsListTypography.rowTitleSelected)
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 16)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AIConnectionEntryRow: View {
    var connection: AppLLMConnectionConfig
    var isDefault: Bool
    var canDelete: Bool
    var select: () -> Void
    var makeDefault: () -> Void
    var delete: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: providerSystemImage)
                    .font(SettingsListTypography.icon)
                    .foregroundStyle(providerTint)
                    .frame(width: 18, alignment: .center)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(connection.name)
                            .font(isDefault ? SettingsListTypography.rowTitleSelected : SettingsListTypography.rowTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if isDefault {
                            Text("默认")
                                .font(SettingsListTypography.rowCaptionEmphasized)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.10), in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 16)

                Menu {
                    Button("设为默认", action: makeDefault)
                        .disabled(isDefault)
                    Divider()
                    Button(role: .destructive, action: delete) {
                        Text("删除连接")
                    }
                    .disabled(!canDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(SettingsListTypography.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .buttonStyle(.plain)
                .help("更多")
            }
            .contentShape(Rectangle())
            .frame(minHeight: 58)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        "\(providerDisplayName) · \(endpointDisplayName)"
    }

    private var providerDisplayName: String {
        switch connection.providerMode {
        case .openAICompatible:
            return "Craft Agents Backend Compatible"
        case .governedClaudeSidecar:
            return "Claude"
        }
    }

    private var endpointDisplayName: String {
        switch connection.providerMode {
        case .openAICompatible:
            return host(from: connection.baseURLString)
        case .governedClaudeSidecar:
            let arguments = connection.sidecarArguments.trimmingCharacters(in: .whitespacesAndNewlines)
            if !arguments.isEmpty { return URL(fileURLWithPath: arguments).lastPathComponent }
            return "Claude SDK Sidecar"
        }
    }

    private var providerSystemImage: String {
        switch connection.providerMode {
        case .openAICompatible:
            return "sparkles"
        case .governedClaudeSidecar:
            return "terminal"
        }
    }

    private var providerTint: Color {
        switch connection.providerMode {
        case .openAICompatible:
            return .primary
        case .governedClaudeSidecar:
            return .purple
        }
    }

    private func host(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "未设置 endpoint" }
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }
        return trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .split(separator: "/")
            .first
            .map(String.init) ?? trimmed
    }
}

private struct SettingsPermissionsSection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingPolicyDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("控制新会话默认能做什么。")
                    .font(SettingsListTypography.rowSubtitle)
                    .foregroundStyle(.primary)
                Text("运行中的会话仍可在输入框下方的权限按钮临时切换；项目目录在每个会话顶部的“当前会话 Workspace”中配置。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: "新会话默认权限") {
                SettingsPickerRow(title: "权限模式", subtitle: "作为新会话和重建会话的默认 Policy Engine 模式。", selection: $viewModel.defaultPermissionMode) {
                    ForEach(AgentPermissionMode.allCases.filter { $0 != .allowAll }, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Divider()
                PermissionModeSummaryRow(mode: viewModel.defaultPermissionMode)
            }

            SettingsGroup(title: "当前真实生效") {
                PermissionBoundaryRow(systemImage: "checkmark.shield", title: "权限模式会影响新会话", message: "这里选择的模式会写入 runtime-settings.json → loop.permissionMode，并用于创建或重建 NativeSessionManager。")
                Divider()
                PermissionBoundaryRow(systemImage: "network", title: "网络访问默认不单独审批", message: "在“询问”和“执行”模式下，externalNetwork 当前由 Policy Engine 默认通过；只读模式仍会拒绝外部网络。")
                Divider()
                PermissionBoundaryRow(systemImage: "terminal", title: "Shell 由风险分类决定", message: "只读 shell、workspace shell、network shell 和 destructive shell 由 LocalShellCommandPolicy 分类后交给 Policy Engine 决策。")
            }

            SettingsGroup(title: "安全边界") {
                PermissionBoundaryRow(systemImage: "lock.shield", title: "不提供全部允许", message: "allowAll 不在界面中开放。Claude Sidecar 的 bypassPermissions 只表示 Connor 接管审批，不代表无限制授权。")
                Divider()
                PermissionBoundaryRow(systemImage: "folder", title: "Workspace 属于会话", message: "Primary root 和 additional roots 在会话顶部设置，不在全局权限页管理。")
                Divider()
                PermissionBoundaryRow(systemImage: "person.crop.circle.badge.xmark", title: "本地单用户边界", message: "Connor 当前是单一 Home / Runtime Root，不做团队成员、组织角色或多用户权限。")
            }

            DisclosureGroup(isExpanded: $isShowingPolicyDetails) {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionPolicyDetailRow(title: "只读", message: "允许读取图谱、会话、workspace 文件、搜索文件、只读 shell、模型调用和本地科学计算；拒绝写入、删除、外部网络和危险 shell。")
                    PermissionPolicyDetailRow(title: "询问", message: "读取、普通模型调用、graph write proposal、外部网络默认允许；文件写入/编辑/删除、graph commit/删除、昂贵模型调用、workspace/network/destructive shell 进入审批。")
                    PermissionPolicyDetailRow(title: "执行", message: "文件写入/编辑、graph commit、workspace shell 可自动通过；图谱删除、文件删除、network shell、destructive shell 和昂贵模型调用仍需审批。")
                }
                .padding(.top, 8)
            } label: {
                Label("查看当前策略说明", systemImage: "list.bullet.rectangle")
                    .font(SettingsListTypography.rowTitleSelected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct PermissionModeSummaryRow: View {
    var mode: AgentPermissionMode

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.displayName)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(summary)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 52, alignment: .leading)
    }

    private var systemImage: String {
        switch mode {
        case .readOnly:
            return "eye"
        case .askToWrite:
            return "questionmark.circle"
        case .trustedWrite:
            return "bolt.circle"
        case .allowAll:
            return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch mode {
        case .readOnly:
            return .blue
        case .askToWrite:
            return .orange
        case .trustedWrite:
            return .green
        case .allowAll:
            return .red
        }
    }

    private var summary: String {
        switch mode {
        case .readOnly:
            return "适合探索、阅读和分析。写入、删除、网络和高风险 shell 会被拒绝。"
        case .askToWrite:
            return "适合日常协作。读取和普通工具可直接运行，写入、删除和高风险操作会先询问。"
        case .trustedWrite:
            return "适合你明确要让 Connor 连续执行修改时使用。普通写入和 workspace shell 可自动通过，删除和危险操作仍需审批。"
        case .allowAll:
            return "内部保留模式，不在产品界面中开放。"
        }
    }
}

private struct PermissionNoteRow: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsListTypography.rowCaptionEmphasized)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PermissionBoundaryRow: View {
    var systemImage: String
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(SettingsListTypography.rowTitleSelected)
                Text(message)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 46, alignment: .leading)
    }
}

private struct PermissionPolicyDetailRow: View {
    var title: String
    var message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(SettingsListTypography.rowCaptionEmphasized)
            Text(message)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WorkspaceRootsSettingsContent: View {
    @ObservedObject var viewModel: AppViewModel

    private var primaryRoot: WorkspaceRootDraft? {
        viewModel.workspaceRoots.first(where: \.isPrimary) ?? viewModel.workspaceRoots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前会话 Workspace")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text(summaryText)
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("选择目录…") { chooseDirectories() }
                    .buttonStyle(.bordered)
            }
            .frame(minHeight: 42)

            if !viewModel.workspaceRoots.isEmpty {
                Divider()
                VStack(spacing: 0) {
                    ForEach(viewModel.workspaceRoots) { root in
                        WorkspaceRootRow(
                            root: root,
                            setPrimary: { viewModel.setPrimaryWorkspaceRoot(id: root.id) },
                            remove: { viewModel.removeWorkspaceRoot(id: root.id) }
                        )
                        if root.id != viewModel.workspaceRoots.last?.id { Divider() }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("输入目录路径", text: $viewModel.workspaceRootPathInput)
                    .textFieldStyle(.roundedBorder)
                Button("添加路径") {
                    viewModel.addWorkspaceRoot(path: viewModel.workspaceRootPathInput)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.workspaceRootPathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("保存到当前 Session Capsule。Native local tools 可访问所有 roots；Claude Sidecar cwd 使用主目录。为空时兼容旧 Sidecar 目录，再回退到进程 cwd。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var summaryText: String {
        if let primaryRoot {
            return "主目录：\(primaryRoot.path) · 共 \(viewModel.workspaceRoots.count) 个 root"
        }
        let fallback = viewModel.defaultWorkingDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fallback.isEmpty { return "默认项目目录：\(fallback)" }
        return "尚未设置；将使用旧 Sidecar 工作目录或进程 cwd。"
    }

    private func chooseDirectories() {
        let panel = NSOpenPanel()
        panel.title = "选择当前会话项目工作目录"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK {
            viewModel.addWorkspaceRoots(paths: panel.urls.map(\.path))
        }
    }
}

private struct WorkspaceRootRow: View {
    var root: WorkspaceRootDraft
    var setPrimary: () -> Void
    var remove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(root.displayName.isEmpty ? URL(fileURLWithPath: root.path).lastPathComponent : root.displayName)
                        .font(SettingsListTypography.rowTitleSelected)
                    Text(root.role)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.10), in: Capsule())
                    if root.isPrimary {
                        Text("主目录")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                Text(root.path)
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !root.isPrimary {
                Button("设为主目录", action: setPrimary)
                    .buttonStyle(.bordered)
            }
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
        .frame(minHeight: 50)
        .padding(.vertical, 6)
    }
}

private struct SettingsLabelsSection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var editorRequest: SettingsLabelEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "标签",
                subtitle: "用颜色和名称整理会话。标签是纯标签：系统 UID、显示名、颜色和图标；不再承担值类型、图谱绑定或字段校验。",
                systemImage: "tag"
            ) {
                Button("新建标签…") { presentNewLabelEditor() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            SettingsGroup(title: "标签") {
                if viewModel.governanceConfig.labels.isEmpty {
                    SettingsEmptyStateRow(systemImage: "tag.slash", title: "暂无标签", subtitle: "点击“新建标签…”创建第一个会话标签。")
                } else {
                    ForEach(viewModel.governanceConfig.labels) { label in
                        SettingsLabelDefinitionRow(
                            definition: label,
                            usageCount: countSessions(using: label.id),
                            edit: { presentLabelEditor(label) },
                            delete: { viewModel.deleteLabelDefinition(label) }
                        )
                        if label.id != viewModel.governanceConfig.labels.last?.id { Divider().padding(.leading, 48) }
                    }
                }
            }

            SettingsGroup(title: "删除行为") {
                Text("删除标签会自动从所有会话中移除该标签，然后删除标签定义。")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $editorRequest) { request in
            SettingsLabelEditorSheet(
                title: request.isCreating ? "新建标签" : "编辑标签",
                definition: request.definition,
                onCancel: { editorRequest = nil },
                onSave: { updated in
                    viewModel.upsertLabelDefinition(updated)
                    editorRequest = nil
                }
            )
        }
    }

    private func presentLabelEditor(_ definition: AgentSessionLabelDefinition) {
        editorRequest = SettingsLabelEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewLabelEditor() {
        editorRequest = SettingsLabelEditorRequest(
            definition: AgentSessionLabelDefinition(id: "", name: "", colorName: "blue", systemImage: "tag"),
            isCreating: true
        )
    }

    private func countSessions(using labelID: String) -> Int {
        viewModel.allChatSessions.filter { session in
            session.governance.labels.contains { $0.id == labelID }
        }.count
    }
}

private struct SettingsStatusesSection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var editorRequest: SettingsStatusEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "状态",
                subtitle: "管理会话状态的显示名和图标。状态 UID 由系统生成；排序、终态等治理字段不在设置页暴露。",
                systemImage: "circle.dashed"
            ) {
                Button("新建状态…") { presentNewStatusEditor() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }

            SettingsGroup(title: "状态") {
                ForEach(sortedStatuses) { status in
                    SettingsStatusDefinitionRow(
                        definition: status,
                        usageCount: countSessions(using: status),
                        canDelete: viewModel.canDeleteStatusDefinition(status),
                        edit: { presentStatusEditor(status) },
                        delete: { viewModel.deleteStatusDefinition(status) }
                    )
                    if status.id != sortedStatuses.last?.id { Divider().padding(.leading, 48) }
                }
            }

            SettingsGroup(title: "删除限制") {
                Text("至少保留一个状态；如果已有会话正在使用某个状态，该状态不能删除。当前底层会话状态仍受 AgentSessionStatus 枚举约束，自定义状态定义会保存到治理配置，完整自定义状态切换需要后续迁移到 string-backed status ID。")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .sheet(item: $editorRequest) { request in
            SettingsStatusEditorSheet(
                title: request.isCreating ? "新建状态" : "编辑状态",
                definition: request.definition,
                onCancel: { editorRequest = nil },
                onSave: { updated in
                    viewModel.upsertStatusDefinition(updated)
                    editorRequest = nil
                }
            )
        }
    }

    private var sortedStatuses: [AgentSessionStatusDefinition] {
        viewModel.governanceConfig.statuses.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder { return lhs.name < rhs.name }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    private func presentStatusEditor(_ definition: AgentSessionStatusDefinition) {
        editorRequest = SettingsStatusEditorRequest(definition: definition, isCreating: false)
    }

    private func presentNewStatusEditor() {
        let nextSortOrder = (viewModel.governanceConfig.statuses.map(\.sortOrder).max() ?? 0) + 10
        editorRequest = SettingsStatusEditorRequest(
            definition: AgentSessionStatusDefinition(id: "", name: "", systemImage: "circle", sortOrder: nextSortOrder, isTerminal: false),
            isCreating: true
        )
    }

    private func countSessions(using definition: AgentSessionStatusDefinition) -> Int {
        viewModel.allChatSessions.filter { $0.governance.status.rawValue == definition.id }.count
    }
}

private struct SettingsLabelEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionLabelDefinition
    var isCreating: Bool
}

private struct SettingsStatusEditorRequest: Identifiable {
    var id = UUID()
    var definition: AgentSessionStatusDefinition
    var isCreating: Bool
}

private struct SettingsHeroHeader<Accessory: View>: View {
    var title: String
    var subtitle: String
    var systemImage: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(SettingsListTypography.header)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            accessory
        }
        .frame(minHeight: 72)
    }
}

private struct SettingsEmptyStateRow: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(SettingsListTypography.rowSubtitle)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 54)
    }
}

private struct SettingsLabelDefinitionRow: View {
    var definition: AgentSessionLabelDefinition
    var usageCount: Int
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(settingsLabelColor(from: definition.colorName)).frame(width: 28, height: 28)
                Image(systemName: definition.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name).font(SettingsListTypography.rowTitleSelected)
                Text("用于 \(usageCount) 个会话")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑…", action: edit)
                .controlSize(.regular)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .help("删除标签")
        }
        .frame(minHeight: 56)
        .contextMenu {
            Button("编辑标签…", systemImage: "pencil", action: edit)
            Button(role: .destructive, action: delete) { Label("删除标签", systemImage: "trash") }
        }
    }
}

private struct SettingsStatusDefinitionRow: View {
    var definition: AgentSessionStatusDefinition
    var usageCount: Int
    var canDelete: Bool
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: definition.systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(definition.name).font(SettingsListTypography.rowTitleSelected)
                Text("用于 \(usageCount) 个会话")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("编辑…", action: edit)
                .controlSize(.regular)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .frame(width: 44, height: 44)
            .disabled(!canDelete)
            .help(canDelete ? "删除状态" : "至少保留一个状态，且不能删除正在被会话使用的状态")
        }
        .frame(minHeight: 56)
        .contextMenu {
            Button("编辑状态…", systemImage: "pencil", action: edit)
            Button(role: .destructive, action: delete) { Label("删除状态", systemImage: "trash") }
                .disabled(!canDelete)
        }
    }
}

private struct SettingsLabelEditorSheet: View {
    var title: String
    var definition: AgentSessionLabelDefinition
    var onCancel: () -> Void
    var onSave: (AgentSessionLabelDefinition) -> Void

    @State private var name: String
    @State private var color: Color
    @State private var systemImage: String

    init(title: String, definition: AgentSessionLabelDefinition, onCancel: @escaping () -> Void, onSave: @escaping (AgentSessionLabelDefinition) -> Void) {
        self.title = title
        self.definition = definition
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: definition.name)
        _color = State(initialValue: settingsLabelColor(from: definition.colorName))
        _systemImage = State(initialValue: definition.systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(SettingsListTypography.header)
            TextField("标签名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("图标", selection: $systemImage) {
                ForEach(settingsLabelIconOptions, id: \.self) { icon in
                    Label(settingsLabelIconTitle(for: icon), systemImage: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
            ColorPicker("颜色", selection: $color, supportsOpacity: false)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(AgentSessionLabelDefinition(id: definition.id, name: settingsTrimmed(name), colorName: settingsColorStorageName(from: color), systemImage: systemImage))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(settingsTrimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct SettingsStatusEditorSheet: View {
    var title: String
    var definition: AgentSessionStatusDefinition
    var onCancel: () -> Void
    var onSave: (AgentSessionStatusDefinition) -> Void

    @State private var name: String
    @State private var systemImage: String

    init(title: String, definition: AgentSessionStatusDefinition, onCancel: @escaping () -> Void, onSave: @escaping (AgentSessionStatusDefinition) -> Void) {
        self.title = title
        self.definition = definition
        self.onCancel = onCancel
        self.onSave = onSave
        _name = State(initialValue: definition.name)
        _systemImage = State(initialValue: definition.systemImage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(SettingsListTypography.header)
            TextField("状态名称", text: $name)
                .textFieldStyle(.roundedBorder)
            Picker("图标", selection: $systemImage) {
                ForEach(settingsStatusIconOptions, id: \.self) { icon in
                    Label(settingsStatusIconTitle(for: icon), systemImage: icon).tag(icon)
                }
            }
            .pickerStyle(.menu)
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    onSave(AgentSessionStatusDefinition(id: definition.id, name: settingsTrimmed(name), systemImage: systemImage, sortOrder: definition.sortOrder, isTerminal: definition.isTerminal))
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(settingsTrimmed(name).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private let settingsStatusIconOptions: [String] = [
    "circle", "clock", "pause.circle", "play.circle", "checkmark.circle", "checkmark.circle.fill", "xmark.circle", "nosign", "exclamationmark.circle", "exclamationmark.bubble", "questionmark.circle", "flag", "star", "bolt", "flame", "tray", "archivebox", "paperplane", "hammer", "wrench.and.screwdriver", "lightbulb", "sparkles", "target"
]

private func settingsStatusIconTitle(for icon: String) -> String {
    switch icon {
    case "circle": return "圆点"
    case "clock": return "时钟"
    case "pause.circle": return "暂停"
    case "play.circle": return "进行中"
    case "checkmark.circle": return "完成"
    case "checkmark.circle.fill": return "完成（填充）"
    case "xmark.circle": return "关闭"
    case "nosign": return "受阻"
    case "exclamationmark.circle": return "提醒"
    case "exclamationmark.bubble": return "待审阅"
    case "questionmark.circle": return "询问"
    case "flag": return "旗标"
    case "star": return "星标"
    case "bolt": return "闪电"
    case "flame": return "火焰"
    case "tray": return "收件箱"
    case "archivebox": return "归档"
    case "paperplane": return "发送"
    case "hammer": return "构建"
    case "wrench.and.screwdriver": return "工具"
    case "lightbulb": return "想法"
    case "sparkles": return "闪光"
    case "target": return "目标"
    default: return icon
    }
}

private let settingsLabelIconOptions: [String] = [
    "tag", "tag.fill", "star", "star.fill", "flag", "flag.fill", "bookmark", "bookmark.fill", "doc.text", "doc.text.magnifyingglass", "folder", "folder.fill", "calendar", "calendar.badge.clock", "person.2", "link", "paperclip", "lightbulb", "sparkles", "flame"
]

private func settingsLabelIconTitle(for icon: String) -> String {
    switch icon {
    case "tag": return "标签"
    case "tag.fill": return "标签（填充）"
    case "star": return "星标"
    case "star.fill": return "星标（填充）"
    case "flag": return "旗标"
    case "flag.fill": return "旗标（填充）"
    case "bookmark": return "书签"
    case "bookmark.fill": return "书签（填充）"
    case "doc.text": return "文档"
    case "doc.text.magnifyingglass": return "研究"
    case "folder": return "文件夹"
    case "folder.fill": return "项目"
    case "calendar": return "日期"
    case "calendar.badge.clock": return "截止日期"
    case "person.2": return "协作"
    case "link": return "链接"
    case "paperclip": return "附件"
    case "lightbulb": return "想法"
    case "sparkles": return "闪光"
    case "flame": return "火焰"
    default: return icon
    }
}

private func settingsTrimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func settingsLabelColor(from storageName: String) -> Color {
    switch storageName {
    case "orange": return .orange
    case "purple": return .purple
    case "teal": return .teal
    case "red": return .red
    case "yellow": return .yellow
    case "green": return .green
    case "blue": return .blue
    default:
        guard storageName.hasPrefix("#"), storageName.count == 7 else { return .blue }
        let hex = String(storageName.dropFirst())
        guard let value = Int(hex, radix: 16) else { return .blue }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

private func settingsColorStorageName(from color: Color) -> String {
    let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .systemBlue
    let red = Int((nsColor.redComponent * 255).rounded())
    let green = Int((nsColor.greenComponent * 255).rounded())
    let blue = Int((nsColor.blueComponent * 255).rounded())
    return String(format: "#%02X%02X%02X", red, green, blue)
}

private struct SettingsShortcutsSection: View {
    @ObservedObject var viewModel: AppViewModel

    private let generalActions: [AgentRuntimeShortcutAction] = [
        .newSession,
        .toggleBrowser,
        .focusTopSearch,
        .openSettings
    ]

    private let browserActions: [AgentRuntimeShortcutAction] = [
        .focusBrowserAddress,
        .newBrowserTab,
        .closeBrowserTab,
        .browserBack,
        .browserForward,
        .toggleBrowserBookmarks,
        .toggleBrowserHistory
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "全局") {
                ForEach(generalActions.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    EditableShortcutRow(
                        title: title(for: generalActions[index]),
                        subtitle: subtitle(for: generalActions[index]),
                        shortcut: viewModel.shortcut(for: generalActions[index]),
                        onRecord: { viewModel.beginRecordingShortcut(for: generalActions[index]) },
                        onReset: { viewModel.resetShortcut(generalActions[index]) }
                    )
                }
            }

            SettingsGroup(title: "Browser Workspace") {
                ForEach(browserActions.indices, id: \.self) { index in
                    if index > 0 { Divider() }
                    EditableShortcutRow(
                        title: title(for: browserActions[index]),
                        subtitle: subtitle(for: browserActions[index]),
                        shortcut: viewModel.shortcut(for: browserActions[index]),
                        onRecord: { viewModel.beginRecordingShortcut(for: browserActions[index]) },
                        onReset: { viewModel.resetShortcut(browserActions[index]) }
                    )
                }
            }

            Text("修改后会写入 runtime-settings.json,并由菜单命令或 Browser Workspace 局部 key monitor 真实生效。Governance / Source / Skill 等低频入口不在此页暴露快捷键,避免占用过多 ⌘ 数字键。")
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $viewModel.recordingShortcutAction) { action in
            ShortcutRecorderSheet(
                title: title(for: action),
                currentShortcut: viewModel.shortcut(for: action),
                onCancel: { viewModel.recordingShortcutAction = nil },
                onSave: { shortcut in viewModel.updateShortcut(action, shortcut: shortcut) }
            )
        }
    }

    private func title(for action: AgentRuntimeShortcutAction) -> String {
        switch action {
        case .newSession: "新建聊天"
        case .toggleBrowser: "显示 / 隐藏浏览器"
        case .focusTopSearch: "聚焦顶部搜索"
        case .openSettings: "打开设置"
        case .focusBrowserAddress: "聚焦地址栏"
        case .newBrowserTab: "新建浏览器标签"
        case .closeBrowserTab: "关闭当前标签"
        case .browserBack: "后退"
        case .browserForward: "前进"
        case .toggleBrowserBookmarks: "打开 / 关闭书签"
        case .toggleBrowserHistory: "打开 / 关闭历史"
        }
    }

    private func subtitle(for action: AgentRuntimeShortcutAction) -> String {
        switch action {
        case .newSession: "创建新会话并进入聊天。"
        case .toggleBrowser: "在当前会话中切换内置浏览器工作区。"
        case .focusTopSearch: "聚焦应用顶部的会话搜索框。"
        case .openSettings: "打开设置中心。"
        case .focusBrowserAddress: "Browser Workspace 可见时聚焦地址栏。"
        case .newBrowserTab: "Browser Workspace 可见时创建新标签。"
        case .closeBrowserTab: "Browser Workspace 可见时关闭当前标签,不关闭 macOS 窗口。"
        case .browserBack: "Browser Workspace 当前标签后退。"
        case .browserForward: "Browser Workspace 当前标签前进。"
        case .toggleBrowserBookmarks: "切换浏览器书签面板。"
        case .toggleBrowserHistory: "切换浏览器历史面板。"
        }
    }
}

private struct SettingsPreferencesSection: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "基本信息") {
                SettingsTextFieldRow(title: "称呼", subtitle: "康纳同学如何称呼你。首次启动且未设置时会读取 macOS 账户名称，可手动更改。", text: $viewModel.userDisplayName)
                Divider()
                SettingsTextFieldRow(title: "时区", subtitle: "未设置时自动读取系统时区，用于相对日期和日程上下文。", text: $viewModel.userTimezone)
                Divider()
                SettingsTextFieldRow(title: "语言偏好", subtitle: "未设置时自动读取系统语言；康纳同学会优先按此语言回复。", text: $viewModel.userPreferredLanguage)
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("系统默认")
                            .font(SettingsListTypography.rowTitleSelected)
                        Text("只补全仍为空的项目，不覆盖你已经手动填写的偏好。")
                            .font(SettingsListTypography.rowCaption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("重新读取空白项") { viewModel.refreshSystemPreferenceDefaults() }
                        .buttonStyle(.bordered)
                }
            }
            SettingsGroup(title: "位置") {
                SettingsTextFieldRow(title: "城市", subtitle: "用于本地信息和上下文。不会在启动时自动请求定位权限，可手动填写或主动授权读取。", text: $viewModel.userCity)
                Divider()
                SettingsTextFieldRow(title: "国家/地区", subtitle: "未设置时会优先从系统地区推断，也可手动更改。", text: $viewModel.userCountry)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前位置")
                            .font(SettingsListTypography.rowTitleSelected)
                        if let message = viewModel.userLocationStatusMessage {
                            Text(message)
                                .font(SettingsListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("申请位置权限后自动填写城市和国家/地区。")
                                .font(SettingsListTypography.rowCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("使用当前位置") { viewModel.requestUserLocation() }
                        .buttonStyle(.bordered)
                }
            }
            SettingsGroup(title: "备注") {
                TextEditor(text: $viewModel.userPreferenceNotes)
                    .font(SettingsListTypography.rowTitle)
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(SettingsListTypography.header)
            VStack(spacing: 0) {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
            )
        }
    }
}

private struct SettingsAppearanceModeRow: View {
    @Binding var selection: ConnorAppearanceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("外观")
                        .font(SettingsListTypography.rowTitleSelected)
                    Text("选择应用页面的显示主题。")
                        .font(SettingsListTypography.rowCaption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Picker("页面显示主题", selection: $selection) {
                ForEach(ConnorAppearanceMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
        .frame(minHeight: 68, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    var title: String
    var subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Spacer()
            Text(value).font(SettingsListTypography.rowTitle).foregroundStyle(.secondary)
        }
        .frame(minHeight: 42)
    }
}

private struct SettingsTextFieldRow: View {
    var title: String
    var subtitle: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            TextField(title, text: $text)
                .font(SettingsListTypography.rowTitle)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct SettingsPickerRow<Selection: Hashable, Content: View>: View {
    var title: String
    var subtitle: String
    @Binding var selection: Selection
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Picker(title, selection: $selection) { content }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220)
        }
        .frame(minHeight: 46)
    }
}


private struct ShortcutRow: View {
    var title: String
    var keys: [String]

    var body: some View {
        HStack {
            Text(title).font(SettingsListTypography.rowTitleSelected)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key)
                        .font(SettingsListTypography.rowCaptionEmphasized)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
            }
        }
        .frame(minHeight: 38)
    }
}

// MARK: - Shortcut editing support

extension AgentRuntimeShortcutAction {
    var supportsGlobalCommandMenu: Bool {
        switch self {
        case .newSession, .toggleBrowser, .focusTopSearch, .openSettings:
            true
        default:
            false
        }
    }
}

extension AgentRuntimeKeyboardShortcut {
    var keyEquivalent: KeyEquivalent {
        switch key.lowercased() {
        case ",": return ","
        case ".": return "."
        case "/": return "/"
        case "[": return "["
        case "]": return "]"
        default:
            return KeyEquivalent(Character(String(key.lowercased().prefix(1))))
        }
    }

    var eventModifierFlags: EventModifiers {
        var flags: EventModifiers = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        return flags
    }

    static func from(event: NSEvent) -> AgentRuntimeKeyboardShortcut? {
        let flags = event.modifierFlags
        let character = event.charactersIgnoringModifiers?.lowercased()
        guard let rawKey = character, !rawKey.isEmpty else { return nil }
        let supported = [",", ".", "/", "[", "]"]
        let key: String
        if let scalar = rawKey.unicodeScalars.first, CharacterSet.alphanumerics.contains(scalar) {
            key = String(rawKey.prefix(1))
        } else if supported.contains(String(rawKey.prefix(1))) {
            key = String(rawKey.prefix(1))
        } else {
            return nil
        }
        return AgentRuntimeKeyboardShortcut(
            key: key,
            command: flags.contains(.command),
            shift: flags.contains(.shift),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }
}

struct ShortcutRecorderSheet: View {
    var title: String
    var currentShortcut: AgentRuntimeKeyboardShortcut
    var onCancel: () -> Void
    var onSave: (AgentRuntimeKeyboardShortcut) -> Void

    @State private var capturedShortcut: AgentRuntimeKeyboardShortcut?
    @State private var message: String = "按下新的快捷键。建议至少包含 ⌘。"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改快捷键")
                .font(SettingsListTypography.header)
            Text(title)
                .font(SettingsListTypography.rowTitleSelected)
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Text((capturedShortcut ?? currentShortcut).displayText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospaced()
            }
            .frame(height: 86)
            .background(ShortcutCaptureView { shortcut in
                capturedShortcut = shortcut
                message = shortcut.command ? "已捕捉: \(shortcut.displayText)" : "已捕捉: \(shortcut.displayText)。建议包含 ⌘。"
            })
            Text(message)
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
            HStack {
                Button("恢复当前") { capturedShortcut = currentShortcut }
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { onSave(capturedShortcut ?? currentShortcut) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    var onCapture: (AgentRuntimeKeyboardShortcut) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.onCapture = onCapture
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }

    final class CaptureView: NSView {
        var onCapture: ((AgentRuntimeKeyboardShortcut) -> Void)?
        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if let shortcut = AgentRuntimeKeyboardShortcut.from(event: event) {
                onCapture?(shortcut)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

struct EditableShortcutRow: View {
    var title: String
    var subtitle: String
    var shortcut: AgentRuntimeKeyboardShortcut
    var onRecord: () -> Void
    var onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(SettingsListTypography.rowTitleSelected)
                Text(subtitle).font(SettingsListTypography.rowCaption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortcut.displayText)
                .font(.caption.weight(.semibold).monospaced())
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.quaternary.opacity(0.30), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button("修改", action: onRecord)
                .buttonStyle(.bordered)
            Button("默认", action: onReset)
                .buttonStyle(.borderless)
        }
        .frame(minHeight: 50)
    }
}
