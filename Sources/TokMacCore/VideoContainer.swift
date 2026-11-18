import Foundation

enum VideoContainer {
    static func fileExtension(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let length = try file.seekToEnd()
        var reader = Reader(file: file, length: length)
        if let format = try reader.isoFormat() { return format }
        if try reader.isWebM() { return "webm" }
        throw NSError(domain: "TokMac.Download", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "无法识别完整的视频文件（支持 MP4、MOV 和 WebM）"
        ])
    }

    private struct Reader {
        let file: FileHandle
        let length: UInt64
        var budget = 20_000

        func bytes(_ offset: UInt64, _ count: Int) throws -> Data? {
            guard offset <= length, UInt64(count) <= length - offset else { return nil }
            try file.seek(toOffset: offset)
            guard let data = try file.read(upToCount: count), data.count == count else { return nil }
            return data
        }

        func integer(_ offset: UInt64, _ count: Int) throws -> UInt64? {
            try bytes(offset, count)?.reduce(0) { ($0 << 8) | UInt64($1) }
        }

        mutating func box(_ offset: UInt64, end: UInt64) throws -> (type: String, body: Range<UInt64>)? {
            guard budget > 0, end - offset >= 8, let header = try bytes(offset, 8) else { return nil }
            budget -= 1
            let size32 = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let headerLength: UInt64 = size32 == 1 ? 16 : 8
            guard headerLength <= end - offset else { return nil }
            let size = size32 == 1 ? (try integer(offset + 8, 8) ?? 0) : (size32 == 0 ? end - offset : size32)
            guard size >= headerLength, size <= end - offset else { return nil }
            return (String(decoding: header.suffix(4), as: UTF8.self), (offset + headerLength)..<(offset + size))
        }

        mutating func hasVideoTrack(_ range: Range<UInt64>, parents: ArraySlice<String>) throws -> Bool {
            var offset = range.lowerBound
            while offset < range.upperBound {
                guard let element = try box(offset, end: range.upperBound) else { return false }
                if let parent = parents.first {
                    if element.type == parent, try hasVideoTrack(element.body, parents: parents.dropFirst()) { return true }
                } else if element.type == "hdlr", element.body.count >= 12,
                          try bytes(element.body.lowerBound + 8, 4) == Data("vide".utf8) { return true }
                offset = element.body.upperBound
            }
            return false
        }

        mutating func isoFormat() throws -> String? {
            var offset: UInt64 = 0
            var format: String?
            var videoTrack = false
            var mediaData = false
            while offset < length {
                guard let element = try box(offset, end: length) else { return nil }
                switch element.type {
                case "ftyp":
                    guard format == nil, element.body.count >= 8,
                          let brand = try bytes(element.body.lowerBound, 4) else { return nil }
                    switch String(decoding: brand, as: UTF8.self) {
                    case "qt  ": format = "mov"
                    case "isom", "iso2", "iso3", "iso4", "iso5", "iso6", "iso7", "iso8", "iso9",
                         "mp41", "mp42", "avc1", "hvc1", "hev1", "M4V ", "dash", "MSNV": format = "mp4"
                    default: return nil
                    }
                case "moov":
                    videoTrack = try hasVideoTrack(element.body, parents: ["trak", "mdia"][...])
                case "mdat":
                    mediaData = mediaData || !element.body.isEmpty
                default: break
                }
                offset = element.body.upperBound
            }
            return videoTrack && mediaData ? (format ?? "mov") : nil
        }

        func vint(_ offset: UInt64, end: UInt64, isID: Bool) throws -> (value: UInt64, width: UInt64, unknown: Bool)? {
            guard offset < end, let first = try integer(offset, 1), first != 0 else { return nil }
            let width = UInt64(first.leadingZeroBitCount - 55)
            guard width <= (isID ? 4 : 8), width <= end - offset,
                  let encoded = try integer(offset, Int(width)) else { return nil }
            let mask = (UInt64(1) << (7 * width)) - 1
            let value = isID ? encoded : encoded & mask
            return (value, width, !isID && value == mask)
        }

        mutating func element(_ offset: UInt64, end: UInt64) throws -> (id: UInt64, body: Range<UInt64>)? {
            guard budget > 0, let id = try vint(offset, end: end, isID: true),
                  let size = try vint(offset + id.width, end: end, isID: false) else { return nil }
            budget -= 1
            let start = offset + id.width + size.width
            // WebM permits unknown lengths for streaming Segment and Cluster elements.
            guard !size.unknown || id.value == 0x18538067 || id.value == 0x1f43b675 else { return nil }
            let count = size.unknown ? end - start : size.value
            guard count <= end - start else { return nil }
            return (id.value, start..<(start + count))
        }

        mutating func hasWebMVideoTrack(_ range: Range<UInt64>) throws -> Bool {
            var offset = range.lowerBound
            while offset < range.upperBound {
                guard let entry = try element(offset, end: range.upperBound) else { return false }
                if entry.id == 0xae {
                    var fieldOffset = entry.body.lowerBound
                    while fieldOffset < entry.body.upperBound {
                        guard let field = try element(fieldOffset, end: entry.body.upperBound) else { return false }
                        if field.id == 0x83, (1...8).contains(field.body.count),
                           try integer(field.body.lowerBound, field.body.count) == 1 { return true }
                        fieldOffset = field.body.upperBound
                    }
                }
                offset = entry.body.upperBound
            }
            return false
        }

        mutating func isWebM() throws -> Bool {
            guard let header = try element(0, end: length), header.id == 0x1a45dfa3 else { return false }
            var offset = header.body.lowerBound
            var webm = false
            while offset < header.body.upperBound {
                guard let field = try element(offset, end: header.body.upperBound) else { return false }
                if field.id == 0x4282, field.body.count == 4 {
                    webm = try bytes(field.body.lowerBound, 4) == Data("webm".utf8)
                }
                offset = field.body.upperBound
            }
            guard webm, let segment = try element(header.body.upperBound, end: length),
                  segment.id == 0x18538067, segment.body.upperBound == length else { return false }
            offset = segment.body.lowerBound
            var videoTrack = false
            var cluster = false
            while offset < length {
                guard let item = try element(offset, end: length) else { return false }
                if item.id == 0x1654ae6b { videoTrack = try hasWebMVideoTrack(item.body) }
                if item.id == 0x1f43b675 { cluster = cluster || !item.body.isEmpty }
                offset = item.body.upperBound
            }
            return videoTrack && cluster
        }
    }
}
