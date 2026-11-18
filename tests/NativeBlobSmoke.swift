import Cocoa
import WebKit

// Local-only integration check: no TikTok page or external video is requested.
final class NativeBlobProbe: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    let webView: WKWebView
    var download: WKDownload?
    let videoBytes = try! Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/tiny.mp4"))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    lazy var destination = directory.appendingPathComponent("O'Connor.mp4")
    lazy var temporary = DownloadFile.temporaryURL(for: destination)

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
    }

    func start() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: destination)
        webView.navigationDelegate = self
        webView.loadHTMLString("<html><body>Local Blob test</body></html>", baseURL: URL(string: "https://www.tiktok.com/"))
    }

    func finish(_ code: Int32, message: String) -> Never {
        print(message)
        try? FileManager.default.removeItem(at: directory)
        exit(code)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let base64 = videoBytes.base64EncodedString()
        webView.evaluateJavaScript("URL.createObjectURL(new Blob([Uint8Array.from(atob('\(base64)'), c => c.charCodeAt(0))], {type:'video/mp4'}))") { result, error in
            guard let source = result as? String, let url = URL(string: source) else {
                self.finish(1, message: "Blob creation failed: \(String(describing: error))")
            }
            webView.startDownload(using: URLRequest(url: url)) { download in
                self.download = download
                download.delegate = self
            }
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        do { try DownloadFile.validateResponse(response) }
        catch { finish(2, message: "Blob response rejected: \(error)") }
        completionHandler(temporary)
    }

    func downloadDidFinish(_ download: WKDownload) {
        do {
            guard try String(contentsOf: destination, encoding: .utf8) == "original" else {
                finish(3, message: "Native download modified the original before commit")
            }
            try DownloadFile.commit(temporary, to: destination)
            guard try Data(contentsOf: destination) == videoBytes else {
                finish(4, message: "Native download bytes differ")
            }
            finish(0, message: "Native WebKit Blob streaming and atomic replacement passed.")
        } catch { finish(5, message: "Blob commit failed: \(error)") }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        finish(6, message: "Native Blob download failed: \(error)")
    }
}

@main
struct NativeBlobSmoke {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let probe = NativeBlobProbe()
        try probe.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            probe.finish(7, message: "Native Blob download timed out")
        }
        withExtendedLifetime(probe) { app.run() }
    }
}
