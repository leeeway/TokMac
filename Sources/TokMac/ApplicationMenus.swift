import Cocoa

@objc protocol PlaybackActions {
    func nextVideo()
    func prevVideo()
    func togglePlay()
    func toggleMute()
    func toggleComments()
}

enum ApplicationMenus {
    static func playback(target: PlaybackActions) -> NSMenu {
        let menu = NSMenu(title: "播放控制")
        let entries: [(String, Selector)] = [
            ("下一个视频 (↓ / J)", #selector(PlaybackActions.nextVideo)),
            ("上一个视频 (↑ / K)", #selector(PlaybackActions.prevVideo)),
            ("播放 / 暂停 (空格)", #selector(PlaybackActions.togglePlay)),
            ("静音 / 恢复声音 (M)", #selector(PlaybackActions.toggleMute)),
            ("展开 / 关闭评论区 (C)", #selector(PlaybackActions.toggleComments))
        ]
        // Unmodified playback keys belong to the page, where editing focus is known.
        for (title, action) in entries {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        return menu
    }

    static func editing() -> NSMenu {
        let menu = NSMenu(title: "编辑")
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }
}
