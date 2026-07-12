import Foundation
import ConnorGraphCore

public enum NoteImportSourceAccessError: Error, Sendable, Equatable {
    case bookmarkCreationFailed(String)
    case bookmarkResolutionFailed(String)
    case staleBookmark
    case accessDenied
    case pathEscapesAuthorizedRoot
}

public protocol NoteImportBookmarkCoding: Sendable {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool)
}

public struct SystemNoteImportBookmarkCodec: NoteImportBookmarkCoding {
    public init() {}
    public func createBookmark(for url: URL) throws -> Data {
        do { return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw NoteImportSourceAccessError.bookmarkCreationFailed(String(describing: error)) }
    }
    public func resolveBookmark(_ data: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url.standardizedFileURL, stale)
        } catch { throw NoteImportSourceAccessError.bookmarkResolutionFailed(String(describing: error)) }
    }
}

public final class NoteImportSourceAccessLease: @unchecked Sendable {
    public let rootURL: URL
    private let didStart: Bool
    private let lock = NSLock()
    private var released = false

    init(rootURL: URL, didStart: Bool) { self.rootURL = rootURL; self.didStart = didStart }
    public func validate(_ candidate: URL) throws -> URL {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let value = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard value.path == root.path || value.path.hasPrefix(rootPath) else { throw NoteImportSourceAccessError.pathEscapesAuthorizedRoot }
        return value
    }
    public func release() { lock.lock(); defer { lock.unlock() }; guard !released else { return }; released = true; if didStart { rootURL.stopAccessingSecurityScopedResource() } }
    deinit { release() }
}

public struct NoteImportSourceAccessService: Sendable {
    public var codec: any NoteImportBookmarkCoding
    public init(codec: any NoteImportBookmarkCoding = SystemNoteImportBookmarkCodec()) { self.codec = codec }

    public func authorize(url: URL, source: NoteImportSourceRecord) throws -> NoteImportSourceRecord {
        var source = source
        source.locationBookmark = try codec.createBookmark(for: url.standardizedFileURL)
        source.metadata["authorized_path"] = url.standardizedFileURL.path
        source.metadata["authorization_kind"] = url.hasDirectoryPath ? "directory" : "file"
        return source
    }

    public func access(source: NoteImportSourceRecord) throws -> NoteImportSourceAccessLease {
        guard let bookmark = source.locationBookmark else { throw NoteImportSourceAccessError.accessDenied }
        let resolved = try codec.resolveBookmark(bookmark)
        guard !resolved.isStale else { throw NoteImportSourceAccessError.staleBookmark }
        let didStart = resolved.url.startAccessingSecurityScopedResource()
        // Non-sandboxed development/test builds may return false while the URL remains readable.
        guard didStart || FileManager.default.isReadableFile(atPath: resolved.url.path) else { throw NoteImportSourceAccessError.accessDenied }
        return NoteImportSourceAccessLease(rootURL: resolved.url, didStart: didStart)
    }
}
