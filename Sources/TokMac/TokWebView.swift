import Cocoa
import WebKit

final class TokWebView: WKWebView {
    weak var controller: WebViewController?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        let downloadItem = NSMenuItem(title: "⬇️ 下载当前视频 (Cmd+S)", action: #selector(handleDownload), keyEquivalent: "s")
        downloadItem.target = self
        menu.insertItem(downloadItem, at: 0)

        let commentItem = NSMenuItem(title: "💬 查看 / 隐藏评论 (C)", action: #selector(handleComments), keyEquivalent: "")
        commentItem.target = self
        menu.insertItem(commentItem, at: 1)

        let copyLinkItem = NSMenuItem(title: "📋 复制页面链接", action: #selector(handleCopyLink), keyEquivalent: "")
        copyLinkItem.target = self
        menu.insertItem(copyLinkItem, at: 2)

        menu.insertItem(NSMenuItem.separator(), at: 3)
    }

    @objc private func handleDownload() {
        controller?.downloadCurrentVideo()
    }

    @objc private func handleComments() {
        controller?.toggleComments()
    }

    @objc private func handleCopyLink() {
        controller?.copyCurrentVideoLink()
    }
}
