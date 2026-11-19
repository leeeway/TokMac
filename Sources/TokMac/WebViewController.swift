import Cocoa
import WebKit
import UniformTypeIdentifiers
import TokMacCore

protocol WebViewControllerDelegate: AnyObject {
    func webViewController(_ controller: WebViewController, didChangeDetailState isOpen: Bool)
}

final class WebViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private(set) var webView: TokWebView!
    private var progressIndicator: NSProgressIndicator!
    private let popupWindows = PopupWindowStore()
    private var downloadHUD: DownloadHUDView?
    // All download state is owned by the main thread (WebKit delegate callbacks).
    private var downloadID: UUID?
    private var activeDownload: WKDownload?
    private var destinationURL: URL?
    private var temporaryURL: URL?
    private var progressObservation: NSKeyValueObservation?
    private var isCommittingDownload = false
    private var lastProcessRecovery: TimeInterval?

    weak var delegate: WebViewControllerDelegate?

    var isCompactMode: Bool = false {
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
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1080, height: 760))
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
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true

        let userContent = config.userContentController

        let navScript = WKUserScript(
            source: InjectedScripts.keyboardAndNavigationJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        userContent.addUserScript(navScript)

        webView = TokWebView(frame: view.bounds, configuration: config)
        webView.controller = self
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self

        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

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

    func loadForYou() {
        if let url = URL(string: "https://www.tiktok.com/foryou") {
            webView.load(URLRequest(url: url))
        }
    }

    func loadFollowing() {
        if let url = URL(string: "https://www.tiktok.com/following") {
            webView.load(URLRequest(url: url))
        }
    }

    func loadExplore() {
        if let url = URL(string: "https://www.tiktok.com/explore") {
            webView.load(URLRequest(url: url))
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

    func copyCurrentVideoLink() {
        currentVideo { [weak self] video in
            guard let self, let video else { return }
            NSPasteboard.general.clearContents()
            let copied = NSPasteboard.general.setString(video.url.absoluteString, forType: .string)
            self.showNotification(title: copied ? "已复制视频链接" : "无法复制视频链接", body: video.title)
        }
    }

    func copyPageLink() {
        if let urlString = webView.url?.absoluteString {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(urlString, forType: .string)
            showNotification(title: "链接已复制", body: urlString)
        }
    }

    func currentVideo(_ completion: @escaping (SavedVideo?) -> Void) {
        guard let page = webView.url, DownloadFile.isTrustedPage(page) else {
            showNotification(title: "没有可用的当前视频", body: "请先打开 TikTok 视频")
            completion(nil)
            return
        }
        webView.evaluateJavaScript("window.tokmacCurrentVideoLink?.() ?? null") { [weak self] result, _ in
            guard let self else { return }
            let video = self.webView.url == page ? (result as? String).flatMap(SavedVideo.init) : nil
            if video == nil {
                self.showNotification(title: "找不到当前视频链接", body: "试试打开视频详情页")
            }
            completion(video)
        }
    }

    func openSavedVideo(_ video: SavedVideo) {
        webView.load(URLRequest(url: video.url))
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

    // MARK: - Video Downloading (Direct HTTP & Blob support with HUD & Progress)
    private func showDownloadHUD() -> DownloadHUDView {
        if let existing = downloadHUD, existing.canReuse {
            return existing
        }
        let hud = DownloadHUDView()
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hud.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            hud.widthAnchor.constraint(equalToConstant: 380),
            hud.heightAnchor.constraint(equalToConstant: 68)
        ])
        downloadHUD = hud
        return hud
    }

    func downloadCurrentVideo() {
        guard downloadID == nil, DownloadFile.isTrustedPage(webView.url) else { NSSound.beep(); return }
        let id = UUID()
        downloadID = id
        let pageURL = webView.url
        webView.evaluateJavaScript("window.tokmacGetVideoDownloadInfo && window.tokmacGetVideoDownloadInfo();") { [weak self] result, error in
            guard let self, self.downloadID == id else { return }
            guard self.webView.url == pageURL,
                  let dict = result as? [String: Any], let source = dict["url"] as? String,
                  let url = URL(string: source), DownloadFile.isVideoSource(url, pageURL: pageURL) else {
                self.failDownload("请等待视频加载完成或播放后再尝试下载")
                return
            }
            let author = (dict["author"] as? String ?? "TikTok")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: ":", with: "_")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = "\(author)_\(Int(Date().timeIntervalSince1970)).mp4"
            self.promptUserForSaveDestination(suggestedFilename: filename) { [weak self] selectedURL in
                guard let self, self.downloadID == id else { return }
                guard let selectedURL else { self.resetDownload(); return }
                guard self.webView.url == pageURL else {
                    self.failDownload("页面已切换，请重新选择视频")
                    return
                }
                self.destinationURL = selectedURL
                self.showDownloadHUD().setIndeterminate(title: "正在连接视频...", subtitle: selectedURL.lastPathComponent)
                self.downloadHUD?.onCancel = { [weak self] in self?.cancelDownload() }
                var request = URLRequest(url: url)
                request.setValue("https://www.tiktok.com/", forHTTPHeaderField: "Referer")
                // WebKit streams both HTTP and Blob URLs and shares the page's cookies.
                self.webView.startDownload(using: request) { [weak self] download in
                    guard let self, self.downloadID == id else { download.cancel { _ in }; return }
                    self.attach(download)
                }
            }
        }
    }

    private func attach(_ download: WKDownload) {
        activeDownload = download
        download.delegate = self
        progressObservation = download.progress.observe(\.fractionCompleted, options: [.new]) { [weak self, weak download] progress, _ in
            let written = progress.completedUnitCount
            let total = progress.totalUnitCount
            DispatchQueue.main.async {
                guard let self, let download, self.activeDownload === download, !self.isCommittingDownload else { return }
                if total > 0 {
                    self.downloadHUD?.updateProgress(fraction: Double(written) / Double(total), writtenBytes: written, totalBytes: total)
                }
            }
        }
    }

    private func resetDownload() {
        progressObservation = nil
        activeDownload = nil
        downloadID = nil
        destinationURL = nil
        isCommittingDownload = false
        downloadHUD?.onCancel = nil
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
        temporaryURL = nil
    }

    private func failDownload(_ message: String) {
        resetDownload()
        showDownloadHUD().showError(message: message)
    }

    private func cancelDownload() {
        guard !isCommittingDownload else { return }
        let download = activeDownload
        let temporary = temporaryURL
        resetDownload()
        // Wait for WebKit to close its file before removing a canceled partial download.
        download?.cancel { _ in
            if let temporary { try? FileManager.default.removeItem(at: temporary) }
        }
    }

    private func promptUserForSaveDestination(suggestedFilename: String, completion: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.title = "选择保存视频的位置"
        panel.prompt = "保存"
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.mpeg4Movie, .quickTimeMovie, UTType(filenameExtension: "webm") ?? .movie]

        if let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloadsDir
        }

        if let window = view.window {
            panel.beginSheetModal(for: window) { response in
                if response == .OK {
                    completion(panel.url)
                } else {
                    completion(nil)
                }
            }
        } else {
            let response = panel.runModal()
            if response == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }

    func showNotification(title: String, body: String) {
        // A toast must not replace the active download's progress/cancel controls.
        guard downloadID == nil else { return }
        showDownloadHUD().showToast(title: title, subtitle: body)
    }

    // MARK: - WKNavigationDelegate (Downloads & Navigation)
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else { return }
        if downloadID != nil && !isCommittingDownload {
            cancelDownload()
            showDownloadHUD().showError(message: "网页进程已退出，视频下载已取消")
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastProcessRecovery, now - previous < 30 {
            if !isCommittingDownload {
                showDownloadHUD().showToast(title: "网页进程反复退出", subtitle: "按 Cmd+R 重新加载")
            }
            return
        }
        lastProcessRecovery = now
        if webView.reload() == nil { loadTikTok() }
    }

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
        acceptPageDownload(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        acceptPageDownload(download)
    }

    private func acceptPageDownload(_ download: WKDownload) {
        guard downloadID == nil, DownloadFile.isTrustedPage(webView.url) else {
            download.cancel { _ in }
            return
        }
        downloadID = UUID()
        attach(download)
    }

    // MARK: - WKDownloadDelegate
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard activeDownload === download else { completionHandler(nil); return }
        do { try DownloadFile.validateResponse(response) } catch {
            completionHandler(nil)
            failDownload(error.localizedDescription)
            return
        }
        let id = downloadID
        let begin: (URL?) -> Void = { [weak self] selectedURL in
            guard let self, self.downloadID == id, self.activeDownload === download else {
                completionHandler(nil)
                return
            }
            guard let selectedURL else { completionHandler(nil); self.resetDownload(); return }
            self.destinationURL = selectedURL
            let temporary = DownloadFile.temporaryURL(for: selectedURL)
            self.temporaryURL = temporary
            let hud = self.showDownloadHUD()
            if response.expectedContentLength > 0 {
                hud.startDownload(filename: selectedURL.lastPathComponent)
            } else {
                hud.setIndeterminate(title: "正在下载视频...", subtitle: selectedURL.lastPathComponent)
            }
            self.downloadHUD?.onCancel = { [weak self] in self?.cancelDownload() }
            completionHandler(temporary)
        }
        if let destinationURL { begin(destinationURL) } else {
            promptUserForSaveDestination(suggestedFilename: suggestedFilename, completion: begin)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard activeDownload === download, let temporaryURL, let destinationURL else { return }
        let id = downloadID
        isCommittingDownload = true
        progressObservation = nil
        downloadHUD?.onCancel = nil
        // File replacement may touch external volumes; keep it off the UI thread.
        DispatchQueue.global(qos: .utility).async {
            let result = Result { try DownloadFile.commit(temporaryURL, to: destinationURL) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.downloadID == id else { return }
                self.resetDownload()
                switch result {
                case .success(let savedURL):
                    NSSound(named: "Glass")?.play()
                    self.showDownloadHUD().finishDownload(fileURL: savedURL)
                case .failure(let error):
                    self.showDownloadHUD().showError(message: error.localizedDescription)
                }
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard activeDownload === download else { return }
        failDownload(error.localizedDescription)
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
        popupWindows.retain(popupWindow)
        popupWindow.makeKeyAndOrderFront(nil)

        return popupWebView
    }

    func webViewDidClose(_ webView: WKWebView) {
        if let window = webView.window { popupWindows.close(window) }
    }

    deinit {
        webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
    }
}
