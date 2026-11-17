import Foundation
import Darwin

public enum DownloadFile {
    public static func isTrustedPage(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "tiktok.com" || host.hasSuffix(".tiktok.com")
    }

    public static func isVideoSource(_ url: URL, pageURL: URL?) -> Bool {
        if ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            return url.host != nil && url.user == nil && url.password == nil
        }
        guard url.scheme == "blob", let pageURL, isTrustedPage(pageURL),
              let origin = URL(string: String(url.absoluteString.dropFirst(5))) else { return false }
        return origin.scheme == pageURL.scheme && origin.host == pageURL.host && origin.port == pageURL.port
    }

    public static func validateResponse(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw failure("服务器返回 HTTP \(http.statusCode)，未保存视频")
        }
        let mime = response.mimeType?.lowercased() ?? ""
        let isBlob = response.url?.scheme == "blob"
        guard mime.hasPrefix("video/") || ["application/octet-stream", "application/mp4"].contains(mime)
                || (isBlob && mime.isEmpty) else {
            throw failure("服务器返回的内容不是视频 (\(mime.isEmpty ? "未知类型" : mime))")
        }
    }

    public static func temporaryURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appendingPathComponent(".tokmac-\(UUID().uuidString).part")
    }

    /// Both paths are on the same volume. POSIX rename replaces the destination atomically;
    /// a failed rename leaves the existing file intact.
    public static func commit(_ temporary: URL, to destination: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
        guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
            throw failure("下载的视频为空")
        }
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "TokMac.Download", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
