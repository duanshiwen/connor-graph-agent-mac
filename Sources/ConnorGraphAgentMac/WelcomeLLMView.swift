import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct WelcomeLLMView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 32)

                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.tint)
                    Text("欢迎使用康纳同学")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Text("请配置 AI 连接以开始使用")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                LLMSettingsView(viewModel: viewModel)
                    .frame(maxWidth: 520)

                Button("跳过，稍后设置") {
                    viewModel.showWelcomePlaceholder = false
                }
                .buttonStyle(.link)
                .padding(.top, 8)

                Spacer(minLength: 32)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 600)
        }
    }
}
