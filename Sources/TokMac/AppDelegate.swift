import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
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

        // 3. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "视图")
        
        let pinItem = NSMenuItem(title: "窗口置顶", action: #selector(togglePin), keyEquivalent: "t")
        pinItem.target = self
        viewMenu.addItem(pinItem)
        viewMenu.addItem(NSMenuItem.separator())

        let phoneItem = NSMenuItem(title: "手机竖屏模式 (490×820)", action: #selector(setPhoneMode), keyEquivalent: "1")
        phoneItem.target = self
        viewMenu.addItem(phoneItem)

        let commentItem = NSMenuItem(title: "视频 + 评论并列模式 (880×820)", action: #selector(setCommentMode), keyEquivalent: "3")
        commentItem.target = self
        viewMenu.addItem(commentItem)

        let desktopItem = NSMenuItem(title: "宽屏桌面模式 (1080×780)", action: #selector(setDesktopMode), keyEquivalent: "2")
        desktopItem.target = self
        viewMenu.addItem(desktopItem)

        viewMenu.addItem(NSMenuItem.separator())
        let cleanItem = NSMenuItem(title: "纯净模式 (隐藏干扰横幅)", action: #selector(toggleClean), keyEquivalent: "C")
        cleanItem.keyEquivalentModifierMask = [.command, .shift]
        cleanItem.target = self
        viewMenu.addItem(cleanItem)

        let autoNextItem = NSMenuItem(title: "自动连播下一个", action: #selector(toggleAutoNext), keyEquivalent: "A")
        autoNextItem.keyEquivalentModifierMask = [.command, .shift]
        autoNextItem.target = self
        viewMenu.addItem(autoNextItem)

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
        let playMenu = NSMenu(title: "播放控制")

        let nextItem = NSMenuItem(title: "下一个视频 (↓ / J)", action: #selector(nextVideo), keyEquivalent: "j")
        nextItem.target = self
        playMenu.addItem(nextItem)

        let prevItem = NSMenuItem(title: "上一个视频 (↑ / K)", action: #selector(prevVideo), keyEquivalent: "k")
        prevItem.target = self
        playMenu.addItem(prevItem)

        let playPauseItem = NSMenuItem(title: "播放 / 暂停 (空格)", action: #selector(togglePlay), keyEquivalent: " ")
        playPauseItem.keyEquivalentModifierMask = []
        playPauseItem.target = self
        playMenu.addItem(playPauseItem)

        let muteItem = NSMenuItem(title: "静音 / 恢复声音 (M)", action: #selector(toggleMute), keyEquivalent: "m")
        muteItem.target = self
        playMenu.addItem(muteItem)

        let toggleCommentsItem = NSMenuItem(title: "展开 / 关闭评论区 (C)", action: #selector(toggleComments), keyEquivalent: "c")
        toggleCommentsItem.target = self
        playMenu.addItem(toggleCommentsItem)

        playMenuItem.submenu = playMenu
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

    @objc private func downloadCurrentVideo() {
        mainWindowController?.downloadCurrentVideo()
    }

    @objc private func togglePin() {
        mainWindowController?.toggleAlwaysOnTop()
    }

    @objc private func setPhoneMode() {
        mainWindowController?.setPhoneMode()
    }

    @objc private func setCommentMode() {
        mainWindowController?.setCommentMode()
    }

    @objc private func setDesktopMode() {
        mainWindowController?.setDesktopMode()
    }

    @objc private func toggleClean() {
        mainWindowController?.toggleCleanMode()
    }

    @objc private func toggleAutoNext() {
        mainWindowController?.toggleAutoNext()
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

    @objc private func nextVideo() {
        mainWindowController?.nextVideo()
    }

    @objc private func prevVideo() {
        mainWindowController?.prevVideo()
    }

    @objc private func togglePlay() {
        mainWindowController?.togglePlay()
    }

    @objc private func toggleMute() {
        mainWindowController?.toggleMute()
    }

    @objc private func toggleComments() {
        mainWindowController?.toggleComments()
    }
}
