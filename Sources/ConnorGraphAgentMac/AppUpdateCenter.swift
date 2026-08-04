import AppKit
import Combine
import CryptoKit
import Foundation
import ConnorGraphAppSupport

public struct AppUpdateInfo: Decodable, Sendable, Equatable {
    public var platform: String
    public var latestVersion: String
    public var buildNumber: String
    public var downloadFileName: String
    public var sha256: String
    public var size: Int64
    public var notes: String
    public var publishedAt: String
    public var downloadUrl: String
}

enum AppUpdateError: LocalizedError {
    case invalidResponse
    case serverStatus(Int)
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "更新服务返回了无效响应。"
        case .serverStatus(let status): "更新服务不可用（HTTP \(status)）。"
        case .checksumMismatch: "下载校验失败（SHA-256 不匹配）。"
        }
    }
}

/// 自托管更新中心：从康纳后端拉取最新版本，下载安装包并校验后交给访达打开。
@MainActor
final class AppUpdateCenter: ObservableObject {
    static let shared = AppUpdateCenter()

    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var availableUpdate: AppUpdateInfo?
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    private var didCheckOnLaunch = false

    private var apiBaseURL: String? { AppBackendConnectivity.shared.baseURLString }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    func checkOnLaunch() {
        guard !didCheckOnLaunch else { return }
        didCheckOnLaunch = true
        Task { await checkNow() }
    }

    func checkNow() async {
        guard let base = apiBaseURL, !isChecking else { return }
        isChecking = true
        errorMessage = nil
        defer { isChecking = false }
        do {
            let endpoint = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                + "/api/v1/updates/latest?platform=macos&currentVersion="
                + currentVersion.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
            guard let url = URL(string: endpoint) else { throw AppUpdateError.invalidResponse }
            var request = URLRequest(url: url)
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppUpdateError.invalidResponse }
            if http.statusCode == 204 {
                availableUpdate = nil
                return
            }
            guard (200..<300).contains(http.statusCode) else { throw AppUpdateError.serverStatus(http.statusCode) }
            struct Envelope: Decodable { var data: AppUpdateInfo }
            availableUpdate = try JSONDecoder().decode(Envelope.self, from: data).data
        } catch {
            availableUpdate = nil
            errorMessage = error.localizedDescription
        }
    }

    func dismissUpdate() {
        availableUpdate = nil
        statusMessage = nil
        errorMessage = nil
    }

    func downloadAndOpen() async {
        guard let update = availableUpdate, let base = apiBaseURL, !isDownloading else { return }
        isDownloading = true
        errorMessage = nil
        statusMessage = "正在下载 \(update.downloadFileName)…"
        defer {
            isDownloading = false
            if statusMessage == "正在下载 \(update.downloadFileName)…" { statusMessage = nil }
        }
        do {
            let destination = try await Self.downloadInstaller(
                baseURLString: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
                downloadUrl: update.downloadUrl,
                fileName: update.downloadFileName
            )
            let digest = SHA256.hash(data: try Data(contentsOf: destination))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            guard hex.lowercased() == update.sha256.lowercased() else {
                try? FileManager.default.removeItem(at: destination)
                throw AppUpdateError.checksumMismatch
            }
            statusMessage = "已下载，正在打开安装包…"
            availableUpdate = nil
            NSWorkspace.shared.open(destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func downloadInstaller(baseURLString: String, downloadUrl: String, fileName: String) async throws -> URL {
        guard let url = URL(string: baseURLString + downloadUrl) else { throw AppUpdateError.invalidResponse }
        let destination = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppUpdateError.serverStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }
}
