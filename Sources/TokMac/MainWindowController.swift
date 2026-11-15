import Cocoa

final class MainWindowController: NSWindowController, NSToolbarDelegate, WebViewControllerDelegate {
    private let webViewController = WebViewController()
    private(set) var isAlwaysOnTop: Bool = false
    private var wasAutoExpandedForDetail: Bool = false

    private let toolbarID = NSToolbar.Identifier("TokMacMainToolbar")
    private let pinItemID = NSToolbarItem.Identifier("TokMacPinItem")
    private let forYouItemID = NSToolbarItem.Identifier("TokMacForYouItem")
    private let followingItemID = NSToolbarItem.Identifier("TokMacFollowingItem")
    private let exploreItemID = NSToolbarItem.Identifier("TokMacExploreItem")
    private let downloadItemID = NSToolbarItem.Identifier("TokMacDownloadItem")
    private let modeItemID = NSToolbarItem.Identifier("TokMacModeItem")
    private let reloadItemID = NSToolbarItem.Identifier("TokMacReloadItem")

    convenience init() {
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
        window.minSize = NSSize(width: 380, height: 520)

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
            forYouItemID,
            followingItemID,
            exploreItemID,
            pinItemID,
            modeItemID,
            downloadItemID,
            reloadItemID
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            forYouItemID,
            followingItemID,
            exploreItemID,
            pinItemID,
            modeItemID,
            downloadItemID,
            reloadItemID
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isNavigational = true

        switch itemIdentifier {
        case forYouItemID:
            item.label = "推荐"
            item.toolTip = "首页推荐 (For You)"
            item.image = NSImage(systemSymbolName: "house", accessibilityDescription: "For You")
            item.action = #selector(loadForYou)
            item.target = self

        case followingItemID:
            item.label = "关注"
            item.toolTip = "已关注 (Following)"
            item.image = NSImage(systemSymbolName: "person.2", accessibilityDescription: "Following")
            item.action = #selector(loadFollowing)
            item.target = self

        case exploreItemID:
            item.label = "探索"
            item.toolTip = "探索与搜索 (Explore)"
            item.image = NSImage(systemSymbolName: "safari", accessibilityDescription: "Explore")
            item.action = #selector(loadExplore)
            item.target = self

        case pinItemID:
            item.label = "置顶"
            item.toolTip = "窗口置顶 (Cmd+T)"
            let img = NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: "Pin")
            item.image = img
            item.action = #selector(toggleAlwaysOnTop)
            item.target = self

        case modeItemID:
            item.label = "布局"
            item.toolTip = "切换竖屏/宽屏 (Cmd+1 / Cmd+2)"
            let img = NSImage(systemSymbolName: webViewController.isCompactMode ? "iphone" : "macbook", accessibilityDescription: "Layout")
            item.image = img
            item.action = #selector(toggleLayoutMode)
            item.target = self

        case downloadItemID:
            item.label = "下载"
            item.toolTip = "下载当前播放的视频 (Cmd+S)"
            item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Download")
            item.action = #selector(downloadCurrentVideo)
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
    func webViewController(_ controller: WebViewController, didChangeDetailState isOpen: Bool) {
        guard let window = window else { return }

        if isOpen && window.frame.width < 750 {
            // Video detail / comment modal opened: Smoothly expand window to 1060px to show video left, comments right!
            wasAutoExpandedForDetail = true
            var frame = window.frame
            let targetWidth: CGFloat = 1060
            frame.origin.x = max(20, frame.origin.x - (targetWidth - frame.width) / 2)
            frame.size.width = targetWidth
            window.setFrame(frame, display: true, animate: true)
        } else if !isOpen && wasAutoExpandedForDetail && webViewController.isCompactMode {
            // Detail modal closed: Restore to 490px portrait mode!
            wasAutoExpandedForDetail = false
            var frame = window.frame
            let targetWidth: CGFloat = 490
            frame.origin.x += (frame.width - targetWidth) / 2
            frame.size.width = targetWidth
            window.setFrame(frame, display: true, animate: true)
        }
    }

    // MARK: - Actions
    @objc func loadForYou() {
        webViewController.loadForYou()
    }

    @objc func loadFollowing() {
        webViewController.loadFollowing()
    }

    @objc func loadExplore() {
        webViewController.loadExplore()
    }

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

    @objc func toggleLayoutMode() {
        if webViewController.isCompactMode {
            setDesktopMode()
        } else {
            setPhoneMode()
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
        updateModeToolbarIcon()
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
        updateModeToolbarIcon()
    }

    private func updateModeToolbarIcon() {
        guard let window = window, let toolbar = window.toolbar else { return }
        for item in toolbar.items where item.itemIdentifier == modeItemID {
            item.image = NSImage(systemSymbolName: webViewController.isCompactMode ? "iphone" : "macbook", accessibilityDescription: "Layout")
        }
    }

    @objc func downloadCurrentVideo() {
        webViewController.downloadCurrentVideo()
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
