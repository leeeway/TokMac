import Foundation

public struct SavedVideo: Equatable {
    public let url: URL
    public let id: String
    public let title: String

    public init?(_ value: String) {
        guard let parts = URLComponents(string: value), parts.scheme?.lowercased() == "https",
              let host = parts.host?.lowercased(), (host == "tiktok.com" || host.hasSuffix(".tiktok.com")),
              parts.user == nil, parts.password == nil, (parts.port == nil || parts.port == 443),
              parts.percentEncodedPath.range(of: #"\A/@[A-Za-z0-9._]{1,64}/video/[0-9]{1,32}/?\z"#,
                                             options: .regularExpression) != nil else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/")
        guard let url = URL(string: "https://www.tiktok.com/\(path[0])/video/\(path[2])") else { return nil }
        self.url = url
        id = String(path[2])
        title = "\(path[0]) · \(id)"
    }
}

public struct WatchLaterStore {
    private let file: URL

    public init(file: URL) { self.file = file }

    public func videos() throws -> [SavedVideo] {
        let data: Data
        do { data = try Data(contentsOf: file) }
        catch CocoaError.fileReadNoSuchFile { return [] }
        var seen = Set<String>()
        return try JSONDecoder().decode([String].self, from: data).map { value in
            guard let video = SavedVideo(value) else { throw CocoaError(.fileReadCorruptFile) }
            return video
        }.filter { seen.insert($0.id).inserted }
    }

    @discardableResult
    public func add(_ video: SavedVideo) throws -> Bool {
        var entries = try videos()
        if let current = entries.first(where: { $0.id == video.id }) {
            if current != video {
                entries = entries.map { $0.id == video.id ? video : $0 }
                try write(entries)
            }
            return false
        }
        entries.insert(video, at: 0)
        try write(entries)
        return true
    }

    public func remove(_ video: SavedVideo) throws {
        let entries = try videos()
        let remaining = entries.filter { $0.id != video.id }
        if remaining.count != entries.count { try write(remaining) }
    }

    private func write(_ entries: [SavedVideo]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries.map { $0.url.absoluteString })
        try data.write(to: file, options: .atomic)
    }
}
