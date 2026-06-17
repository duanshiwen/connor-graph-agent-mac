import SwiftUI
import Combine
import Foundation
import Sparkle

struct ConnorAppVersionInfo: Equatable {
    var displayVersion: String
    var build: String
    var bundleIdentifier: String

    var displayText: String {
        if build.isEmpty || build == displayVersion {
            return displayVersion
        }
        return "\(displayVersion) (\(build))"
    }

    static func read(from bundle: Bundle = .main) -> ConnorAppVersionInfo {
        let info = bundle.infoDictionary ?? [:]
        let displayVersion = info["CFBundleShortVersionString"] as? String
            ?? info["CFBundleVersion"] as? String
            ?? "开发版本"
        let build = info["CFBundleVersion"] as? String ?? ""
        let bundleIdentifier = bundle.bundleIdentifier ?? "unknown.bundle"
        return ConnorAppVersionInfo(displayVersion: displayVersion, build: build, bundleIdentifier: bundleIdentifier)
    }
}

@MainActor
final class ConnorReleaseUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates: Bool = false
    @Published private(set) var currentVersion: ConnorAppVersionInfo
    @Published private(set) var configurationStatus: String

    private let updaterController: SPUStandardUpdaterController?
    private var cancellables: Set<AnyCancellable> = []

    init(bundle: Bundle = .main) {
        currentVersion = ConnorAppVersionInfo.read(from: bundle)
        if ConnorReleaseUpdateController.hasUsableSparkleConfiguration(in: bundle) {
            configurationStatus = "Sparkle 自动更新已配置。"
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller
            canCheckForUpdates = controller.updater.canCheckForUpdates
            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: RunLoop.main)
                .sink { [weak self] value in
                    self?.canCheckForUpdates = value
                }
                .store(in: &cancellables)
        } else {
            updaterController = nil
            canCheckForUpdates = false
            configurationStatus = "Sparkle 自动更新尚未完成发布配置：需要 SUFeedURL 与 SUPublicEDKey。"
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    var feedURLString: String {
        Bundle.main.infoDictionary?["SUFeedURL"] as? String ?? "未配置"
    }

    private static func hasUsableSparkleConfiguration(in bundle: Bundle) -> Bool {
        let info = bundle.infoDictionary ?? [:]
        guard let feedURL = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !feedURL.isEmpty,
              URL(string: feedURL) != nil else {
            return false
        }
        guard let publicKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !publicKey.isEmpty,
              !publicKey.contains("REPLACE"),
              !publicKey.contains("$(") else {
            return false
        }
        return true
    }
}

struct ConnorCheckForUpdatesCommandView: View {
    @ObservedObject var updateController: ConnorReleaseUpdateController

    var body: some View {
        Button("Check for Updates…") {
            updateController.checkForUpdates()
        }
        .disabled(!updateController.canCheckForUpdates)
    }
}
