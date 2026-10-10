import Foundation

/// Office 97–2003 binary text reader. Reads named CFB streams, never scans arbitrary bytes.
/// MS-CFB, MS-DOC §2.4.1, MS-XLS BIFF8, MS-PPT persist object directory.
public enum LegacyOfficeText {
    public static func supports(_ ext: String) -> Bool { ["doc", "xls", "ppt"].contains(ext.lowercased()) }
    public static func extract(_ data: Data, fileExtension: String) throws -> String {
        guard data.count <= 50_000_000 else { throw LegacyOfficeError.invalid("文件超过解析大小限制") }
        let compound = try CompoundOfficeFile(Array(data))
        if compound.names.contains("EncryptedPackage") || compound.names.contains("EncryptionInfo") {
            throw LegacyOfficeError.invalid("加密 Office 文件需要先解除密码保护")
        }
        let text: String
        switch fileExtension.lowercased() {
        case "doc": text = try word(compound)
        case "xls": text = try excel(compound)
        case "ppt": text = try powerpoint(compound)
        default: throw LegacyOfficeError.invalid("不是旧版 Office 文件")
        }
        return clean(text)
    }

    private static func word(_ c: CompoundOfficeFile) throws -> String {
        let w = try c.stream("WordDocument")
        guard try w.u16(0) == 0xa5ec, try w.u16(2) >= 0xc1 else { throw LegacyOfficeError.invalid("不支持此 Word 二进制版本") }
        let flags = try w.u16(10)
        guard flags & 0x8100 == 0 else { throw LegacyOfficeError.invalid("加密 Word 文件需要先解除密码保护") }
        let table = try c.stream(flags & 0x200 != 0 ? "1Table" : "0Table")
        let lw = 34 + (try w.u16(32)) * 2
        let pairs = lw + 2 + (try w.u16(lw)) * 4
        guard try w.u16(pairs) > 33 else { throw LegacyOfficeError.invalid("Word 缺少文字片段表") }
        let fc = try w.u32(pairs + 2 + 33 * 8), size = try w.u32(pairs + 6 + 33 * 8)
        let clx = try table.slice(fc, size)
        var pos = 0
        while try clx.u8(pos) == 1 { pos += 3 + (try clx.u16(pos + 1)) }
        guard try clx.u8(pos) == 2 else { throw LegacyOfficeError.invalid("Word 文字片段表损坏") }
        let plc = try clx.slice(pos + 5, clx.u32(pos + 1))
        guard plc.count >= 4, (plc.count - 4) % 12 == 0 else { throw LegacyOfficeError.invalid("Word 文字片段表长度错误") }
        let count = (plc.count - 4) / 12, bodyCount = try w.u32(lw + 14)
        var output = ""
        for i in 0..<count {
            let start = try plc.u32(i * 4), end = try plc.u32((i + 1) * 4)
            guard end >= start else { throw LegacyOfficeError.invalid("Word 文字位置错误") }
            if start >= bodyCount { break }
            let length = min(end, bodyCount) - start
            let raw = try plc.u32((count + 1) * 4 + i * 8 + 2)
            let compressed = raw & 0x40000000 != 0
            let offset = (raw & 0x3fffffff) / (compressed ? 2 : 1)
            output += try decode(w.slice(offset, length * (compressed ? 1 : 2)), wide: !compressed, ansi: compressed)
        }
        // Field instructions are not visible document text; keep their displayed result.
        var fields: [Bool] = [], visible = ""
        for scalar in output.unicodeScalars {
            switch scalar.value {
            case 0x13: fields.append(false)
            case 0x14: if !fields.isEmpty { fields[fields.count - 1] = true }
            case 0x15: if !fields.isEmpty { fields.removeLast() }
            default: if !fields.contains(false) { visible.unicodeScalars.append(scalar) }
            }
        }
        return visible
    }

    private struct Record { let id: Int; let offset: Int; let bytes: [UInt8] }
    private static func records(_ bytes: [UInt8]) throws -> [Record] {
        var result: [Record] = [], p = 0
        while p < bytes.count {
            let id = try bytes.u16(p), size = try bytes.u16(p + 2)
            result.append(Record(id: id, offset: p, bytes: try bytes.slice(p + 4, size)))
            p += 4 + size
            guard result.count <= 1_000_000 else { throw LegacyOfficeError.invalid("Excel 记录过多") }
        }
        return result
    }
    private static func excel(_ c: CompoundOfficeFile) throws -> String {
        let bytes = try c.stream(c.names.contains("Workbook") ? "Workbook" : "Book")
        let all = try records(bytes)
        guard let first = all.first, first.id == 0x809, try first.bytes.u16(0) == 0x600 else {
            throw LegacyOfficeError.invalid("不支持此 Excel 二进制版本（需要 BIFF8）")
        }
        guard !all.contains(where: { $0.id == 0x2f }) else { throw LegacyOfficeError.invalid("加密 Excel 文件需要先解除密码保护") }
        var strings: [String] = []
        if let i = all.firstIndex(where: { $0.id == 0xfc }) {
            var chunks = [all[i].bytes], j = i + 1
            while j < all.count && all[j].id == 0x3c { chunks.append(all[j].bytes); j += 1 }
            var cursor = BiffStringCursor(chunks)
            _ = try cursor.number(4)
            let count = try cursor.number(4)
            guard count <= 1_000_000 else { throw LegacyOfficeError.invalid("Excel 字符串过多") }
            for _ in 0..<count { strings.append(try cursor.string()) }
        }
        var output: [String] = []
        for sheet in all where sheet.id == 0x85 {
            let b = sheet.bytes
            guard try b.u8(5) == 0 else { continue } // worksheet, not a macro sheet
            let start = try b.u32(0), length = try b.u8(6)
            let name = try decode(b.slice(8, length * (b.u8(7) & 1 != 0 ? 2 : 1)), wide: b.u8(7) & 1 != 0)
            guard let index = all.firstIndex(where: { $0.offset == start }) else { throw LegacyOfficeError.invalid("Excel 工作表位置错误") }
            output.append("## \(name)")
            for record in all.dropFirst(index + 1) {
                if record.id == 0xa { break }
                let d = record.bytes
                if [0x203, 0x27e, 0xfd, 0x205, 0x6, 0x204].contains(record.id) {
                    let row = try d.u16(0), col = try d.u16(2)
                    let value: String
                    switch record.id {
                    case 0xfd:
                        let i = try d.u32(6)
                        guard strings.indices.contains(i) else { throw LegacyOfficeError.invalid("Excel 共享字符串索引错误") }
                        value = strings[i]
                    case 0x203: value = String(try d.double(6))
                    case 0x27e: value = String(try rk(d.u32(6)))
                    case 0x205: value = try d.u8(7) == 0 ? (d.u8(6) == 0 ? "FALSE" : "TRUE") : "#ERROR(\(d.u8(6)))"
                    case 0x204: var cursor = BiffStringCursor([try d.slice(6, d.count - 6)]); value = try cursor.string()
                    default:
                        if try d.u16(12) == 0xffff {
                            let type = try d.u8(6)
                            if type == 0, let next = all.first(where: { $0.offset == record.offset + 4 + d.count }), next.id == 0x207 {
                                var cursor = BiffStringCursor([next.bytes]); value = try cursor.string()
                            } else { value = type == 1 ? (try d.u8(8) == 0 ? "FALSE" : "TRUE") : "" }
                        } else { value = String(try d.double(6)) }
                    }
                    output.append("\(column(col))\(row + 1)=\(value)")
                } else if record.id == 0xbd {
                    let row = try d.u16(0), firstCol = try d.u16(2), lastCol = try d.u16(d.count - 2)
                    guard lastCol >= firstCol, d.count == 6 + (lastCol - firstCol + 1) * 6 else { throw LegacyOfficeError.invalid("Excel MULRK 记录错误") }
                    for col in firstCol...lastCol { output.append("\(column(col))\(row + 1)=\(try rk(d.u32(6 + (col - firstCol) * 6)))") }
                }
            }
        }
        return output.joined(separator: "\n")
    }
    private static func rk(_ raw: Int) -> Double {
        let value = raw & 2 != 0 ? Double(Int32(bitPattern: UInt32(raw)) >> 2) : Double(bitPattern: UInt64(raw & 0xfffffffc) << 32)
        return raw & 1 != 0 ? value / 100 : value
    }
    private static func column(_ index: Int) -> String {
        var n = index + 1, s = ""
        while n > 0 { n -= 1; s = String(UnicodeScalar(65 + n % 26)!) + s; n /= 26 }
        return s
    }

    private static func powerpoint(_ c: CompoundOfficeFile) throws -> String {
        let user = try c.stream("Current User"), bytes = try c.stream("PowerPoint Document")
        guard try user.u32(12) == 0xe391c05f else { throw LegacyOfficeError.invalid("加密或不支持的 PowerPoint 文件") }
        var edit = try user.u32(16), seen: Set<Int> = [], persist: [Int: Int] = [:], documentID = 0
        while edit != 0 {
            guard seen.insert(edit).inserted, seen.count <= 4096, try bytes.u16(edit + 2) == 4085 else { throw LegacyOfficeError.invalid("PPT 编辑链损坏") }
            let length = try bytes.u32(edit + 4)
            guard length == 28 else { throw LegacyOfficeError.invalid("加密或不支持的 PPT 编辑记录") }
            if documentID == 0 { documentID = try bytes.u32(edit + 24) }
            let directory = try bytes.u32(edit + 20)
            guard try bytes.u16(directory + 2) == 6002 else { throw LegacyOfficeError.invalid("PPT 对象目录错误") }
            let end = directory + 8 + (try bytes.u32(directory + 4))
            var p = directory + 8
            while p < end {
                let packed = try bytes.u32(p), start = packed & 0xfffff, count = packed >> 20
                guard count > 0, p + 4 + count * 4 <= end else { throw LegacyOfficeError.invalid("PPT 对象目录损坏") }
                for i in 0..<count { if persist[start + i] == nil { persist[start + i] = try bytes.u32(p + 4 + i * 4) } }
                p += 4 + count * 4
            }
            edit = try bytes.u32(edit + 16)
        }
        guard let doc = persist[documentID] else { throw LegacyOfficeError.invalid("PPT 缺少当前文档") }
        var text: [String] = [], references: [Int] = [], visited: Set<Int> = []
        func walk(_ offset: Int, _ end: Int, _ depth: Int) throws {
            guard depth < 64, end <= bytes.count else { throw LegacyOfficeError.invalid("PPT 容器越界") }
            var p = offset
            while p < end {
                guard p + 8 <= end else { throw LegacyOfficeError.invalid("PPT 记录损坏") }
                let flags = try bytes.u16(p), type = try bytes.u16(p + 2), size = try bytes.u32(p + 4), next = p + 8 + size
                guard next <= end else { throw LegacyOfficeError.invalid("PPT 记录越界") }
                if flags & 15 == 15 {
                    if !(type == 4080 && flags >> 4 == 1) { try walk(p + 8, next, depth + 1) }
                } else if type == 4000 || type == 4008 {
                    text.append(try decode(bytes.slice(p + 8, size), wide: type == 4000, ansi: type == 4008))
                } else if type == 1011 { references.append(try bytes.u32(p + 8)) }
                p = next
            }
        }
        try walk(doc, doc + 8 + bytes.u32(doc + 4), 0)
        var i = 0
        while i < references.count {
            let id = references[i]; i += 1
            if visited.insert(id).inserted {
                guard let offset = persist[id] else { throw LegacyOfficeError.invalid("PPT 缺少引用对象") }
                try walk(offset, offset + 8 + bytes.u32(offset + 4), 0)
            }
        }
        return text.joined(separator: "\n")
    }
    fileprivate static func decode(_ bytes: [UInt8], wide: Bool, ansi: Bool = false) throws -> String {
        if wide {
            guard bytes.count % 2 == 0 else { throw LegacyOfficeError.invalid("Unicode 字符串损坏") }
            return String(decoding: stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }, as: UTF16.self)
        }
        if ansi, let value = String(data: Data(bytes), encoding: .windowsCP1252) { return value }
        return String(String.UnicodeScalarView(bytes.map { UnicodeScalar(UInt32($0))! }))
    }
    private static func clean(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.compactMap { scalar in
            if [7, 9].contains(scalar.value) { return UnicodeScalar(9) }
            if [10, 11, 12, 13].contains(scalar.value) { return UnicodeScalar(10) }
            return scalar.value >= 32 ? scalar : nil
        })).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum LegacyOfficeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let value) = self { return value }; return nil }
}
private extension Array where Element == UInt8 {
    func slice(_ offset: Int, _ length: Int) throws -> [UInt8] {
        guard offset >= 0, length >= 0, offset <= count, length <= count - offset else { throw LegacyOfficeError.invalid("Office 二进制数据越界") }
        return Array(self[offset..<offset + length])
    }
    func u8(_ offset: Int) throws -> Int { Int(try slice(offset, 1)[0]) }
    func u16(_ offset: Int) throws -> Int { let b = try slice(offset, 2); return Int(b[0]) | Int(b[1]) << 8 }
    func u32(_ offset: Int) throws -> Int { let b = try slice(offset, 4); return b.enumerated().reduce(0) { $0 | Int($1.element) << ($1.offset * 8) } }
    func double(_ offset: Int) throws -> Double { let b = try slice(offset, 8); return Double(bitPattern: b.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << ($1.offset * 8) }) }
}
private struct BiffStringCursor {
    let chunks: [[UInt8]]
    var chunk = 0, offset = 0
    init(_ chunks: [[UInt8]]) { self.chunks = chunks }
    mutating func byte() throws -> Int {
        while chunk < chunks.count && offset == chunks[chunk].count { chunk += 1; offset = 0 }
        guard chunk < chunks.count else { throw LegacyOfficeError.invalid("Excel 字符串截断") }
        defer { offset += 1 }; return Int(chunks[chunk][offset])
    }
    mutating func number(_ size: Int) throws -> Int { var n = 0; for i in 0..<size { n |= try byte() << (i * 8) }; return n }
    mutating func string() throws -> String {
        let count = try number(2), flags = try byte()
        let runs = flags & 8 != 0 ? try number(2) : 0, extra = flags & 4 != 0 ? try number(4) : 0
        guard extra <= 8_000_000 else { throw LegacyOfficeError.invalid("Excel 扩展字符串过大") }
        var wide = flags & 1 != 0, units: [UInt16] = []
        for _ in 0..<count {
            if chunk < chunks.count && offset == chunks[chunk].count { chunk += 1; offset = 0; wide = try byte() & 1 != 0 }
            let low = try byte(), high = wide ? try byte() : 0
            units.append(UInt16(low | high << 8))
        }
        for _ in 0..<(runs * 4 + extra) { _ = try byte() }
        return String(decoding: units, as: UTF16.self)
    }
}
private struct CompoundOfficeFile {
    let bytes: [UInt8], sectorSize: Int, fat: [Int], directory: [UInt8], miniFat: [Int], miniStream: [UInt8]
    let entries: [String: Int]
    var names: Set<String> { Set(entries.keys) }
    init(_ bytes: [UInt8]) throws {
        guard Array(bytes.prefix(8)) == [0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1], try bytes.u16(28) == 0xfffe,
              [9,12].contains(try bytes.u16(30)), try bytes.u16(32) == 6, try bytes.u32(56) == 4096 else { throw LegacyOfficeError.invalid("不是有效的 Office 复合文件") }
        let sectorSize = 1 << (try bytes.u16(30))
        func sector(_ id: Int) throws -> [UInt8] { try bytes.slice((id + 1) * sectorSize, sectorSize) }
        var ids: [Int] = [], next = try bytes.u32(68), visited: Set<Int> = []
        for i in 0..<109 { let id = try bytes.u32(76 + i * 4); if id != 0xffffffff { ids.append(id) } }
        let difCount = try bytes.u32(72)
        guard difCount <= bytes.count / sectorSize else { throw LegacyOfficeError.invalid("Office DIFAT 过大") }
        for _ in 0..<difCount {
            guard visited.insert(next).inserted else { throw LegacyOfficeError.invalid("Office DIFAT 循环") }
            let b = try sector(next)
            for i in 0..<(sectorSize / 4 - 1) { let id = try b.u32(i * 4); if id != 0xffffffff { ids.append(id) } }
            next = try b.u32(sectorSize - 4)
        }
        guard ids.count == (try bytes.u32(44)), ids.count <= bytes.count / sectorSize else { throw LegacyOfficeError.invalid("Office FAT 数量错误") }
        var fat: [Int] = []
        for id in ids { let b = try sector(id); for i in stride(from: 0, to: b.count, by: 4) { fat.append(try b.u32(i)) } }
        let directory = try Self.chain(try bytes.u32(48), fat, sectorSize, bytes, sectorSize)
        guard directory.count >= 128, try directory.u8(66) == 5 else { throw LegacyOfficeError.invalid("Office 根目录错误") }
        let mini = try Self.chain(try directory.u32(116), fat, sectorSize, bytes, sectorSize)
        let miniSize = try directory.u32(120)
        guard try directory.u32(124) == 0, miniSize <= mini.count else { throw LegacyOfficeError.invalid("Office mini stream 长度错误") }
        let mf = try Self.chain(try bytes.u32(60), fat, sectorSize, bytes, sectorSize)
        var miniFat: [Int] = []
        for i in stride(from: 0, to: mf.count, by: 4) { miniFat.append(try mf.u32(i)) }
        var entries: [String: Int] = [:], walked: Set<Int> = []
        func visit(_ id: Int, _ depth: Int) throws {
            if id == 0xffffffff { return }
            guard depth < 128, id > 0, id < directory.count / 128, walked.insert(id).inserted else { throw LegacyOfficeError.invalid("Office 目录树损坏") }
            let p = id * 128, length = try directory.u16(p + 64)
            guard length >= 2, length <= 64, length % 2 == 0 else { throw LegacyOfficeError.invalid("Office 流名称错误") }
            try visit(directory.u32(p + 68), depth + 1)
            if try directory.u8(p + 66) == 2 {
                let name = try LegacyOfficeText.decode(directory.slice(p, length - 2), wide: true)
                guard entries[name] == nil else { throw LegacyOfficeError.invalid("Office 重复流名称") }
                entries[name] = p
            }
            try visit(directory.u32(p + 72), depth + 1)
        }
        try visit(directory.u32(76), 0)
        self.bytes = bytes; self.sectorSize = sectorSize; self.fat = fat; self.directory = directory
        self.miniFat = miniFat; self.miniStream = Array(mini.prefix(miniSize)); self.entries = entries
    }
    func stream(_ name: String) throws -> [UInt8] {
        guard let p = entries[name] else { throw LegacyOfficeError.invalid("Office 缺少 \(name) 流") }
        let size = try directory.u32(p + 120)
        guard try directory.u32(p + 124) == 0, size <= 50_000_000 else { throw LegacyOfficeError.invalid("Office 流过大") }
        if size == 0 { return [] }
        let output = size < 4096
            ? try Self.chain(directory.u32(p + 116), miniFat, 64, miniStream, 0)
            : try Self.chain(directory.u32(p + 116), fat, sectorSize, bytes, sectorSize)
        guard size <= output.count else { throw LegacyOfficeError.invalid("Office 流截断") }
        return Array(output.prefix(size))
    }
    private static func chain(_ start: Int, _ table: [Int], _ size: Int, _ bytes: [UInt8], _ base: Int) throws -> [UInt8] {
        var id = start, seen: Set<Int> = [], result: [UInt8] = []
        while id != 0xfffffffe {
            guard table.indices.contains(id), seen.insert(id).inserted, result.count <= 50_000_000 - size else { throw LegacyOfficeError.invalid("Office 扇区链损坏或循环") }
            result += try bytes.slice(base + id * size, size); id = table[id]
        }
        return result
    }
}
