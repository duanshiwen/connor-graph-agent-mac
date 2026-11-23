import Foundation
import Observation

public struct RemoteModelCatalogProvider: Codable, Sendable, Equatable {
    public let id: String
    public let default_model: String
    public let models: [String]
    public let model_requirements: [String: [String]]?
}

public struct RemoteModelCatalogDocument: Codable, Sendable {
    public let schema_version: Int
    public let revision: String
    public let refresh_after_seconds: Int
    public let providers: [RemoteModelCatalogProvider]

    public static func parse(_ data: Data) throws -> Self {
        guard data.count <= 262_144 else { throw URLError(.dataLengthExceedsMaximum) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schema_version == 1, !value.revision.isEmpty, value.revision.count <= 80,
              (300...86400).contains(value.refresh_after_seconds),
              (1...100).contains(value.providers.count), Set(value.providers.map(\.id)).count == value.providers.count
        else { throw URLError(.cannotParseResponse) }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/@+-")
        func valid(_ id: String) -> Bool {
            guard let first = id.utf8.first else { return false }
            let alphanumeric = (48...57).contains(first) || (65...90).contains(first) || (97...122).contains(first)
            return alphanumeric && id.utf8.count <= 160 && id.unicodeScalars.allSatisfy(allowed.contains)
        }
        for p in value.providers {
            guard valid(p.id), (1...200).contains(p.models.count), Set(p.models).count == p.models.count,
                  p.models.allSatisfy(valid), p.models.contains(p.default_model)
            else { throw URLError(.cannotParseResponse) }
            for (model, flags) in p.model_requirements ?? [:] {
                guard p.models.contains(model), flags.count <= 16, flags.allSatisfy(valid)
                else { throw URLError(.cannotParseResponse) }
            }
        }
        return value
    }
}

/// Public metadata only. Never receives user API keys, prompts, or credential stores.
@MainActor @Observable
public final class AppRemoteModelCatalog {
    public static let shared = AppRemoteModelCatalog()
    public private(set) var document: RemoteModelCatalogDocument?
    private let preferences: UserDefaults
    private var refreshing = false
    private var nextAttempt = Date.distantPast
    private let cacheKey = "official-model-catalog-v1"
    private let endpoint = URL(string: "https://connor-agent.connor.run/api/v1/model-catalog")!

    public init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        if let data = preferences.data(forKey: cacheKey), let cached = try? RemoteModelCatalogDocument.parse(data) {
            document = cached
        } else if let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "ModelCatalog"),
                  let data = try? Data(contentsOf: url) {
            document = try? RemoteModelCatalogDocument.parse(data)
            preferences.removeObject(forKey: cacheKey + "-etag")
        }
    }

    public func provider(_ id: String) -> RemoteModelCatalogProvider? {
        let canonical: String
        switch id {
        case "openai-eu", "openai-us", "openai-responses": canonical = "openai"
        case "kimi": canonical = "moonshot"
        case "glm": canonical = "zhipu"
        default: canonical = id
        }
        guard let raw = document?.providers.first(where: { $0.id == canonical }) else { return nil }
        let supported: Set<String> = ["anthropic_signed_thinking_v1", "openai_reasoning_replay_v1"]
        let models = raw.models.filter { model in (raw.model_requirements?[model] ?? []).allSatisfy(supported.contains) }
        return RemoteModelCatalogProvider(id: raw.id, default_model: models.contains(raw.default_model) ? raw.default_model : (models.first ?? ""), models: models, model_requirements: raw.model_requirements)
    }

    public func refreshIfNeeded(
        force: Bool = false,
        load: (@Sendable (URLRequest) async throws -> (Data, HTTPURLResponse))? = nil
    ) async {
        guard !refreshing, force || Date() >= nextAttempt else { return }
        refreshing = true
        nextAttempt = Date().addingTimeInterval(300)
        defer { refreshing = false }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue(preferences.string(forKey: cacheKey + "-etag"), forHTTPHeaderField: "If-None-Match")
        do {
            let data: Data
            let http: HTTPURLResponse
            if let load {
                (data, http) = try await load(request)
            } else {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.httpShouldSetCookies = false
                let session = URLSession(configuration: configuration)
                defer { session.invalidateAndCancel() }
                let result = try await session.data(for: request)
                guard let response = result.1 as? HTTPURLResponse else { return }
                data = result.0
                http = response
            }
            guard http.url == endpoint else { return }
            if http.statusCode == 304 {
                nextAttempt = Date().addingTimeInterval(TimeInterval(document?.refresh_after_seconds ?? 21600))
                return
            }
            guard http.statusCode == 200 else { return }
            let candidate = try RemoteModelCatalogDocument.parse(data)
            preferences.set(data, forKey: cacheKey)
            preferences.set(http.value(forHTTPHeaderField: "ETag"), forKey: cacheKey + "-etag")
            document = candidate
            nextAttempt = Date().addingTimeInterval(TimeInterval(candidate.refresh_after_seconds))
        } catch { /* Keep the last valid catalog; no blocking alert for optional metadata. */ }
    }
}
