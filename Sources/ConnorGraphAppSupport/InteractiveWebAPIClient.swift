import Foundation

public struct InteractiveWebAPIClient: Sendable {
    public var baseURL: URL
    private let transport: any ConnorBackendHTTPTransport
    private let credentials: any CloudKnowledgeCredentialProvider
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, transport: any ConnorBackendHTTPTransport = URLSession.shared, credentials: any CloudKnowledgeCredentialProvider = StoredCloudKnowledgeCredentialProvider()) {
        self.baseURL = baseURL; self.transport = transport; self.credentials = credentials
    }

    public func publish(project: LocalInteractiveWebProject, manifest: InteractiveWebManifest) async throws -> LocalInteractiveWebProject {
        let remoteProjectID: String
        if let existingProjectID = project.remoteProjectID {
            remoteProjectID = existingProjectID
        } else {
            remoteProjectID = try await createProject(name: project.name)
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
        var result = project; result.remoteProjectID = remoteProjectID; result.latestDeploymentID = deployment.id; return result
    }

    public func rollback(projectID: String, deploymentID: String) async throws {
        let _: RollbackResult = try await send("api/v1/projects/\(projectID)/rollback", method: "POST", body: Rollback(deploymentId: deploymentID))
    }

    private func createProject(name: String) async throws -> String {
        let project: RemoteProject = try await send("api/v1/projects", method: "POST", body: CreateProject(name: name)); return project.id
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        let url = baseURL.appendingPathComponent(path); var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue("Bearer \(try await credentials.accessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw InteractiveWebAPIError.server }
        guard let value = try? decoder.decode(Envelope<T>.self, from: data).data else { throw InteractiveWebAPIError.invalidResponse }; return value
    }

    private struct Envelope<T: Decodable>: Decodable { var data: T }
    private struct Empty: Encodable {}
    private struct CreateProject: Encodable { var name: String }
    private struct UploadPaths: Encodable { var paths: [String] }
    private struct Rollback: Encodable { var deploymentId: String }
    private struct RemoteProject: Decodable { var id: String }
    private struct Deployment: Decodable { var id: String }
    private struct UploadSession: Decodable { var uploadUrls: [String: URL] }
    private struct RollbackResult: Decodable { var currentDeploymentId: String }
}

public enum InteractiveWebAPIError: Error { case server, invalidResponse, uploadFailed }
