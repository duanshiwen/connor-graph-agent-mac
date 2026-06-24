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
                Text("OpenAI Responses").tag(AppLLMProviderMode.openAIResponses)
                Text("OpenAI 兼容").tag(AppLLMProviderMode.openAICompatible)
                Text("Anthropic / Claude").tag(AppLLMProviderMode.anthropicMessages)
            }
            .pickerStyle(.segmented)

            TextField("接口地址", text: $viewModel.llmBaseURLString)
                .textFieldStyle(.roundedBorder)
            TextField("模型列表（逗号分隔）", text: $viewModel.llmModel)
                .textFieldStyle(.roundedBorder)
            SecureField("API Key", text: $viewModel.llmAPIKeyInput)
                .textFieldStyle(.roundedBorder)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Label("模型连接", systemImage: "sparkles.rectangle.stack")
                        .font(SettingsListTypography.rowCaptionEmphasized)
                    Text("模型连接用于生成回复；会话、工具调用和权限确认由康纳同学在本机统一管理。")
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
                    Label("安全提示：API Key 会加密保存在本机", systemImage: "lock.shield")
                        .font(SettingsListTypography.rowCaptionEmphasized)
                    Text("康纳同学会将 API Key 加密保存在本机，用于之后连接模型服务。")
                    Text("API Key 不会以明文写入应用设置、项目文件或 Git 仓库；删除 API Key 会移除对应凭据。")
                    Text("这是本机加密存储，不会上传到模型服务之外的地方。")
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
