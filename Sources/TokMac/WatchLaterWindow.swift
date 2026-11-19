import Cocoa
import TokMacCore

final class WatchLaterWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let store: WatchLaterStore
    private let search = NSSearchField()
    private let table = NSTableView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton()
    private let removeButton = NSButton()
    private var entries: [SavedVideo]?
    private var visibleEntries: [SavedVideo] = []
    private(set) var openedVideo: SavedVideo?

    init(store: WatchLaterStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 414),
                              styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "稍后看"
        window.isReleasedWhenClosed = false
        configure(window)
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configure(_ window: NSWindow) {
        let content = window.contentView!
        let scroll = NSScrollView()
        let close = NSButton(title: "关闭", target: self, action: #selector(closeSheet))
        close.keyEquivalent = "\u{1b}"
        openButton.title = "打开视频"
        openButton.target = self
        openButton.action = #selector(openVideo)
        openButton.keyEquivalent = "\r"
        removeButton.title = "移除"
        removeButton.target = self
        removeButton.action = #selector(removeVideo)
        let buttons = NSStackView(views: [removeButton, close, openButton])
        buttons.spacing = 8

        search.placeholderString = "搜索标题、作者或视频 ID"
        search.setAccessibilityLabel("搜索稍后看")
        search.delegate = self
        search.sendsSearchStringImmediately = true
        status.textColor = .secondaryLabelColor
        table.setAccessibilityLabel("已收藏的视频")
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("video")))
        table.headerView = nil
        table.rowHeight = 62
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openVideo)
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        for view in [search, scroll, status, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            search.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            search.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            search.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: search.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: search.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            status.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -16),
            status.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            buttons.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
        window.initialFirstResponder = search
    }

    func reload() {
        do {
            entries = try store.videos()
        } catch {
            entries = nil
        }
        applySearch()
    }

    func controlTextDidChange(_ notification: Notification) { applySearch() }
    func numberOfRows(in tableView: NSTableView) -> Int { visibleEntries.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("saved-video")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? WatchLaterCell ?? WatchLaterCell()
        cell.identifier = identifier
        cell.show(visibleEntries[row])
        return cell
    }

    private var selectedVideo: SavedVideo? {
        visibleEntries.indices.contains(table.selectedRow) ? visibleEntries[table.selectedRow] : nil
    }

    private func applySearch() {
        let selected = selectedVideo?.id
        visibleEntries = entries?.filter { $0.matches(search.stringValue) } ?? []
        table.reloadData()
        if !visibleEntries.isEmpty {
            let row = visibleEntries.firstIndex(where: { $0.id == selected }) ?? 0
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
        }
        updateButtons()
        if let entries {
            showStatus(entries.isEmpty ? "还没有收藏的视频" : visibleEntries.isEmpty ? "没有匹配的视频" : nil)
        } else {
            showStatus("无法读取稍后看列表")
        }
    }

    private func updateButtons() {
        openButton.isEnabled = selectedVideo != nil
        removeButton.isEnabled = selectedVideo != nil
    }

    private func showStatus(_ message: String?) {
        status.stringValue = message ?? ""
        status.isHidden = message == nil
    }

    @objc private func openVideo() {
        guard let video = selectedVideo else { return }
        openedVideo = video
        closeSheet()
    }

    @objc private func removeVideo() {
        guard let video = selectedVideo else { return }
        do {
            try store.remove(video)
            reload()
        } catch {
            showStatus("无法移除此视频")
        }
    }

    @objc private func closeSheet() {
        guard let window else { return }
        window.sheetParent?.endSheet(window)
    }
}

private final class WatchLaterCell: NSTableCellView {
    private let cover = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.contentTintColor = .secondaryLabelColor
        cover.setAccessibilityElement(false)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        subtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, subtitleLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let text = NSStackView(views: [titleLabel, subtitleLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        for view in [cover, text] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            cover.centerYAnchor.constraint(equalTo: centerYAnchor),
            cover.widthAnchor.constraint(equalToConstant: 74),
            cover.heightAnchor.constraint(equalToConstant: 50),
            text.leadingAnchor.constraint(equalTo: cover.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ video: SavedVideo) {
        titleLabel.stringValue = video.title
        titleLabel.toolTip = video.caption
        subtitleLabel.stringValue = video.subtitle
        cover.image = video.thumbnail.flatMap(NSImage.init(data:))
            ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil)
    }
}
