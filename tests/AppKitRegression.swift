import Cocoa
import TokMacCore

// The real window controller is exercised with a local empty content view, so these
// tests don't navigate to TikTok, touch cookies, or require a network connection.
final class WebViewController: NSViewController {
    var isCompactMode = false
    override func loadView() { view = NSView() }
    func loadForYou() {}
    func loadFollowing() {}
    func loadExplore() {}
    func downloadCurrentVideo() {}
    func reloadPage() {}
    func goBack() {}
    func goForward() {}
    func nextVideo() {}
    func prevVideo() {}
    func togglePlay() {}
    func toggleMute() {}
    func toggleComments() {}
    func copyCurrentVideoLink() {}
    func currentVideo(_ completion: @escaping (SavedVideo?) -> Void) { completion(nil) }
    func openSavedVideo(_ video: SavedVideo) {}
    func showNotification(title: String, body: String) {}
}

final class PlaybackReceiver: NSObject, PlaybackActions {
    func nextVideo() {}
    func prevVideo() {}
    func togglePlay() {}
    func toggleMute() {}
    func toggleComments() {}
}

@main struct AppKitRegression {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let store = PopupWindowStore()
        weak var releasedWindow: NSWindow?
        for _ in 0..<20 {
            autoreleasepool {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                releasedWindow = window
                store.retain(window)
                precondition(!window.isReleasedWhenClosed)
                precondition(store.windows.count == 1)
                window.close() // Manual close must take the same cleanup path as the page.
                precondition(store.windows.isEmpty)
            }
            precondition(releasedWindow == nil, "Closed OAuth window must not be retained")
        }
        autoreleasepool {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            store.retain(window)
            store.close(window)
            store.close(window) // Repeated callbacks must be safe.
            precondition(store.windows.isEmpty)
        }
        let receiver = PlaybackReceiver()
        let playback = ApplicationMenus.playback(target: receiver)
        precondition(playback.items.count == 5)
        precondition(playback.items.allSatisfy { $0.keyEquivalent.isEmpty }, "Playback menus must not steal system or text-entry keys")
        let editing = ApplicationMenus.editing()
        let copy = editing.items.first { $0.keyEquivalent == "c" }!
        precondition(copy.action == #selector(NSText.copy(_:)) && copy.target == nil && copy.keyEquivalentModifierMask == .command)
        let controller = MainWindowController()
        precondition(controller.window?.windowController === controller, "Web context actions must reach the main controller")
        let toolbar = controller.window!.toolbar!
        let pin = toolbar.items.first { $0.itemIdentifier.rawValue == "TokMacPinItem" }!
        let mode = toolbar.items.first { $0.itemIdentifier.rawValue == "TokMacModeItem" }!
        let originalPin = pin.image
        controller.toggleAlwaysOnTop()
        precondition(controller.isAlwaysOnTop && controller.window!.level == .floating)
        precondition(pin.image !== originalPin && pin.toolTip!.contains("已开启"))
        let originalMode = mode.image
        controller.setPhoneMode()
        precondition(mode.image !== originalMode && mode.toolTip!.contains("桌面模式"))
        controller.setDesktopMode()
        precondition(mode.toolTip!.contains("竖屏模式"))
        let workArea = NSRect(x: -1280, y: 25, width: 1280, height: 680)
        let edge = NSRect(x: -520, y: 25, width: 520, height: 560)
        let wide = MainWindowController.layoutFrame(from: edge, size: NSSize(width: 1080, height: 760), workArea: workArea)
        precondition(workArea.contains(wide) && wide.size == NSSize(width: 1080, height: 680))
        if let visible = NSScreen.main?.visibleFrame {
            controller.window?.setFrame(NSRect(x: visible.maxX - 520, y: visible.minY, width: 520, height: 560), display: false)
            controller.setDesktopMode()
            precondition(visible.contains(controller.window!.frame), "Switching modes at a screen edge must keep the window visible")
        }
        let parent = controller.window!.contentView!
        let oldHUD = DownloadHUDView()
        parent.addSubview(oldHUD)
        precondition(oldHUD.canReuse)
        oldHUD.dismissAnimated()
        precondition(!oldHUD.canReuse, "An in-flight dismissal must prevent reuse immediately")
        let newHUD = DownloadHUDView()
        parent.addSubview(newHUD)
        newHUD.startDownload(filename: "new download.mp4")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
        precondition(oldHUD.superview == nil && newHUD.canReuse, "Old animations must not remove a new download HUD")
        controller.window?.close()
        print("AppKit popup lifecycle, system shortcuts, and toolbar regression checks passed.")
    }
}
