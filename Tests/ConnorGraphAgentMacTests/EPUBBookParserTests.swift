import Foundation
import Testing
@testable import ConnorGraphAgentMac

@Suite("EPUB Book Parser")
struct EPUBBookParserTests {
    @Test("Parses EPUB3 book with nav and cover metadata")
    func parsesEPUB3WithNav() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bookURL = root.appendingPathComponent("book.epub")
        try makeEPUB3(at: bookURL)

        let extraction = EPUBBookParser.extractionDirectory()
        defer { EPUBBookParser.cleanupExtractedDirectoryIfNeeded(path: extraction.path) }
        try EPUBBookParser.extract(fileURL: bookURL, to: extraction)
        let book = try EPUBBookParser.parseBook(at: extraction, defaultTitle: "book")

        #expect(book.title == "示例电子书")
        #expect(book.creator == "康纳")
        #expect(book.coverHref == "OEBPS/images/cover.jpg")
        #expect(book.chapters.map(\.title) == ["第一章 开始", "第二章 继续"])
        #expect(book.chapters.map(\.href) == [
            "OEBPS/text/chapter1.xhtml",
            "OEBPS/text/chapter2.xhtml"
        ])
    }

    @Test("Parses EPUB2 book using NCX table of contents")
    func parsesEPUB2WithNCX() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bookURL = root.appendingPathComponent("book.epub")
        try makeEPUB2(at: bookURL)

        let extraction = EPUBBookParser.extractionDirectory()
        defer { EPUBBookParser.cleanupExtractedDirectoryIfNeeded(path: extraction.path) }
        try EPUBBookParser.extract(fileURL: bookURL, to: extraction)
        let book = try EPUBBookParser.parseBook(at: extraction, defaultTitle: "book")

        #expect(book.title == "旧版电子书")
        #expect(book.chapters.map(\.title) == ["前言", "正文"])
        #expect(book.chapters.map(\.href) == [
            "OEBPS/chapter1.xhtml",
            "OEBPS/chapter2.xhtml"
        ])
    }

    @Test("Generates reader landing page with title and chapter links")
    func generatesLandingPage() throws {
        let book = EPUBBook(
            title: "测试 <书>",
            creator: "作者 & 团队",
            coverHref: "OEBPS/images/cover.jpg",
            chapters: [
                EPUBChapter(href: "OEBPS/ch1.xhtml", title: "第一章"),
                EPUBChapter(href: "OEBPS/ch2.xhtml#s2", title: "第二章")
            ]
        )

        let html = EPUBBookParser.landingPageHTML(for: book)

        #expect(html.contains("测试 &lt;书&gt;"))
        #expect(html.contains("作者 &amp; 团队"))
        #expect(html.contains("src=\"OEBPS/images/cover.jpg\""))
        #expect(html.contains("href=\"OEBPS/ch1.xhtml\""))
        #expect(html.contains("href=\"OEBPS/ch2.xhtml#s2\""))
        #expect(html.contains(">第一章</a>"))
    }

    @Test("Rejects files that are not EPUB archives")
    func rejectsNonEPUB() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = root.appendingPathComponent("fake.epub")
        try "not a zip".write(to: fake, atomically: true, encoding: .utf8)

        let extraction = EPUBBookParser.extractionDirectory()
        defer { EPUBBookParser.cleanupExtractedDirectoryIfNeeded(path: extraction.path) }

        #expect(throws: EPUBBookParserError.self) {
            try EPUBBookParser.extract(fileURL: fake, to: extraction)
        }
    }

    @Test("Cleanup only removes directories created by the parser")
    func cleanupOnlyRemovesParserDirectories() throws {
        let root = try makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        EPUBBookParser.cleanupExtractedDirectoryIfNeeded(path: root.path)
        #expect(FileManager.default.fileExists(atPath: root.path))

        let parserDirectory = EPUBBookParser.extractionDirectory()
        try FileManager.default.createDirectory(at: parserDirectory, withIntermediateDirectories: true)
        EPUBBookParser.cleanupExtractedDirectoryIfNeeded(path: parserDirectory.path)
        #expect(!FileManager.default.fileExists(atPath: parserDirectory.path))
    }

    // MARK: - Fixtures

    private func makeFixtureDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("epub-parser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeEPUB3(at url: URL) throws {
        let files: [(String, String)] = [
            ("mimetype", "application/epub+zip"),
            ("META-INF/container.xml", """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """),
            ("OEBPS/content.opf", """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>示例电子书</dc:title>
                <dc:creator>康纳</dc:creator>
                <dc:language>zh</dc:language>
                <meta name="cover" content="cover-image"/>
              </metadata>
              <manifest>
                <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
                <item id="cover-image" href="images/cover.jpg" media-type="image/jpeg"/>
                <item id="c1" href="text/chapter1.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="text/chapter2.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="c1"/>
                <itemref idref="c2"/>
              </spine>
            </package>
            """),
            ("OEBPS/nav.xhtml", """
            <?xml version="1.0" encoding="UTF-8"?>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
              <head><title>目录</title></head>
              <body>
                <nav epub:type="toc">
                  <ol>
                    <li><a href="text/chapter1.xhtml">第一章 开始</a></li>
                    <li><a href="text/chapter2.xhtml">第二章 继续</a></li>
                  </ol>
                </nav>
              </body>
            </html>
            """),
            ("OEBPS/text/chapter1.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>正文一</p></body></html>"),
            ("OEBPS/text/chapter2.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>正文二</p></body></html>"),
            ("OEBPS/images/cover.jpg", "fake-jpeg-bytes")
        ]
        try writeEPUB(files.map { ($0.0, Data($0.1.utf8)) }, to: url)
    }

    private func makeEPUB2(at url: URL) throws {
        let files: [(String, String)] = [
            ("META-INF/container.xml", """
            <?xml version="1.0" encoding="UTF-8"?>
            <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
              <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
              </rootfiles>
            </container>
            """),
            ("OEBPS/content.opf", """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="2.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>旧版电子书</dc:title>
                <dc:creator>康纳</dc:creator>
              </metadata>
              <manifest>
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
                <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                <item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine toc="ncx">
                <itemref idref="c1"/>
                <itemref idref="c2"/>
              </spine>
            </package>
            """),
            ("OEBPS/toc.ncx", """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <navMap>
                <navPoint id="n1">
                  <navLabel><text>前言</text></navLabel>
                  <content src="chapter1.xhtml"/>
                </navPoint>
                <navPoint id="n2">
                  <navLabel><text>正文</text></navLabel>
                  <content src="chapter2.xhtml"/>
                </navPoint>
              </navMap>
            </ncx>
            """),
            ("OEBPS/chapter1.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>前言</p></body></html>"),
            ("OEBPS/chapter2.xhtml", "<html xmlns=\"http://www.w3.org/1999/xhtml\"><body><p>正文</p></body></html>")
        ]
        try writeEPUB(files.map { ($0.0, Data($0.1.utf8)) }, to: url)
    }

    private func writeEPUB(_ entries: [(String, Data)], to url: URL) throws {
        try TestZIPWriter.write(entries: entries, to: url)
    }
}

// MARK: - 极简 ZIP 写入器（stored，供测试构造 EPUB 夹具）

enum TestZIPWriter {
    static func write(entries: [(String, Data)], to url: URL) throws {
        var localParts: [Data] = []
        var centralParts: [Data] = []
        var offset = 0

        for entry in entries {
            let nameData = Data(entry.0.utf8)
            let crc = crc32(entry.1)
            let size = UInt32(entry.1.count)

            var local = Data()
            appendUInt32(0x04034b50, to: &local)
            appendUInt16(20, to: &local)  // version needed
            appendUInt16(0, to: &local)   // flags
            appendUInt16(0, to: &local)   // method: stored
            appendUInt16(0, to: &local)   // mod time
            appendUInt16(0, to: &local)   // mod date
            appendUInt32(crc, to: &local)
            appendUInt32(size, to: &local)
            appendUInt32(size, to: &local)
            appendUInt16(UInt16(nameData.count), to: &local)
            appendUInt16(0, to: &local)   // extra length
            local.append(nameData)
            local.append(entry.1)

            var central = Data()
            appendUInt32(0x02014b50, to: &central)
            appendUInt16(20, to: &central) // version made by
            appendUInt16(20, to: &central) // version needed
            appendUInt16(0, to: &central)  // flags
            appendUInt16(0, to: &central)  // method
            appendUInt16(0, to: &central)  // mod time
            appendUInt16(0, to: &central)  // mod date
            appendUInt32(crc, to: &central)
            appendUInt32(size, to: &central)
            appendUInt32(size, to: &central)
            appendUInt16(UInt16(nameData.count), to: &central)
            appendUInt16(0, to: &central)  // extra length
            appendUInt16(0, to: &central)  // comment length
            appendUInt16(0, to: &central)  // disk number
            appendUInt16(0, to: &central)  // internal attrs
            appendUInt32(0, to: &central)  // external attrs
            appendUInt32(UInt32(offset), to: &central)
            central.append(nameData)

            localParts.append(local)
            centralParts.append(central)
            offset += local.count
        }

        var archive = Data()
        for part in localParts { archive.append(part) }
        let centralData = centralParts.reduce(into: Data()) { $0.append($1) }
        let centralOffset = archive.count
        archive.append(centralData)

        appendUInt32(0x06054b50, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt16(UInt16(entries.count), to: &archive)
        appendUInt32(UInt32(centralData.count), to: &archive)
        appendUInt32(UInt32(centralOffset), to: &archive)
        appendUInt16(0, to: &archive)

        try archive.write(to: url, options: .atomic)
    }

    private static func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
