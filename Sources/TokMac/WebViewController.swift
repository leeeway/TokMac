import Cocoa
import WebKit
import UserNotifications

protocol WebViewControllerDelegate: AnyObject {
    func webViewController(_ controller: WebViewController, didChangeCommentState isOpen: Bool)
}

final class WebViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, WKDownloadDelegate {
    private(set) var webView: WKWebView!
    private var progressIndicator: NSProgressIndicator!
    private var popupWindows: [NSWindow] = []

    weak var delegate: WebViewControllerDelegate?

    var isCompactMode: Bool = true {
        didSet {
            updateCompactModeState()
        }
    }

    var isCleanMode: Bool = true {
        didSet {
            updateCleanModeState()
        }
    }

    var isAutoNextEnabled: Bool = false {
        didSet {
            updateAutoNextState()
        }
    }

    override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 490, height: 820))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        self.view = view

        setupWebView()
        setupProgressBar()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadTikTok()
    }

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        // Ensure cookies and credentials persist across app restarts
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        let userContent = config.userContentController
        userContent.add(self, name: "tokmac")

        // Inject script to handle shortcuts, comment detection & clean layout
        let navScript = WKUserScript(
            source: InjectedScripts.keyboardAndNavigationJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(navScript)

        let cssScript = WKUserScript(
            source: """
            const style = document.createElement('style');
            style.id = '__tokmac_clean_style';
            style.textContent = `\(InjectedScripts.cleanModeCSS)`;
            document.head.appendChild(style);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        userContent.addUserScript(cssScript)

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self

        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        // Standard modern Safari Desktop User-Agent for seamless login & video streaming
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        webView.setValue(false, forKey: "drawsBackground")
        view.addSubview(webView)
    }

    private func setupProgressBar() {
        progressIndicator = NSProgressIndicator()
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0.0
        progressIndicator.maxValue = 1.0
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(progressIndicator)
        NSLayoutConstraint.activate([
            progressIndicator.topAnchor.constraint(equalTo: view.topAnchor),
            progressIndicator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressIndicator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressIndicator.heightAnchor.constraint(equalToConstant: 2.5)
        ])

        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(WKWebView.estimatedProgress) {
            progressIndicator.doubleValue = webView.estimatedProgress
            if webView.estimatedProgress >= 1.0 {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    progressIndicator.animator().alphaValue = 0.0
                } completionHandler: {
                    self.progressIndicator.stopAnimation(nil)
                    self.progressIndicator.alphaValue = 1.0
                }
            } else {
                progressIndicator.alphaValue = 1.0
                progressIndicator.startAnimation(nil)
            }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func loadTikTok() {
        if let url = URL(string: "https://www.tiktok.com/") {
            let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
            webView.load(request)
        }
    }

    func updateCompactModeState() {
        let js = "document.body && document.body.classList.toggle('tokmac-compact', \(isCompactMode));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func updateCleanModeState() {
        let js = """
        const el = document.getElementById('__tokmac_clean_style');
        if (el) {
            el.disabled = \(!isCleanMode);
        }
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func updateAutoNextState() {
        let js = "window.tokmacSetAutoNext && window.tokmacSetAutoNext(\(isAutoNextEnabled));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Actions
    func nextVideo() {
        webView.evaluateJavaScript("window.tokmacNextVideo && window.tokmacNextVideo();", completionHandler: nil)
    }

    func prevVideo() {
        webView.evaluateJavaScript("window.tokmacPrevVideo && window.tokmacPrevVideo();", completionHandler: nil)
    }

    func togglePlay() {
        webView.evaluateJavaScript("window.tokmacTogglePlay && window.tokmacTogglePlay();", completionHandler: nil)
    }

    func toggleMute() {
        webView.evaluateJavaScript("window.tokmacToggleMute && window.tokmacToggleMute();", completionHandler: nil)
    }

    func toggleComments() {
        webView.evaluateJavaScript("window.tokmacToggleComments && window.tokmacToggleComments();", completionHandler: nil)
    }

    func reloadPage() {
        webView.reload()
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func goForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    // MARK: - Video Downloading
    func downloadCurrentVideo() {
        webView.evaluateJavaScript("window.tokmacGetVideoDownloadInfo && window.tokmacGetVideoDownloadInfo();") { [weak self] result, error in
            guard let self = self else { return }
            guard let dict = result as? [String: Any],
                  let urlString = dict["url"] as? String,
                  let videoURL = URL(string: urlString) else {
                self.showNotification(title: "未检测到可下载视频", body: "请先播放一个视频后再点击下载")
                NSSound.beep()
                return
            }

            let author = (dict["author"] as? String)?.replacingOccurrences(of: "/", with: "_") ?? "TikTok"
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "\(author)_\(timestamp).mp4"

            self.performDirectDownload(from: videoURL, suggestedFilename: filename)
        }
    }

    private func performDirectDownload(from url: URL, suggestedFilename: String) {
        showNotification(title: "开始下载视频...", body: suggestedFilename)

        var request = URLRequest(url: url)
        request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
        request.setValue(webView.customUserAgent, forHTTPHeaderField: "User-Agent")

        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let destinationURL = downloadsDir.appendingPathComponent(suggestedFilename)

        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.showNotification(title: "下载失败", body: error.localizedDescription)
                    NSSound.beep()
                }
                return
            }

            guard let tempURL = tempURL else { return }

            do {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.moveItem(at: tempURL, to: destinationURL)

                DispatchQueue.main.async {
                    NSSound(named: "Glass")?.play()
                    self.showDownloadCompletedAlert(fileURL: destinationURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showNotification(title: "文件保存失败", body: error.localizedDescription)
                }
            }
        }
        task.resume()
    }

    private func showDownloadCompletedAlert(fileURL: URL) {
        let alert = NSAlert()
        alert.messageText = "视频下载完成！"
        alert.informativeText = "文件已保存至：\n\(fileURL.path)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "在 Finder 中显示")
        alert.addButton(withTitle: "好")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        }
    }

    private func showNotification(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "tokmac", let body = message.body as? [String: Any] else { return }

        if let type = body["type"] as? String {
            switch type {
            case "commentPanelStateChanged":
                let isOpen = body["isOpen"] as? Bool ?? false
                delegate?.webViewController(self, didChangeCommentState: isOpen)
            default:
                break
            }
        }
    }

    // MARK: - WKNavigationDelegate (Downloads & Navigation)
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateCompactModeState()
        updateCleanModeState()
        updateAutoNextState()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        var destination = downloadsDir.appendingPathComponent(suggestedFilename)
        if FileManager.default.fileExists(atPath: destination.path) {
            let name = (suggestedFilename as NSString).deletingPathExtension
            let ext = (suggestedFilename as NSString).pathExtension
            destination = downloadsDir.appendingPathComponent("\(name)_\(Int(Date().timeIntervalSince1970)).\(ext)")
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        NSSound(named: "Glass")?.play()
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        showDownloadCompletedAlert(fileURL: downloadsDir)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        showNotification(title: "下载遇到问题", body: error.localizedDescription)
    }

    // MARK: - WKUIDelegate (OAuth Popup Support)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let popupRect = NSRect(
            x: (windowFeatures.x?.doubleValue).map { CGFloat($0) } ?? 200,
            y: (windowFeatures.y?.doubleValue).map { CGFloat($0) } ?? 200,
            width: (windowFeatures.width?.doubleValue).map { CGFloat($0) } ?? 520,
            height: (windowFeatures.height?.doubleValue).map { CGFloat($0) } ?? 640
        )

        let popupWindow = NSWindow(
            contentRect: popupRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        popupWindow.title = "TokMac - 登录"
        popupWindow.center()

        let popupWebView = WKWebView(frame: popupWindow.contentView!.bounds, configuration: configuration)
        popupWebView.autoresizingMask = [.width, .height]
        popupWebView.uiDelegate = self
        popupWebView.customUserAgent = webView.customUserAgent

        popupWindow.contentView?.addSubview(popupWebView)
        popupWindow.makeKeyAndOrderFront(nil)
        popupWindows.append(popupWindow)

        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let window = webView.window, let index = popupWindows.firstIndex(of: window) {
            window.close()
            popupWindows.remove(at: index)
        }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}
