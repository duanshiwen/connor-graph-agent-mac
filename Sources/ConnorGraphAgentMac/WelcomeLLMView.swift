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
                    viewModel.handleSuccessfulLLMSetup()
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
                        choose: { setupOption = $0 }
                    )
                }
            }
        }
    }
}

private struct WelcomeOnboardingContent: View {
    var choose: (AIConnectionOnboardingOption) -> Void

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

            Spacer(minLength: 56)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 760)
    }
}
