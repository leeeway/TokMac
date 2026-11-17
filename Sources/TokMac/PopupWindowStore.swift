import Cocoa

/// Owns OAuth windows until either the user or the page closes them.
final class PopupWindowStore: NSObject, NSWindowDelegate {
    private(set) var windows: [NSWindow] = []

    func retain(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.delegate = self
        windows.append(window)
    }

    func close(_ window: NSWindow) {
        guard windows.contains(where: { $0 === window }) else { return }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        window.delegate = nil
        windows.removeAll { $0 === window }
    }
}
