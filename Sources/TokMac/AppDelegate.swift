import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, PlaybackActions {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "TokMac")
        appMenu.addItem(withTitle: "关于 TokMac", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 TokMac", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 TokMac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File / Actions Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        let downloadItem = NSMenuItem(title: "下载当前视频到电脑", action: #selector(downloadCurrentVideo), keyEquivalent: "s")
        downloadItem.target = self
        fileMenu.addItem(downloadItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = ApplicationMenus.editing()
        mainMenu.addItem(editMenuItem)

        // 3. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "视图")
        
        let pinItem = NSMenuItem(title: "窗口置顶", action: #selector(togglePin), keyEquivalent: "t")
        pinItem.target = self
        viewMenu.addItem(pinItem)
        viewMenu.addItem(NSMenuItem.separator())

        let forYouItem = NSMenuItem(title: "首页推荐 (For You)", action: #selector(loadForYou), keyEquivalent: "")
        forYouItem.target = self
        viewMenu.addItem(forYouItem)

        let followingItem = NSMenuItem(title: "已关注 (Following)", action: #selector(loadFollowing), keyEquivalent: "")
        followingItem.target = self
        viewMenu.addItem(followingItem)

        let exploreItem = NSMenuItem(title: "探索 (Explore)", action: #selector(loadExplore), keyEquivalent: "")
        exploreItem.target = self
        viewMenu.addItem(exploreItem)

        viewMenu.addItem(NSMenuItem.separator())

        let phoneItem = NSMenuItem(title: "手机竖屏模式 (520×840)", action: #selector(setPhoneMode), keyEquivalent: "1")
        phoneItem.target = self
        viewMenu.addItem(phoneItem)

        let desktopItem = NSMenuItem(title: "宽屏桌面模式 (1080×760)", action: #selector(setDesktopMode), keyEquivalent: "2")
        desktopItem.target = self
        viewMenu.addItem(desktopItem)

        viewMenu.addItem(NSMenuItem.separator())
        let reloadItem = NSMenuItem(title: "重新加载", action: #selector(reloadPage), keyEquivalent: "r")
        reloadItem.target = self
        viewMenu.addItem(reloadItem)

        let backItem = NSMenuItem(title: "后退", action: #selector(goBack), keyEquivalent: "[")
        backItem.target = self
        viewMenu.addItem(backItem)

        let forwardItem = NSMenuItem(title: "前进", action: #selector(goForward), keyEquivalent: "]")
        forwardItem.target = self
        viewMenu.addItem(forwardItem)

        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 4. Playback Menu
        let playMenuItem = NSMenuItem()
        playMenuItem.submenu = ApplicationMenus.playback(target: self)
        mainMenu.addItem(playMenuItem)

        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func loadForYou() {
        mainWindowController?.loadForYou()
    }

    @objc private func loadFollowing() {
        mainWindowController?.loadFollowing()
    }

    @objc private func loadExplore() {
        mainWindowController?.loadExplore()
    }

    @objc private func downloadCurrentVideo() {
        mainWindowController?.downloadCurrentVideo()
    }

    @objc private func togglePin() {
        mainWindowController?.toggleAlwaysOnTop()
    }

    @objc private func setPhoneMode() {
        mainWindowController?.setPhoneMode()
    }

    @objc private func setDesktopMode() {
        mainWindowController?.setDesktopMode()
    }

    @objc private func reloadPage() {
        mainWindowController?.reloadPage()
    }

    @objc private func goBack() {
        mainWindowController?.goBack()
    }

    @objc private func goForward() {
        mainWindowController?.goForward()
    }

    @objc func nextVideo() {
        mainWindowController?.nextVideo()
    }

    @objc func prevVideo() {
        mainWindowController?.prevVideo()
    }

    @objc func togglePlay() {
        mainWindowController?.togglePlay()
    }

    @objc func toggleMute() {
        mainWindowController?.toggleMute()
    }

    @objc func toggleComments() {
        mainWindowController?.toggleComments()
    }
}
