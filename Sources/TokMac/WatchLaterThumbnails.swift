import Foundation
import ImageIO
import TokMacCore
import UniformTypeIdentifiers

enum WatchLaterThumbnails {
    private static let maxDownloadBytes = 2 * 1024 * 1024
    private static let domains = ["tiktokcdn.com", "tiktokcdn-us.com", "tiktokcdn-eu.com"]
    private static let imageTypes: [UTType] = [.jpeg, .png, .webP]

    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()

    static func allowedURL(_ value: String?) -> URL? {
        guard let value, value.utf8.count <= 4096,
              let url = URL(string: value), url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased(),
              domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }

    static func fetch(_ value: String?) async -> Data? {
        guard let url = allowedURL(value) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("image/jpeg,image/png,image/webp", forHTTPHeaderField: "Accept")
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        do {
            let (bytes, response) = try await session.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= maxDownloadBytes,
                  let mime = http.mimeType, imageTypes.contains(where: { $0.preferredMIMEType == mime }) else { return nil }
            var data = Data()
            for try await byte in bytes {
                guard data.count < maxDownloadBytes else { return nil }
                data.append(byte)
            }
            return makeJPEG(data)
        } catch {
            return nil
        }
    }

    static func makeJPEG(_ data: Data) -> Data? {
        guard data.count <= maxDownloadBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source), imageTypes.contains(where: { $0.identifier == type as String }),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...8192).contains(width), (1...8192).contains(height), width * height <= 16_000_000,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.78
        ] as CFDictionary)
        return CGImageDestinationFinalize(destination) && output.length <= SavedVideo.maxThumbnailBytes ? output as Data : nil
    }
}
