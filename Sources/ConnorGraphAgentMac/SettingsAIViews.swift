import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct LLMSettingsView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        Form {
            Picker("模型提供方", selection: $viewModel.llmProviderMode) {
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
                Text("Anthropic / Claude").tag(AppLLMProviderMode.anthropicMessages)
            }
            .pickerStyle(.segmented)

            TextField("Base URL", text: $viewModel.llmBaseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("模型列表（逗号分隔）", text: $viewModel.llmModel)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                .textFieldStyle(.roundedBorder)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("原生模型管线", systemImage: "sparkles.rectangle.stack")
                        .font(SettingsListTypography.rowCaptionEmphasized)
                    Text("Claude/Anthropic 现在通过 Connor 原生 Swift Messages API 管线执行；Session、工具、权限审批、审计和 Graph Memory 均由 Connor 自己持有，不再依赖 Claude SDK Sidecar。")
                }
                .font(SettingsListTypography.rowCaption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
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
    }
}
