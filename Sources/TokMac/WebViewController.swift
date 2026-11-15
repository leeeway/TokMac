import Cocoa
import WebKit

final class WebViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    private(set) var webView: WKWebView!
    private var progressIndicator: NSProgressIndicator!
    private var popupWindows: [NSWindow] = []

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
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 780))
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

        // Inject script to handle shortcuts & clean layout
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

        // Standard modern Safari Desktop User-Agent for seamless login & video streaming
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

        // Dark background for video player
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

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateCompactModeState()
        updateCleanModeState()
        updateAutoNextState()
    }

    // MARK: - WKUIDelegate (OAuth Popup Support for Google/Apple/TikTok Login)
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Create popup window for OAuth / Login dialogs
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
