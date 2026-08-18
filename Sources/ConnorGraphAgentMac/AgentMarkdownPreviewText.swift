import SwiftUI
@preconcurrency import AppKit
import ImageIO
import UniformTypeIdentifiers
import ConnorGraphAgent
import ConnorGraphAppSupport

enum AgentMarkdownPreviewRenderStrategy: Equatable {
    case inlineOnly
    case plainText
    case deferredPreview
    case compiledDocument

    static let deferredPreviewCharacterThreshold = 12_000

    static func strategy(
        lineLimit: Int?,
        monospacedFallback: Bool,
        markdownCharacterCount: Int,
        allowsDeferredPreview: Bool = true
    ) -> AgentMarkdownPreviewRenderStrategy {
        if lineLimit != nil { return .inlineOnly }
        if monospacedFallback { return .plainText }
        if allowsDeferredPreview, markdownCharacterCount >= deferredPreviewCharacterThreshold { return .deferredPreview }
        return .compiledDocument
    }
}

enum AgentMarkdownDeferredPreviewPolicy {
    static let characterLimit = 4_000

    static func source(for markdown: String) -> String {
        let endIndex = markdown.index(
            markdown.startIndex,
            offsetBy: characterLimit,
            limitedBy: markdown.endIndex
        ) ?? markdown.endIndex
        return String(markdown[..<endIndex])
    }
}

struct AgentMarkdownPreviewText: View {
    var markdown: String
    var font: Font = AgentChatTypography.body
    var bodyPointSize: CGFloat? = nil
    var monospacedFallback: Bool = false
    var lineLimit: Int? = nil
    var maxRenderedBlocks: Int? = nil
    var allowsDeferredPreview: Bool = true
    var allowsUserExpansion: Bool = false
    var persistentCacheContext: AgentMarkdownPersistentCacheContext? = nil
    @State private var loadedDocument: AgentMarkdownCompiledDocument?
    @State private var isUserExpanded = false

    private final class RenderCache: @unchecked Sendable {
        static let shared = RenderCache()
        private let documentCache = AgentMarkdownCompiledDocumentCache(limit: 600)
        private let inlineCache: NSCache<NSString, AttributedStringBox> = {
            let cache = NSCache<NSString, AttributedStringBox>()
            cache.countLimit = 1_200
            cache.totalCostLimit = 8 * 1_024 * 1_024
            return cache
        }()

        private final class AttributedStringBox: NSObject {
            let value: AttributedString

            init(_ value: AttributedString) {
                self.value = value
            }
        }

        func document(
            _ markdown: String,
            persistentCacheContext: AgentMarkdownPersistentCacheContext?
        ) -> AgentMarkdownCompiledDocument {
            documentCache.document(
                for: markdown,
                loadBlocks: { source in
                    guard let persistentCacheContext else { return nil }
                    return try? persistentCacheContext.store.loadBlocks(
                        sessionID: persistentCacheContext.sessionID,
                        messageID: persistentCacheContext.messageID,
                        content: source
                    )
                },
                persistBlocks: { source, blocks in
                    guard let persistentCacheContext else { return }
                    try? persistentCacheContext.store.saveBlocks(
                        sessionID: persistentCacheContext.sessionID,
                        messageID: persistentCacheContext.messageID,
                        content: source,
                        blocks: blocks
                    )
                }
            )
        }

        func inlineRendered(_ markdown: String, attributed: AttributedString? = nil) -> AttributedString {
            let cacheKey = markdown as NSString
            if let cached = inlineCache.object(forKey: cacheKey) {
                return cached.value
            }

            let parsed = attributed ?? (try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )) ?? AttributedString(markdown)
            inlineCache.setObject(
                AttributedStringBox(parsed),
                forKey: cacheKey,
                cost: max(markdown.utf8.count, 1)
            )
            return parsed
        }
    }

    private var documentLoadID: String {
        let contentID = AgentMarkdownDocumentCompiler.stableFingerprint(markdown)
        let expansionID = "deferred:\(effectiveAllowsDeferredPreview)"
        guard let persistentCacheContext else { return "\(contentID)|\(expansionID)" }
        return "\(persistentCacheContext.sessionID)|\(persistentCacheContext.messageID)|\(contentID)|\(expansionID)"
    }

    private var markdownContentID: String {
        AgentMarkdownDocumentCompiler.stableFingerprint(markdown)
    }

    private var effectiveAllowsDeferredPreview: Bool {
        allowsDeferredPreview && !isUserExpanded
    }

    private func renderWindow(for document: AgentMarkdownCompiledDocument) -> AgentMarkdownCompiledRenderWindow {
        AgentMarkdownCompiledRenderWindowPolicy().window(
            for: document,
            maxRenderedBlocks: maxRenderedBlocks
        )
    }

    private var lightweightInlineRendered: AttributedString {
        RenderCache.shared.inlineRendered(markdown)
    }

    private var deferredPreviewInlineRendered: AttributedString {
        RenderCache.shared.inlineRendered(AgentMarkdownDeferredPreviewPolicy.source(for: markdown))
    }

    private var renderStrategy: AgentMarkdownPreviewRenderStrategy {
        AgentMarkdownPreviewRenderStrategy.strategy(
            lineLimit: lineLimit,
            monospacedFallback: monospacedFallback,
            markdownCharacterCount: markdown.utf8.count,
            allowsDeferredPreview: effectiveAllowsDeferredPreview
        )
    }

    private var allowedImageRoot: URL? {
        guard let persistentCacheContext else { return nil }
        return persistentCacheContext.store.storagePaths
            .sessionArtifactDirectories(sessionID: persistentCacheContext.sessionID)
            .root
    }

    @ViewBuilder
    var body: some View {
        Group {
            switch renderStrategy {
            case .inlineOnly:
                inlineText(
                    lightweightInlineRendered,
                    font: monospacedFallback ? monospacedBodyFont : font,
                    nativeFont: monospacedFallback ? monospacedBodyNSFont : bodyNSFont
                )
                    .lineLimit(lineLimit)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .plainText:
                Text(markdown)
                    .font(monospacedBodyFont)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .deferredPreview:
                deferredPreviewView(
                    statusText: "内容较长，已先显示轻量预览以保持界面响应。",
                    showsExpansionControl: allowsUserExpansion
                )
            case .compiledDocument:
                if let loadedDocument, loadedDocument.source == markdown {
                    compiledDocumentView(loadedDocument)
                } else if markdown.utf8.count >= AgentMarkdownPreviewRenderStrategy.deferredPreviewCharacterThreshold {
                    deferredPreviewView(statusText: "正在展开完整内容…", showsProgress: true)
                } else {
                    Color.clear
                        .frame(height: bodyPointSize ?? 17)
                        .accessibilityHidden(true)
                }
            }
        }
        .task(id: documentLoadID) {
            guard renderStrategy == .compiledDocument else { return }
            let source = markdown
            let cacheContext = persistentCacheContext
            let loadTask = Task.detached(priority: .utility) {
                RenderCache.shared.document(source, persistentCacheContext: cacheContext)
            }
            let document = await withTaskCancellationHandler {
                await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            guard !Task.isCancelled, document.source == markdown else { return }
            loadedDocument = document
        }
        .onChange(of: markdownContentID) {
            isUserExpanded = false
            loadedDocument = nil
        }
    }

    private func deferredPreviewView(
        statusText: String,
        showsProgress: Bool = false,
        showsExpansionControl: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            inlineText(deferredPreviewInlineRendered, font: font, nativeFont: bodyNSFont)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                if showsProgress {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }
                Text(statusText)
                    .font(secondaryFont)
                    .foregroundStyle(.secondary)
            }
            if showsExpansionControl {
                AgentMessageExpansionButton(
                    title: "展开完整内容",
                    systemImage: "chevron.down",
                    accessibilityLabel: "展开并显示完整文件内容",
                    help: "加载并显示完整 Markdown 内容",
                    action: expandFullContent
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func expandFullContent() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isUserExpanded = true
        }
    }

    private func compiledDocumentView(_ document: AgentMarkdownCompiledDocument) -> some View {
        let window = renderWindow(for: document)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(window.blocks) { block in
                view(for: block)
            }
            if window.omittedBlockCount > 0 {
                omittedBlocksIndicator(count: window.omittedBlockCount)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: AgentMarkdownCompiledBlock) -> some View {
        switch block.content {
        case .heading(let level, let text, let inline):
            inlineText(
                RenderCache.shared.inlineRendered(text, attributed: inline),
                font: headingFont(level),
                nativeFont: headingNSFont(level)
            )
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph(let text, let inline):
            inlineText(RenderCache.shared.inlineRendered(text, attributed: inline), font: font, nativeFont: bodyNSFont)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .unorderedItem(let text, let inline):
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(font)
                    .foregroundStyle(.secondary)
                    .frame(width: 12, alignment: .trailing)
                    .padding(.top, 1)
                inlineText(RenderCache.shared.inlineRendered(text, attributed: inline), font: font, nativeFont: bodyNSFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
        case .orderedItem(let number, let text, let inline):
            HStack(alignment: .top, spacing: 8) {
                Text("\(number).")
                    .font(font)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
                    .padding(.top, 1)
                inlineText(RenderCache.shared.inlineRendered(text, attributed: inline), font: font, nativeFont: bodyNSFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 2)
        case .quote(let text, let inline):
            HStack(alignment: .top, spacing: 8) {
                inlineText(
                    RenderCache.shared.inlineRendered(text, attributed: inline),
                    font: font,
                    nativeFont: bodyNSFont,
                    nativeColor: .secondaryLabelColor
                )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.28))
                            .frame(width: 3)
                    }
                AgentMarkdownBlockCopyButton(text: text, label: "复制引用", accessibilityLabel: "复制整段引用")
                    .padding(.top, 2)
            }
        case .image(let altText, let source):
            AgentMarkdownImageView(
                altText: altText,
                source: source,
                allowedRoot: allowedImageRoot
            )
        case .taskItem(let isCompleted, let text, let inline):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .font(font)
                    .foregroundStyle(isCompleted ? .secondary : .tertiary)
                    .frame(width: 14, alignment: .center)
                    .padding(.top, 1)
                inlineText(
                    RenderCache.shared.inlineRendered(text, attributed: inline),
                    font: font,
                    nativeFont: bodyNSFont,
                    nativeColor: isCompleted ? .secondaryLabelColor : .labelColor,
                    strikethrough: isCompleted
                )
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted, color: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
        case .code(let language, let text):
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    if let language, !language.isEmpty {
                        Text(language)
                            .font(monospacedLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    AgentMarkdownBlockCopyButton(text: text, label: "复制代码", accessibilityLabel: "复制整段代码")
                }
                Text(text)
                    .font(monospacedBodyFont)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        case .table(let table):
            markdownTableView(table)
        case .horizontalRule:
            Rectangle()
                .fill(Color.secondary.opacity(0.24))
                .frame(height: 1)
                .padding(.vertical, 6)
        case .spacer:
            Color.clear.frame(height: 4)
        }
    }

    private func omittedBlocksIndicator(count: Int) -> some View {
        Text("已暂缓渲染后续 \(count) 个 Markdown 块，展开后完整显示")
            .font(secondaryFont)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func markdownTableView(_ table: AgentMarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
                        tableCell(header, isHeader: true, alignment: alignment(for: table.alignments[safe: index] ?? .leading))
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(table.headers.indices), id: \.self) { index in
                            tableCell(row[safe: index] ?? "", isHeader: false, alignment: alignment(for: table.alignments[safe: index] ?? .leading))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tableCell(_ text: String, isHeader: Bool, alignment: Alignment) -> some View {
        inlineText(
            renderTableCellInline(text),
            font: isHeader ? font.weight(.semibold) : font,
            nativeFont: isHeader ? NSFontManager.shared.convert(bodyNSFont, toHaveTrait: .boldFontMask) : bodyNSFont
        )
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minWidth: 92, maxWidth: .infinity, alignment: alignment)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHeader ? Color.secondary.opacity(0.10) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.14))
                    .frame(height: 1)
            }
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 1)
            }
    }

    private func alignment(for tableAlignment: AgentMarkdownTableAlignment) -> Alignment {
        switch tableAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func headingFont(_ level: Int) -> Font {
        guard let bodyPointSize else {
            switch level {
            case 1: return AgentChatTypography.title
            case 2: return AgentChatTypography.sectionTitle
            default: return AgentChatTypography.calloutEmphasis
            }
        }

        let systemBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let semanticSize: CGFloat
        switch level {
        case 1: semanticSize = NSFont.preferredFont(forTextStyle: .title3).pointSize
        case 2: semanticSize = NSFont.preferredFont(forTextStyle: .headline).pointSize
        default: semanticSize = NSFont.preferredFont(forTextStyle: .callout).pointSize
        }
        return .system(size: max(10, bodyPointSize + semanticSize - systemBodySize), weight: .semibold)
    }

    private func headingNSFont(_ level: Int) -> NSFont {
        let size: CGFloat
        if let bodyPointSize {
            let systemBodySize = NSFont.preferredFont(forTextStyle: .body).pointSize
            let semanticSize: CGFloat
            switch level {
            case 1: semanticSize = NSFont.preferredFont(forTextStyle: .title3).pointSize
            case 2: semanticSize = NSFont.preferredFont(forTextStyle: .headline).pointSize
            default: semanticSize = NSFont.preferredFont(forTextStyle: .callout).pointSize
            }
            size = max(10, bodyPointSize + semanticSize - systemBodySize)
        } else {
            switch level {
            case 1: size = NSFont.preferredFont(forTextStyle: .title3).pointSize
            case 2: size = NSFont.preferredFont(forTextStyle: .headline).pointSize
            default: size = NSFont.preferredFont(forTextStyle: .callout).pointSize
            }
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    private var secondaryFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.meta }
        return .system(size: max(10, bodyPointSize - 1))
    }

    private var monospacedBodyFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.monoMeta }
        return .system(size: max(10, bodyPointSize - 1), design: .monospaced)
    }

    private var bodyNSFont: NSFont {
        .systemFont(ofSize: bodyPointSize ?? NSFont.preferredFont(forTextStyle: .body).pointSize)
    }

    private var monospacedBodyNSFont: NSFont {
        .monospacedSystemFont(ofSize: bodyPointSize.map { max(10, $0 - 1) } ?? NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
    }

    private var monospacedLabelFont: Font {
        guard let bodyPointSize else { return AgentChatTypography.monoMicro.weight(.semibold) }
        return .system(size: max(9, bodyPointSize - 2), weight: .semibold, design: .monospaced)
    }

    private func renderTableCellInline(_ text: String) -> AttributedString {
        RenderCache.shared.inlineRendered(text)
    }

    @ViewBuilder
    private func inlineText(
        _ attributed: AttributedString,
        font: Font,
        nativeFont: NSFont,
        nativeColor: NSColor = .labelColor,
        strikethrough: Bool = false
    ) -> some View {
        if attributed.runs.contains(where: { $0.link != nil }) {
            AgentMarkdownLinkText(
                attributed: attributed,
                baseFont: nativeFont,
                baseColor: nativeColor,
                strikethrough: strikethrough
            )
        } else {
            Text(attributed).font(font)
        }
    }

}

enum AgentMarkdownImageSourcePolicy {
    enum Source: Equatable {
        case local(URL)
        case remote(URL)
    }

    static func localFileURL(source: String, allowedRoot: URL?) -> URL? {
        guard let allowedRoot,
              let sourceURL = URL(string: source),
              sourceURL.isFileURL else { return nil }
        let root = allowedRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = sourceURL.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else { return nil }
        return candidate
    }

    static func resolvedSource(source: String, allowedRoot: URL?) -> Source? {
        if let local = localFileURL(source: source, allowedRoot: allowedRoot) { return .local(local) }
        guard let remote = remoteImageURL(source: source) else { return nil }
        return .remote(remote)
    }

    /// 远程图片白名单（安全最佳实践）：
    /// - 只允许 https；http 仅放行设备回环（localhost/127.0.0.1/::1），用于本地调试；
    /// - 拒绝 data:、javascript:、file:、ftp: 等其它 scheme；
    /// - 拒绝携带用户名/密码（userinfo）的 URL，避免把凭据发给第三方；
    /// - 必须包含非空主机名。
    static func remoteImageURL(source: String) -> URL? {
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil else { return nil }
        switch scheme {
        case "https":
            return url
        case "http":
            return isLoopbackHost(host) ? url : nil
        default:
            return nil
        }
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return trimmed == "localhost" || trimmed == "127.0.0.1" || trimmed == "::1"
    }
}

/// 远程图片下载与解码安全策略（按最佳实践收紧）：
/// - 无 Cookie、无凭据、无磁盘缓存（ephemeral），不暴露会话身份；
/// - 流式接收并设置字节上限，超限立即取消，避免内存被耗尽；
/// - 校验 Content-Type 与响应状态码；
/// - 解码前用 ImageIO 校验真实图像格式、像素尺寸上限（防解压炸弹）、GIF 帧数上限；
/// - 拒绝远程 SVG（历史上存在解析器风险；本地 SVG 仍可正常显示）。
enum AgentMarkdownRemoteImagePolicy {
    static let maxBytes = 20_000_000
    static let maxPixels = 40_000_000
    static let maxGIFFrames = 40
    static let requestTimeout: TimeInterval = 20
    static let resourceTimeout: TimeInterval = 30

    static func loadData(from url: URL) async -> Data? {
        if let cached = AgentMarkdownRemoteImageCache.shared.data(for: url) { return cached }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let delegate = AgentMarkdownBoundedDataDelegate(limit: maxBytes)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)
        task.resume()
        guard let data = await delegate.result.first(where: { _ in true }) else { return nil }
        guard let validated = validatedImageData(data) else { return nil }
        AgentMarkdownRemoteImageCache.shared.store(validated, for: url)
        return validated
    }

    /// 解码前校验：必须是可被 ImageIO 识别的栅格图像、尺寸在安全范围内、GIF 帧数受限、且不是 SVG。
    static func validatedImageData(_ data: Data) -> Data? {
        guard data.count <= maxBytes else { return nil }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?,
              let utType = UTType(type) else { return nil }
        guard utType.conforms(to: .image), !utType.conforms(to: .svg) else { return nil }
        guard CGImageSourceGetCount(source) <= maxGIFFrames,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0,
              Int64(width) * Int64(height) <= Int64(maxPixels) else { return nil }
        return data
    }
}

private final class AgentMarkdownRemoteImageCache: @unchecked Sendable {
    static let shared = AgentMarkdownRemoteImageCache()
    private let cache = NSCache<NSString, NSData>()

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 120 * 1_024 * 1_024
    }

    func data(for url: URL) -> Data? {
        cache.object(forKey: url.absoluteString as NSString).map { $0 as Data }
    }

    func store(_ data: Data, for url: URL) {
        cache.setObject(data as NSData, forKey: url.absoluteString as NSString, cost: data.count)
    }
}

/// 有界流式下载：超过字节上限立即取消，避免恶意服务器无限下发数据。
private final class AgentMarkdownBoundedDataDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let limit: Int
    private var data = Data()
    let result: AsyncStream<Data>

    init(limit: Int) {
        self.limit = limit
        var continuation: AsyncStream<Data>.Continuation!
        result = AsyncStream<Data> { continuation = $0 }
        self.continuation = continuation
    }

    private let continuation: AsyncStream<Data>.Continuation

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            guard (200..<300).contains(http.statusCode) else {
                continuation.finish()
                completionHandler(.cancel)
                return
            }
            if let mime = http.mimeType?.lowercased(), !mime.hasPrefix("image/") {
                continuation.finish()
                completionHandler(.cancel)
                return
            }
        }
        if response.expectedContentLength > Int64(limit) {
            continuation.finish()
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count + chunk.count <= limit else {
            continuation.finish()
            dataTask.cancel()
            return
        }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error == nil { continuation.yield(data) }
        continuation.finish()
    }
}

private struct AgentMarkdownImageView: View {
    private enum Phase {
        case loading
        case loaded(NSImage)
        case failed
    }

    var altText: String
    var source: String
    var allowedRoot: URL?
    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 160)
            case .loaded(let image):
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 480, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            case .failed:
                Label("图片无法显示", systemImage: "photo.badge.exclamationmark")
                    .font(AgentChatTypography.meta)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
            }
        }
        .accessibilityLabel(altText.isEmpty ? "回复图片" : altText)
        .task(id: source) {
            phase = .loading
            guard let resolved = AgentMarkdownImageSourcePolicy.resolvedSource(source: source, allowedRoot: allowedRoot) else {
                phase = .failed
                return
            }
            let data: Data?
            switch resolved {
            case .local(let url):
                data = await Task.detached(priority: .utility) {
                    guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                          data.count <= AgentMarkdownRemoteImagePolicy.maxBytes else { return nil as Data? }
                    return data
                }.value
            case .remote(let url):
                data = await AgentMarkdownRemoteImagePolicy.loadData(from: url)
            }
            guard !Task.isCancelled, let data, let image = NSImage(data: data) else { return phase = .failed }
            phase = .loaded(image)
        }
    }
}

struct AgentMarkdownLinkText: NSViewRepresentable {
    var attributed: AttributedString
    var baseFont: NSFont
    var baseColor: NSColor
    var strikethrough: Bool

    @Environment(\.openURL) private var openURL

    func makeCoordinator() -> Coordinator {
        Coordinator(openURL: openURL)
    }

    func makeNSView(context: Context) -> LinkTextView {
        let textView = LinkTextView()
        textView.delegate = context.coordinator
        return textView
    }

    func updateNSView(_ textView: LinkTextView, context: Context) {
        context.coordinator.openURL = openURL
        let rendered = Self.renderedAttributedString(
            attributed,
            baseFont: baseFont,
            baseColor: baseColor,
            strikethrough: strikethrough
        )
        if !textView.attributedString().isEqual(to: rendered) {
            textView.textStorage?.setAttributedString(rendered)
            textView.window?.invalidateCursorRects(for: textView)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0,
              let textContainer = nsView.textContainer,
              let layoutManager = nsView.layoutManager else { return nil }
        textContainer.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        let height = ceil(layoutManager.usedRect(for: textContainer).height)
        return CGSize(width: width, height: max(height, baseFont.ascender - baseFont.descender))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var openURL: OpenURLAction

        init(openURL: OpenURLAction) {
            self.openURL = openURL
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            let url: URL?
            switch link {
            case let value as URL: url = value
            case let value as String: url = URL(string: value)
            default: url = nil
            }
            guard let url else { return false }
            openURL(url)
            return true
        }
    }

    final class LinkTextView: NSTextView {
        init() {
            let storage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let container = NSTextContainer(size: .zero)
            storage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(container)
            super.init(frame: .zero, textContainer: container)

            drawsBackground = false
            isEditable = false
            isSelectable = true
            isRichText = true
            isHorizontallyResizable = false
            isVerticallyResizable = true
            textContainerInset = .zero
            container.lineFragmentPadding = 0
            container.lineBreakMode = .byWordWrapping
            container.widthTracksTextView = true
            setContentHuggingPriority(.defaultLow, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            linkTextAttributes = [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }
    }

    static func renderedAttributedString(
        _ attributed: AttributedString,
        baseFont: NSFont,
        baseColor: NSColor,
        strikethrough: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for run in attributed.runs {
            let text = String(attributed[run.range].characters)
            var font = baseFont
            if let intent = run.inlinePresentationIntent {
                var traits: NSFontTraitMask = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
                if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
                if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
                if intent.contains(.code) {
                    font = .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
                }
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: baseColor
            ]
            if let link = run.link {
                attributes[.link] = link
                attributes[.cursor] = NSCursor.pointingHand
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if strikethrough || run.inlinePresentationIntent?.contains(.strikethrough) == true {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            result.append(NSAttributedString(string: text, attributes: attributes))
        }
        addLinksForBareWebAddresses(in: result)
        return result
    }

    private static func addLinksForBareWebAddresses(in result: NSMutableAttributedString) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let fullRange = NSRange(location: 0, length: result.length)
        detector.enumerateMatches(in: result.string, options: [], range: fullRange) { match, _, _ in
            guard let match, let url = match.url, match.range.length > 0 else { return }
            var overlapsExistingLink = false
            result.enumerateAttribute(.link, in: match.range) { value, _, stop in
                if value != nil {
                    overlapsExistingLink = true
                    stop.pointee = true
                }
            }
            guard !overlapsExistingLink else { return }
            result.addAttributes([
                .link: url,
                .cursor: NSCursor.pointingHand,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: match.range)
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// 代码块 / 引用块右上角的复制按钮：复制整段文本，点击后短暂显示“已复制”。
private struct AgentMarkdownBlockCopyButton: View {
    let text: String
    let label: String
    let accessibilityLabel: String
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.6))
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(copied ? Color.green : Color.secondary)
                .padding(4)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(accessibilityLabel)
        .accessibilityLabel(copied ? "已复制" : accessibilityLabel)
        .animation(.easeOut(duration: 0.15), value: copied)
    }
}
