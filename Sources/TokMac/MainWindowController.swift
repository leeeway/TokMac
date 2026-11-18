import Cocoa

final class MainWindowController: NSWindowController, NSToolbarDelegate {
    private let webViewController = WebViewController()
    private(set) var isAlwaysOnTop: Bool = false

    private let toolbarID = NSToolbar.Identifier("TokMacMainToolbar")
    private let pinItemID = NSToolbarItem.Identifier("TokMacPinItem")
    private let downloadItemID = NSToolbarItem.Identifier("TokMacDownloadItem")
    private let modeItemID = NSToolbarItem.Identifier("TokMacModeItem")
    private let reloadItemID = NSToolbarItem.Identifier("TokMacReloadItem")

    convenience init() {
        // Default to a comfortable desktop width (1080x760)
        let initialRect = NSRect(x: 100, y: 100, width: 1080, height: 760)
        let window = NSWindow(
            contentRect: initialRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "TokMac"
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 460, height: 560)

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
        window.toolbarStyle = .unified
    }

    // MARK: - NSToolbarDelegate
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            pinItemID,
            modeItemID,
            downloadItemID,
            reloadItemID
        ]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            pinItemID,
            modeItemID,
            downloadItemID,
            reloadItemID
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .flexibleSpace {
            return NSToolbarItem(itemIdentifier: itemIdentifier)
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.isNavigational = false

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
            item.toolTip = "切换竖屏/桌面模式 (Cmd+1 / Cmd+2)"
            let img = NSImage(systemSymbolName: webViewController.isCompactMode ? "macbook" : "iphone", accessibilityDescription: "Layout")
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

    @objc func downloadCurrentVideo() {
        webViewController.downloadCurrentVideo()
    }

    @objc func toggleAlwaysOnTop() {
        guard let window = window else { return }
        isAlwaysOnTop.toggle()
        window.level = isAlwaysOnTop ? .floating : .normal
        updateToolbarState()
    }

    private func updateToolbarState() {
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case pinItemID:
                item.image = NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: "Pin")
                item.toolTip = "窗口置顶：\(isAlwaysOnTop ? "已开启" : "已关闭") (Cmd+T)"
            case modeItemID:
                item.image = NSImage(systemSymbolName: webViewController.isCompactMode ? "macbook" : "iphone", accessibilityDescription: "Layout")
                item.toolTip = webViewController.isCompactMode ? "切换到桌面模式 (Cmd+2)" : "切换到竖屏模式 (Cmd+1)"
            default: break
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
        resize(window, to: NSSize(width: 520, height: 840))
        updateToolbarState()
    }

    @objc func setDesktopMode() {
        guard let window = window else { return }
        webViewController.isCompactMode = false
        resize(window, to: NSSize(width: 1080, height: 760))
        updateToolbarState()
    }

    static func layoutFrame(from frame: NSRect, size: NSSize, workArea: NSRect) -> NSRect {
        let width = min(size.width, workArea.width)
        let height = min(size.height, workArea.height)
        let x = min(max(frame.minX, workArea.minX), workArea.maxX - width)
        let y = min(max(frame.maxY - height, workArea.minY), workArea.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func resize(_ window: NSWindow, to size: NSSize) {
        guard let workArea = (window.screen ?? NSScreen.main)?.visibleFrame else {
            window.setContentSize(size)
            return
        }
        window.setFrame(Self.layoutFrame(from: window.frame, size: size, workArea: workArea), display: true, animate: true)
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
