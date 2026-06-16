import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphMemory
import ConnorGraphSearch
import ConnorGraphAgent
import ConnorGraphStore
import ConnorGraphAppSupport

enum SettingsListTypography {
    // Mirror the chat detail typography scale so settings feels like part of the
    // same macOS app. Apple HIG recommends preserving hierarchy with size,
    // weight, and color while keeping macOS body text legible around 13 pt+.
    static let header: Font = AgentChatTypography.title
    static let rowTitle: Font = AgentChatTypography.body
    static let rowTitleSelected: Font = AgentChatTypography.bodyEmphasis
    static let rowSubtitle: Font = AgentChatTypography.meta
    static let rowCaption: Font = AgentChatTypography.micro
    static let rowCaptionEmphasized: Font = AgentChatTypography.microEmphasis
    static let actionTitle: Font = AgentChatTypography.callout
    static let icon: Font = .system(size: AgentChatTypography.controlIconSize, weight: .medium)
    static let largeIcon: Font = .system(size: 22, weight: .semibold)
}

enum SettingsListLayout {
    static let spaceXS = AgentChatLayout.spaceXS
    static let spaceS = AgentChatLayout.spaceS
    static let spaceM = AgentChatLayout.spaceM
    static let spaceL = AgentChatLayout.spaceL
    static let spaceXL = AgentChatLayout.spaceXL

    static let radiusS = AgentChatLayout.radiusS
    static let radiusM = AgentChatLayout.radiusM
    static let radiusL = AgentChatLayout.radiusL
    static let hairlineOpacity = AgentChatLayout.hairlineOpacity

    static let contentMaxWidth = AgentChatLayout.chatContentMaxWidth
    static let formMaxWidth: CGFloat = 560
    static let rowMinHeight = AgentChatLayout.hitTargetSize
    static let compactRowMinHeight: CGFloat = 38
    static let prominentRowMinHeight: CGFloat = 58
    static let fieldHeight = AgentChatLayout.hitTargetSize
    static let pickerControlWidth: CGFloat = 260
    static let compactPickerControlWidth: CGFloat = 220
    static let iconButtonSize = AgentChatLayout.iconButtonSize
    static let optionIconSize = AgentChatLayout.primaryButtonSize
}

struct ConnorSettingsDetailView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(viewModel.selectedSettingsSection.title)
                    .font(SettingsListTypography.header)
                    .frame(maxWidth: .infinity, alignment: .center)

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

struct SettingsAppSection: View {
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

struct SettingsAISection: View {
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
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceXL) {
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceXS) {
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
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceS)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)

            Button(action: { isShowingAddConnectionGuide = true }) {
                Label("添加连接", systemImage: "plus")
                    .font(SettingsListTypography.actionTitle)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, SettingsListLayout.spaceM)
                    .padding(.vertical, SettingsListLayout.spaceXS)
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

enum AIConnectionAuthenticationKind: Equatable {
    case authorizationCode
    case browserCallback
    case deviceCode(code: String, verificationURL: String)
    case direct
}

enum AIConnectionCustomProtocol: String, CaseIterable, Equatable {
    case openAICompatible
    case anthropicCompatible

    var title: String {
        switch self {
        case .openAICompatible: "OpenAI Compatible"
        case .anthropicCompatible: "Anthropic Compatible"
        }
    }
}

struct AIConnectionProviderPreset: Identifiable, Equatable {
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
        "deepseek", "xiaomi-mimo", "qwen", "doubao", "moonshot", "zhipu", "minimax", "stepfun", "zai"
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
        AIConnectionProviderPreset(id: "xiaomi-mimo", title: "Xiaomi MiMo", endpoint: "https://api.xiaomimimo.com/v1", defaultModel: "mimo-v2.5-pro", supportedModels: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2.5-asr", "mimo-v2.5-tts-voiceclone", "mimo-v2.5-tts-voicedesign", "mimo-v2.5-tts", "mimo-v2-pro", "mimo-v2-omni", "mimo-v2-tts"], keyPlaceholder: "MIMO_API_KEY", protocolKind: .openAICompatible, openAIAPIKeyHeaderKind: .apiKey),
        AIConnectionProviderPreset(id: "qwen", title: "阿里百炼 · Qwen", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1", defaultModel: "qwen-plus", supportedModels: ["qwen-plus", "qwen-max", "qwen-turbo", "qwen-long", "qwen3.5-plus", "qwen3.5-flash", "qwen3-max", "qwen3-coder-plus", "qwen3-vl-plus", "qwen3-vl-flash", "qwen3-omni-flash", "qwen3-asr-flash", "qwen3-tts-flash", "qwen-image-plus", "qwen-image-edit"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "doubao", title: "火山方舟 · 豆包", endpoint: "https://ark.cn-beijing.volces.com/api/v3", defaultModel: "doubao-seed-1-6", supportedModels: ["doubao-seed-1-6", "doubao-seed-1-6-thinking", "doubao-seed-1-6-flash", "doubao-seed-1-6-vision", "doubao-seed-1-6-embedding", "doubao-1-5-pro-32k"], keyPlaceholder: "Paste your ARK_API_KEY...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "moonshot", title: "Moonshot · Kimi", endpoint: "https://api.moonshot.cn/v1", defaultModel: "kimi-k2.6", supportedModels: ["kimi-k2.7-code", "kimi-k2.7-code-highspeed", "kimi-k2.6", "kimi-k2.5", "moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k", "moonshot-v1-8k-vision-preview", "moonshot-v1-32k-vision-preview", "moonshot-v1-128k-vision-preview"], keyPlaceholder: "sk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "zhipu", title: "智谱 GLM", endpoint: "https://open.bigmodel.cn/api/paas/v4", defaultModel: "glm-5.1", supportedModels: ["glm-5.2", "glm-5.1", "glm-5", "glm-5-turbo", "glm-4.7", "glm-4.7-flashx", "glm-4.6", "glm-4.5", "glm-4.5-air", "glm-4.5-airx", "glm-4-long", "glm-4-flashx-250414", "glm-4.7-flash", "glm-4.5-flash", "glm-4-flash-250414", "glm-4-plus", "glm-4-flash", "glm-z1-air", "glm-4.5v", "glm-5v-turbo", "glm-4.6v", "glm-ocr", "glm-realtime", "glm-4-voice", "glm-tts", "glm-tts-clone", "glm-asr-2512", "embedding-2"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "minimax", title: "MiniMax", endpoint: "https://api.minimax.chat/v1", defaultModel: "MiniMax-M3", supportedModels: ["MiniMax-M3", "MiniMax-M2.7", "MiniMax-M2.7-highspeed", "MiniMax-M2.5", "MiniMax-M2.5-highspeed", "MiniMax-M2.1", "MiniMax-M2.1-highspeed", "MiniMax-M2", "M2-her", "MiniMax-M1", "MiniMax-Text-01", "MiniMax-VL-01", "abab6.5s-chat", "abab6.5g-chat", "abab6.5t-chat"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "stepfun", title: "阶跃星辰 StepFun", endpoint: "https://api.stepfun.com/v1", defaultModel: "step3.7-flash", supportedModels: ["step3.7-flash", "step3.5-flash", "step-2-mini", "step-2-16k", "step-1-8k", "step-1-32k", "step-1-128k"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "xai", title: "xAI (Grok)", endpoint: "https://api.x.ai/v1", defaultModel: "grok-3-mini", keyPlaceholder: "xai-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "cerebras", title: "Cerebras", endpoint: "https://api.cerebras.ai/v1", defaultModel: "llama3.1-8b", keyPlaceholder: "csk-...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "zai", title: "z.ai (GLM)", endpoint: "https://api.z.ai/api/paas/v4", defaultModel: "glm-4.5", supportedModels: ["glm-4.5", "glm-4.5-air", "glm-4.5-flash", "glm-4-plus", "glm-4-flash"], keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "huggingface", title: "Hugging Face", endpoint: "https://router.huggingface.co/v1", defaultModel: "openai/gpt-oss-120b", keyPlaceholder: "hf_...", protocolKind: .openAICompatible),
        AIConnectionProviderPreset(id: "anthropic", title: "Anthropic API", endpoint: "https://api.anthropic.com", defaultModel: "claude-sonnet-4-5", keyPlaceholder: "sk-ant-...", protocolKind: .anthropicCompatible, authHeaderKind: .xAPIKey),
        AIConnectionProviderPreset(id: "openrouter-anthropic", title: "OpenRouter · Anthropic", endpoint: "https://openrouter.ai/api", defaultModel: "anthropic/claude-sonnet-4.5", keyPlaceholder: "sk-or-...", protocolKind: .anthropicCompatible, authHeaderKind: .bearer),
        AIConnectionProviderPreset(id: "vercel-anthropic", title: "Vercel AI Gateway · Anthropic", endpoint: "https://ai-gateway.vercel.sh/v1", defaultModel: "anthropic/claude-sonnet-4", keyPlaceholder: "vck_...", protocolKind: .anthropicCompatible, authHeaderKind: .bearer),
        AIConnectionProviderPreset(id: "custom", title: "Custom", endpoint: "", defaultModel: "", keyPlaceholder: "Paste your key here...", protocolKind: .openAICompatible)
    ]
}

struct AIConnectionOnboardingOption: Identifiable, Equatable {
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
            supportedModels: ["mimo-v2.5-pro", "mimo-v2.5", "mimo-v2.5-asr", "mimo-v2.5-tts-voiceclone", "mimo-v2.5-tts-voicedesign", "mimo-v2.5-tts", "mimo-v2-pro", "mimo-v2-omni", "mimo-v2-tts"],
            setupTitle: "连接 Xiaomi MiMo",
            setupSubtitle: "使用小米 MiMo OpenAI Compatible API 驱动康纳同学。",
            setupInstruction: "选择 MiMo 模型并填写 API Key。Endpoint 与 api-key 请求头已按官方文档预设。",
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

struct AIConnectionSetupView: View {
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

            VStack(spacing: SettingsListLayout.spaceXL) {
                VStack(spacing: SettingsListLayout.spaceS) {
                    Text(option.setupTitle)
                        .font(SettingsListTypography.header)
                    Text(option.setupSubtitle)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                setupContent
                    .frame(maxWidth: SettingsListLayout.formMaxWidth)

                if let statusMessage {
                    Text(statusMessage)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: SettingsListLayout.formMaxWidth)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(SettingsListTypography.rowSubtitle)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, SettingsListLayout.spaceL)
                        .padding(.vertical, SettingsListLayout.spaceM)
                        .frame(maxWidth: SettingsListLayout.formMaxWidth)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))
                }

                HStack(spacing: SettingsListLayout.spaceL) {
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
                .frame(maxWidth: SettingsListLayout.formMaxWidth)
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
                        .font(SettingsListTypography.rowTitle)
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

            HStack(alignment: .center, spacing: SettingsListLayout.spaceL) {
                Text("服务商")
                    .font(SettingsListTypography.header)
                Spacer(minLength: SettingsListLayout.spaceL)
                Picker("服务商", selection: $selectedProviderPresetID) {
                    ForEach(chinaProviderPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
                .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
            }
            .frame(maxWidth: .infinity, minHeight: SettingsListLayout.rowMinHeight)

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

            HStack(alignment: .center, spacing: SettingsListLayout.spaceL) {
                Text("服务商")
                    .font(SettingsListTypography.header)
                Spacer(minLength: SettingsListLayout.spaceL)
                Picker("服务商", selection: $selectedProviderPresetID) {
                    ForEach(AIConnectionProviderPreset.otherProviderPresets) { preset in
                        Text(preset.title).tag(preset.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
                .onChange(of: selectedProviderPresetID) { _, _ in applySelectedProviderPreset() }
            }
            .frame(maxWidth: .infinity, minHeight: SettingsListLayout.rowMinHeight)

            if selectedProviderPresetID == "custom" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Endpoint")
                        .font(SettingsListTypography.header)
                    TextField("https://your-api-endpoint.com", text: $baseURLString)
                        .textFieldStyle(.roundedBorder)
                        .font(SettingsListTypography.rowTitle)
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
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
                        .font(SettingsListTypography.rowTitle)
                }
                Text("使用服务商自己的模型 ID。当前 Connor 会用该模型执行一次真实连接校验。")
                    .font(SettingsListTypography.rowTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func apiKeyField(placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
            Text("API Key")
                .font(SettingsListTypography.header)
            HStack(spacing: SettingsListLayout.spaceS) {
                Group {
                    if showAPIKey {
                        TextField(placeholder, text: $apiKey)
                    } else {
                        SecureField(placeholder, text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(SettingsListTypography.rowTitle)
                Button(action: { showAPIKey.toggle() }) {
                    Image(systemName: showAPIKey ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(showAPIKey ? "隐藏 API Key" : "显示 API Key")
            }
            .padding(.horizontal, SettingsListLayout.spaceL)
            .frame(height: SettingsListLayout.fieldHeight)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private func modelMultiSelect(title: String, models: [String]) -> some View {
        VStack(alignment: .leading, spacing: SettingsListLayout.spaceM) {
            if !title.isEmpty {
                Text(title)
                    .font(SettingsListTypography.header)
            }
            VStack(alignment: .leading, spacing: SettingsListLayout.spaceS) {
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
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceM)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusM, style: .continuous))

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
                .pickerStyle(.menu)
                .controlSize(.large)
                .frame(width: SettingsListLayout.pickerControlWidth, alignment: .trailing)
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

struct AIConnectionOnboardingView: View {
    var choose: (AIConnectionOnboardingOption) -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: cancel) {
                    Label("返回", systemImage: "chevron.left")
                        .font(SettingsListTypography.rowTitleSelected)
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .background(.quaternary.opacity(0.28), in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .help("返回上一页")
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

struct ConnorConnectionMark: View {
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

struct AIConnectionOnboardingOptionRow: View {
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

struct AIConnectionEntryRow: View {
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

struct SettingsPermissionsSection: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isShowingPolicyDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsHeroHeader(
                title: "权限",
                subtitle: "控制新会话默认能做什么。运行中的会话仍可在输入框下方临时切换权限；项目目录在每个会话顶部的“当前会话 Workspace”中配置。",
                systemImage: "checkmark.shield"
            ) {
                EmptyView()
            }

            SettingsGroup(title: "新会话默认权限") {
                PermissionModePickerRow(selection: $viewModel.defaultPermissionMode)
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
                .padding(.top, SettingsListLayout.spaceS)
            } label: {
                Label("查看当前策略说明", systemImage: "list.bullet.rectangle")
                    .font(SettingsListTypography.rowTitleSelected)
            }
            .padding(.horizontal, SettingsListLayout.spaceL)
            .padding(.vertical, SettingsListLayout.spaceM)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsListLayout.radiusL, style: .continuous)
                    .stroke(Color.secondary.opacity(SettingsListLayout.hairlineOpacity), lineWidth: 1)
            )
        }
    }
}

struct PermissionModePickerRow: View {
    @Binding var selection: AgentPermissionMode

    private var availableModes: [AgentPermissionMode] {
        AgentPermissionMode.allCases.filter { $0 != .allowAll }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("权限模式")
                    .font(SettingsListTypography.rowTitleSelected)
                Text("作为新会话和重建会话的默认 Policy Engine 模式。")
                    .font(SettingsListTypography.rowCaption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: SettingsListLayout.spaceL)

            Menu {
                ForEach(availableModes, id: \.self) { mode in
                    Button {
                        selection = mode
                    } label: {
                        Label(mode.displayName, systemImage: mode.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Label(selection.displayName, systemImage: selection.systemImage)
                        .labelStyle(.titleAndIcon)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(SettingsListTypography.rowTitle)
                .padding(.horizontal, 10)
                .frame(width: 144, height: 34, alignment: .leading)
                .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(width: 160, alignment: .trailing)
            .help("选择新会话默认权限模式")
        }
        .frame(minHeight: SettingsListLayout.rowMinHeight)
    }
}

private extension AgentPermissionMode {
    var systemImage: String {
        switch self {
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
}

struct PermissionModeSummaryRow: View {
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

struct PermissionNoteRow: View {
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

struct PermissionBoundaryRow: View {
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

struct PermissionPolicyDetailRow: View {
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
