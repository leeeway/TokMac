import Cocoa

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let webViewController = WebViewController()
    private(set) var isAlwaysOnTop: Bool = false

    private let toolbarID = NSToolbar.Identifier("TokMacMainToolbar")
    private let pinItemID = NSToolbarItem.Identifier("TokMacPinItem")
    private let modeItemID = NSToolbarItem.Identifier("TokMacModeItem")
    private let cleanItemID = NSToolbarItem.Identifier("TokMacCleanItem")
    private let autoNextItemID = NSToolbarItem.Identifier("TokMacAutoNextItem")
    private let reloadItemID = NSToolbarItem.Identifier("TokMacReloadItem")

    convenience init() {
        let initialRect = NSRect(x: 100, y: 100, width: 420, height: 780)
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
        window.minSize = NSSize(width: 320, height: 500)

        // Center on screen
        window.center()
        window.setFrameAutosaveName("TokMainWindow")

        self.init(window: window)

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
            item.label = "布局"
            item.toolTip = "切换竖屏/宽屏模式 (Cmd+1 / Cmd+2)"
            let img = NSImage(systemSymbolName: webViewController.isCompactMode ? "iphone" : "macbook", accessibilityDescription: "Layout")
            item.image = img
            item.action = #selector(toggleLayoutMode)
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

    // MARK: - Actions
    @objc func toggleAlwaysOnTop() {
        guard let window = window else { return }
        isAlwaysOnTop.toggle()
        window.level = isAlwaysOnTop ? .floating : .normal

        // Refresh toolbar item icon
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
        let targetWidth: CGFloat = 420
        let targetHeight: CGFloat = 780
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
        let targetHeight: CGFloat = 750
        frame.origin.y += (frame.size.height - targetHeight)
        frame.size = NSSize(width: targetWidth, height: targetHeight)
        window.setFrame(frame, display: true, animate: true)

        updateModeToolbarIcon()
    }

    @objc func setMiniMode() {
        guard let window = window else { return }
        webViewController.isCompactMode = true
        var frame = window.frame
        let targetWidth: CGFloat = 340
        let targetHeight: CGFloat = 600
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
}
