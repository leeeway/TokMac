import Cocoa

final class MainWindowController: NSWindowController, NSToolbarDelegate, WebViewControllerDelegate {
    private let webViewController = WebViewController()
    private(set) var isAlwaysOnTop: Bool = false

    private let toolbarID = NSToolbar.Identifier("TokMacMainToolbar")
    private let pinItemID = NSToolbarItem.Identifier("TokMacPinItem")
    private let modeItemID = NSToolbarItem.Identifier("TokMacModeItem")
    private let commentModeItemID = NSToolbarItem.Identifier("TokMacCommentModeItem")
    private let downloadItemID = NSToolbarItem.Identifier("TokMacDownloadItem")
    private let cleanItemID = NSToolbarItem.Identifier("TokMacCleanItem")
    private let autoNextItemID = NSToolbarItem.Identifier("TokMacAutoNextItem")
    private let reloadItemID = NSToolbarItem.Identifier("TokMacReloadItem")

    convenience init() {
        // Optimized 490x820 size ensures 9:16 video + action buttons (Like, Comment, Share) are 100% visible
        let initialRect = NSRect(x: 100, y: 100, width: 490, height: 820)
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.title = "TokMac"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.minSize = NSSize(width: 360, height: 520)

        window.center()
        window.setFrameAutosaveName("TokMainWindow")

        self.init(window: window)

        webViewController.delegate = self
        contentViewController = webViewController
        setupToolbar()
    }

    private func setupToolbar() {
        guard let window = window else { return }
        let toolbar = NSToolbar(identifier: toolbarID)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
    }

    // MARK: - NSToolbarDelegate
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            pinItemID,
            modeItemID,
            commentModeItemID,
            downloadItemID,
            cleanItemID,
            autoNextItemID,
            reloadItemID
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            pinItemID,
            modeItemID,
            commentModeItemID,
            downloadItemID,
            cleanItemID,
            autoNextItemID,
            reloadItemID
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isNavigational = true

        switch itemIdentifier {
        case pinItemID:
            item.label = "置顶"
            item.toolTip = "窗口置顶 (Cmd+T)"
            let img = NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: "Pin")
            item.image = img
            item.action = #selector(toggleAlwaysOnTop)
            item.target = self

        case modeItemID:
            item.label = "竖屏"
            item.toolTip = "手机竖屏模式 (Cmd+1)"
            item.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "Phone")
            item.action = #selector(setPhoneMode)
            item.target = self

        case commentModeItemID:
            item.label = "评论"
            item.toolTip = "视频+评论并列模式 (Cmd+3 或 C)"
            item.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right", accessibilityDescription: "Comments")
            item.action = #selector(setCommentMode)
            item.target = self

        case downloadItemID:
            item.label = "下载"
            item.toolTip = "下载当前播放的视频 (Cmd+S)"
            item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Download")
            item.action = #selector(downloadCurrentVideo)
            item.target = self

        case cleanItemID:
            item.label = "纯净"
            item.toolTip = "隐藏干扰横幅 (Cmd+Shift+C)"
            let img = NSImage(systemSymbolName: webViewController.isCleanMode ? "sparkles" : "sparkle", accessibilityDescription: "Clean")
            item.image = img
            item.action = #selector(toggleCleanMode)
            item.target = self

        case autoNextItemID:
            item.label = "连播"
            item.toolTip = "视频播完自动切下一个 (Cmd+Shift+A)"
            let img = NSImage(systemSymbolName: webViewController.isAutoNextEnabled ? "play.circle.fill" : "play.circle", accessibilityDescription: "AutoNext")
            item.image = img
            item.action = #selector(toggleAutoNext)
            item.target = self

        case reloadItemID:
            item.label = "刷新"
            item.toolTip = "刷新页面 (Cmd+R)"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            item.action = #selector(reloadPage)
            item.target = self

        default:
            return nil
        }

        return item
    }

    // MARK: - WebViewControllerDelegate
    func webViewController(_ controller: WebViewController, didChangeCommentState isOpen: Bool) {
        guard let window = window else { return }
        if isOpen && window.frame.width < 650 {
            // Auto expand window to show comments side-by-side!
            var frame = window.frame
            let targetWidth: CGFloat = 880
            frame.origin.x = max(20, frame.origin.x - (targetWidth - frame.width) / 2)
            frame.size.width = targetWidth
            window.setFrame(frame, display: true, animate: true)
        } else if !isOpen && window.frame.width >= 800 && webViewController.isCompactMode {
            // Restore to compact phone mode
            var frame = window.frame
            let targetWidth: CGFloat = 490
            frame.origin.x += (frame.width - targetWidth) / 2
            frame.size.width = targetWidth
            window.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Actions
    @objc func toggleAlwaysOnTop() {
        guard let window = window else { return }
        isAlwaysOnTop.toggle()
        window.level = isAlwaysOnTop ? .floating : .normal

        if let toolbar = window.toolbar {
            for item in toolbar.items where item.itemIdentifier == pinItemID {
                item.image = NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: "Pin")
            }
        }
    }

    @objc func setPhoneMode() {
        guard let window = window else { return }
        webViewController.isCompactMode = true
        var frame = window.frame
        let targetWidth: CGFloat = 490
        let targetHeight: CGFloat = 820
        frame.origin.y += (frame.size.height - targetHeight)
        frame.size = NSSize(width: targetWidth, height: targetHeight)
        window.setFrame(frame, display: true, animate: true)
    }

    @objc func setCommentMode() {
        guard let window = window else { return }
        webViewController.isCompactMode = false
        var frame = window.frame
        let targetWidth: CGFloat = 880
        let targetHeight: CGFloat = 820
        frame.origin.y += (frame.size.height - targetHeight)
        frame.size = NSSize(width: targetWidth, height: targetHeight)
        window.setFrame(frame, display: true, animate: true)

        // Open comments if not open
        webViewController.toggleComments()
    }

    @objc func setDesktopMode() {
        guard let window = window else { return }
        webViewController.isCompactMode = false
        var frame = window.frame
        let targetWidth: CGFloat = 1080
        let targetHeight: CGFloat = 780
        frame.origin.y += (frame.size.height - targetHeight)
        frame.size = NSSize(width: targetWidth, height: targetHeight)
        window.setFrame(frame, display: true, animate: true)
    }

    @objc func downloadCurrentVideo() {
        webViewController.downloadCurrentVideo()
    }

    @objc func toggleCleanMode() {
        webViewController.isCleanMode.toggle()
        guard let window = window, let toolbar = window.toolbar else { return }
        for item in toolbar.items where item.itemIdentifier == cleanItemID {
            item.image = NSImage(systemSymbolName: webViewController.isCleanMode ? "sparkles" : "sparkle", accessibilityDescription: "Clean")
        }
    }

    @objc func toggleAutoNext() {
        webViewController.isAutoNextEnabled.toggle()
        guard let window = window, let toolbar = window.toolbar else { return }
        for item in toolbar.items where item.itemIdentifier == autoNextItemID {
            item.image = NSImage(systemSymbolName: webViewController.isAutoNextEnabled ? "play.circle.fill" : "play.circle", accessibilityDescription: "AutoNext")
        }
    }

    @objc func reloadPage() {
        webViewController.reloadPage()
    }

    @objc func goBack() {
        webViewController.goBack()
    }

    @objc func goForward() {
        webViewController.goForward()
    }

    @objc func nextVideo() {
        webViewController.nextVideo()
    }

    @objc func prevVideo() {
        webViewController.prevVideo()
    }

    @objc func togglePlay() {
        webViewController.togglePlay()
    }

    @objc func toggleMute() {
        webViewController.toggleMute()
    }

    @objc func toggleComments() {
        webViewController.toggleComments()
    }
}
