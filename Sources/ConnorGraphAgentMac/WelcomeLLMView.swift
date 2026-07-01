import SwiftUI
import AppKit
import ConnorGraphCore
import ConnorGraphAgent
import ConnorGraphAppSupport

struct WelcomeLLMView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var setupOption: AIConnectionOnboardingOption?

    var body: some View {
        if let option = setupOption {
            AIConnectionSetupView(
                viewModel: viewModel,
                option: option,
                complete: {
                    setupOption = nil
                },
                back: {
                    setupOption = nil
                },
                cancel: {
                    setupOption = nil
                }
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    WelcomeOnboardingContent(
                        choose: { setupOption = $0 },
                        canDismiss: !viewModel.llmConnectionConfigs.isEmpty,
                        dismiss: { viewModel.showWelcomePlaceholder = false }
                    )
                }
            }
        }
    }
}

private struct WelcomeOnboardingContent: View {
    var choose: (AIConnectionOnboardingOption) -> Void
    var canDismiss: Bool
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 56)

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

            if canDismiss {
                Button(action: dismiss) {
                    Label("开始使用", systemImage: "arrow.forward")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 12)
            }

            Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 760)
    }
}
