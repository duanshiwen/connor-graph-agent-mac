import Foundation

public struct InteractiveWebAPIClient: Sendable {
    public var baseURL: URL
    private let transport: any ConnorBackendHTTPTransport
    private let credentials: any CloudKnowledgeCredentialProvider
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared, credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider()) {
        self.baseURL = baseURL; self.transport = transport; self.credentials = credentials
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; self.encoder = encoder
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; self.decoder = decoder
    }

    public func publish(project: LocalInteractiveWebProject, manifest: InteractiveWebManifest) async throws -> LocalInteractiveWebProject {
        let remoteProjectID: String
        var remoteSiteID = project.remoteSiteID
        if let existingProjectID = project.remoteProjectID {
            remoteProjectID = existingProjectID
        } else {
            let remoteProject = try await createProject(name: project.name)
            remoteProjectID = remoteProject.id
            remoteSiteID = remoteProject.siteId
        }
        let deployment: Deployment = try await send("api/v1/projects/\(remoteProjectID)/deployments", method: "POST", body: Empty())
        let session: UploadSession = try await send("api/v1/deployments/\(deployment.id)/upload-session", method: "POST", body: UploadPaths(paths: manifest.files.map(\.path)))
        for file in manifest.files {
            guard let uploadURL = session.uploadUrls[file.path] else { throw InteractiveWebAPIError.invalidResponse }
            var request = URLRequest(url: uploadURL); request.httpMethod = "PUT"; request.httpBody = try Data(contentsOf: project.rootURL.appendingPathComponent(file.path)); request.setValue(file.mediaType, forHTTPHeaderField: "Content-Type")
            let (_, response) = try await transport.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InteractiveWebAPIError.uploadFailed }
        }
        let _: Deployment = try await send("api/v1/deployments/\(deployment.id)/finalize", method: "POST", body: manifest)
        var result = project
        result.remoteProjectID = remoteProjectID
        result.remoteSiteID = remoteSiteID
        result.latestDeploymentID = deployment.id
        if let siteID = result.remoteSiteID { result.publishedURL = baseURL.appendingPathComponent("s/\(siteID)") }
        return result
    }

    public func projects(limit: Int = 50) async throws -> [InteractiveWebRemoteProject] {
		try await get("api/v1/projects?limit=\(min(max(limit, 1), 100))")
	}

	public func project(id: String) async throws -> InteractiveWebRemoteProjectDetail {
		try await get("api/v1/projects/\(id)")
	}

	public func projectFile(projectID: String, path: String) async throws -> Data {
		guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
			throw InteractiveWebAPIError.invalidResponse
		}
		var url = baseURL.appendingPathComponent("api/v1/projects/\(projectID)/files")
		for component in path.split(separator: "/") { url.appendPathComponent(String(component)) }
		var request = URLRequest(url: url)
		request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
		let (data, response) = try await transport.data(for: request)
		guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InteractiveWebAPIError.server }
		return data
	}

	public func publicSiteURL(siteID: String) -> URL { baseURL.appendingPathComponent("s/\(siteID)") }

    public func rollback(projectID: String, deploymentID: String) async throws {
        let _: RollbackResult = try await send("api/v1/projects/\(projectID)/rollback", method: "POST", body: Rollback(deploymentId: deploymentID))
    }

    public func records(projectID: String, collection: String, limit: Int = 100) async throws -> InteractiveWebRecordPage {
        guard collection.range(of: #"^[a-z_][a-z0-9_]{0,63}$"#, options: .regularExpression) != nil else { throw InteractiveWebAPIError.invalidResponse }
        return try await get("api/v1/projects/\(projectID)/collections/\(collection)/records?limit=\(min(max(limit, 1), 1000))")
    }

    public func exportCSV(projectID: String, collection: String) async throws -> Data {
        guard collection.range(of: #"^[a-z_][a-z0-9_]{0,63}$"#, options: .regularExpression) != nil else { throw InteractiveWebAPIError.invalidResponse }
        let url = baseURL.appendingPathComponent("api/v1/projects/\(projectID)/collections/\(collection)/export")
        var request = URLRequest(url: url); request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InteractiveWebAPIError.server }; return data
    }

    public func updateAccessPolicy(siteID: String, mode: InteractiveWebAccessMode, password: String? = nil, expiresAt: Date? = nil) async throws {
        let _: AccessPolicyResult = try await send("api/v1/sites/\(siteID)/access-policy", method: "PATCH", body: AccessPolicy(mode: mode.rawValue, password: password, expiresAt: expiresAt))
    }

    public func offline(siteID: String) async throws {
        try await sendNoContent("api/v1/sites/\(siteID)/offline", method: "POST")
    }

    public func analytics(projectID: String) async throws -> InteractiveWebAnalytics {
        try await get("api/v1/projects/\(projectID)/analytics")
    }

    public func auditLogs(projectID: String, limit: Int = 100) async throws -> [InteractiveWebAuditEntry] {
        try await get("api/v1/projects/\(projectID)/audit-logs?limit=\(min(max(limit, 1), 200))")
    }

    private func createProject(name: String) async throws -> RemoteProject {
        try await send("api/v1/projects", method: "POST", body: CreateProject(name: name))
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        let url = baseURL.appendingPathComponent(path); var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InteractiveWebAPIError.server }
        guard let value = try? decoder.decode(Envelope<T>.self, from: data).data else { throw InteractiveWebAPIError.invalidResponse }; return value
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingPathComponent("/"))?.absoluteURL else { throw InteractiveWebAPIError.invalidResponse }
        var request = URLRequest(url: url); request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let value = try? decoder.decode(Envelope<T>.self, from: data).data else { throw InteractiveWebAPIError.server }; return value
    }

    private func sendNoContent(_ path: String, method: String) async throws {
        let url = baseURL.appendingPathComponent(path); var request = URLRequest(url: url); request.httpMethod = method; request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (_, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InteractiveWebAPIError.server }
    }

    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private struct Empty: Encodable {}
    private struct CreateProject: Encodable { var name: String }
    private struct UploadPaths: Encodable { var paths: [String] }
    private struct Rollback: Encodable { var deploymentId: String }
    private struct RemoteProject: Decodable { var id: String; var siteId: String }
    private struct Deployment: Decodable { var id: String }
    private struct UploadSession: Decodable { var uploadUrls: [String: URL] }
    private struct RollbackResult: Decodable { var currentDeploymentId: String }
    private struct AccessPolicy: Encodable { var mode: String; var password: String?; var expiresAt: Date? }
    private struct AccessPolicyResult: Decodable { var mode: String; var expiresAt: Date? }
}

public struct InteractiveWebRemoteProject: Codable, Sendable, Equatable {
	public var id: String
	public var name: String
	public var siteId: String
	public var status: String
	public var accessMode: String
	public var currentDeploymentId: String?
	public var createdAt: String
	public var updatedAt: String
}

public struct InteractiveWebRemoteDeployment: Codable, Sendable, Equatable {
	public var id: String
	public var projectId: String
	public var version: Int
	public var status: String
	public var failureCode: String?
	public var createdAt: String
	public var finalizedAt: String?
}

public struct InteractiveWebRemoteFile: Codable, Sendable, Equatable {
	public var id: String
	public var deploymentId: String
	public var path: String
	public var sha256: String
	public var mediaType: String
	public var sizeBytes: Int64
	public var createdAt: String
}

public struct InteractiveWebRemoteCollection: Codable, Sendable, Equatable {
	public var name: String
	public var schemaVersion: Int
	public var recordCount: Int64
}

public struct InteractiveWebRemoteProjectDetail: Codable, Sendable, Equatable {
	public var id: String
	public var name: String
	public var siteId: String
	public var status: String
	public var accessMode: String
	public var currentDeploymentId: String?
	public var createdAt: String
	public var updatedAt: String
	public var deployments: [InteractiveWebRemoteDeployment]
	public var files: [InteractiveWebRemoteFile]
	public var collections: [InteractiveWebRemoteCollection]
}

public struct InteractiveWebRecordMetadata: Codable, Sendable, Equatable {
    public var id: String
	public var data: [String: ConnorJSONValue]
    public var status: String
    public var checkedInAt: Date?
    public var createdAt: Date
}

public struct InteractiveWebRecordPage: Codable, Sendable, Equatable {
	public var items: [InteractiveWebRecordMetadata]
	public var total: Int
}

public struct InteractiveWebAuditEntry: Decodable, Sendable, Equatable {
    public var id: String
    public var actorId: Int
    public var actorRole: String
    public var action: String
    public var resourceId: String
    public var createdAt: Date
}

public enum InteractiveWebAPIError: Error { case server, invalidResponse, uploadFailed }
