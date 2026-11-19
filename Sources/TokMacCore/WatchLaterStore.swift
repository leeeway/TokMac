import Foundation

public struct SavedVideo: Equatable {
    public static let maxThumbnailBytes = 48 * 1024
    public let url: URL
    public let id: String
    public let author: String
    public let caption: String?
    public let thumbnail: Data?
    public var title: String { caption ?? "视频 \(id)" }
    public var subtitle: String { "\(author) · \(id)" }
    public var needsDetails: Bool { caption == nil || thumbnail == nil }

    public init?(_ value: String, caption: String? = nil, thumbnail: Data? = nil) {
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(), (host == "tiktok.com" || host.hasSuffix(".tiktok.com")),
              parts.user == nil, parts.password == nil, (parts.port == nil || parts.port == 443),
              parts.percentEncodedPath.range(of: #"\A/@[A-Za-z0-9._]{1,64}/video/[0-9]{1,32}/?\z"#,
                                             options: .regularExpression) != nil else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/")
        guard let url = URL(string: "https://www.tiktok.com/\(path[0])/video/\(path[2])") else { return nil }
        self.url = url
        id = String(path[2])
        author = String(path[0])
        let normalized = caption?.prefix(1024).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        self.caption = normalized.flatMap { $0.isEmpty ? nil : String($0.prefix(300)) }
        self.thumbnail = thumbnail.flatMap { !$0.isEmpty && $0.count <= Self.maxThumbnailBytes ? $0 : nil }
    }

    public func matches(_ query: String) -> Bool {
        let searchable = "\(caption ?? "") \(author) \(id)"
        return query.split(whereSeparator: \.isWhitespace).allSatisfy {
            searchable.localizedCaseInsensitiveContains(String($0))
        }
    }

    fileprivate func merging(_ update: SavedVideo) -> SavedVideo {
        SavedVideo(update.url.absoluteString, caption: update.caption ?? caption, thumbnail: update.thumbnail ?? thumbnail)!
    }
}

public struct WatchLaterDetails: Decodable {
    public let url: String
    public let title: String?
    public let thumbnailUrl: String?

    public var video: SavedVideo? { SavedVideo(url, caption: title) }
}

public struct WatchLaterStore {
    private let file: URL
    private struct Record: Codable {
        let url: String
        let title: String?
        let thumbnail: Data?
    }

    public init(file: URL) { self.file = file }

    public func videos() throws -> [SavedVideo] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        let decoder = JSONDecoder()
        let records: [Record]
        if let legacy = try? decoder.decode([String].self, from: data) {
            records = legacy.map { Record(url: $0, title: nil, thumbnail: nil) }
        } else {
            records = try decoder.decode([Record].self, from: data)
        }
        var seen = Set<String>()
        return try records.map { record in
            guard let video = SavedVideo(record.url, caption: record.title, thumbnail: record.thumbnail)
            else { throw CocoaError(.fileReadCorruptFile) }
            return video
        }.filter { seen.insert($0.id).inserted }
    }

    @discardableResult
    public func add(_ video: SavedVideo) throws -> Bool {
        var entries = try videos()
        if let index = entries.firstIndex(where: { $0.id == video.id }) {
            try update(video, at: index, in: &entries)
            return false
        }
        entries.insert(video, at: 0)
        try write(entries)
        return true
    }

    public func refresh(_ video: SavedVideo) throws {
        var entries = try videos()
        guard let index = entries.firstIndex(where: { $0.id == video.id }) else { return }
        try update(video, at: index, in: &entries)
    }

    public func refreshThumbnail(for id: String, data: Data) throws {
        var entries = try videos()
        guard let index = entries.firstIndex(where: { $0.id == id }),
              let update = SavedVideo(entries[index].url.absoluteString, thumbnail: data) else { return }
        try self.update(update, at: index, in: &entries)
    }

    public func remove(_ video: SavedVideo) throws {
        let entries = try videos()
        let remaining = entries.filter { $0.id != video.id }
        if remaining.count != entries.count { try write(remaining) }
    }

    private func update(_ video: SavedVideo, at index: Int, in entries: inout [SavedVideo]) throws {
        let merged = entries[index].merging(video)
        guard merged != entries[index] else { return }
        entries[index] = merged
        try write(entries)
    }

    private func write(_ entries: [SavedVideo]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries.map {
            Record(url: $0.url.absoluteString, title: $0.caption, thumbnail: $0.thumbnail)
        })
        try data.write(to: file, options: .atomic)
    }
}
