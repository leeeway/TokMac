import Cocoa

final class DownloadHUDView: NSVisualEffectView {
    var onCancel: (() -> Void)?
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let revealButton = NSButton()
    private let closeButton = NSButton()

    private var targetFileURL: URL?
    private var autoDismissWorkItem: DispatchWorkItem?
    private var isDismissing = false

    var canReuse: Bool { superview != nil && !isDismissing }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active

        layer?.cornerRadius = 14
        layer?.masksToBounds = false
        layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        layer?.borderWidth = 1.0

        // Subtle drop shadow for floating elevation
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow?.shadowOffset = NSSize(width: 0, height: -4)
        shadow?.shadowBlurRadius = 12

        // Icon
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .systemBlue
        addSubview(iconView)

        // Title
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        // Subtitle
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.7)
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(subtitleLabel)

        // Progress Bar
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.style = .bar
        progressBar.minValue = 0.0
        progressBar.maxValue = 1.0
        progressBar.isIndeterminate = false
        progressBar.controlSize = .small
        addSubview(progressBar)

        // Reveal Button (Shown upon completion)
        revealButton.translatesAutoresizingMaskIntoConstraints = false
        revealButton.title = "在访达中显示"
        revealButton.bezelStyle = .inline
        revealButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        revealButton.target = self
        revealButton.action = #selector(revealInFinder)
        revealButton.isHidden = true
        addSubview(revealButton)

        // Close Button (Small 'X')
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.5)
        closeButton.target = self
        closeButton.action = #selector(closeDownload)
        addSubview(closeButton)

        NSLayoutConstraint.activate([
            // Icon
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),

            // Close button
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 18),

            // Title
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),

            // Subtitle
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),

            // Progress bar
            progressBar.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            progressBar.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 6),
            progressBar.heightAnchor.constraint(equalToConstant: 5),

            // Reveal Button
            revealButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            revealButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    func startDownload(filename: String) {
        autoDismissWorkItem?.cancel()
        targetFileURL = nil

        iconView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloading")
        iconView.contentTintColor = .systemBlue

        titleLabel.stringValue = "正在下载视频 (0%)..."
        subtitleLabel.stringValue = filename
        subtitleLabel.isHidden = false

        progressBar.isHidden = false
        progressBar.isIndeterminate = false
        progressBar.doubleValue = 0.0

        revealButton.isHidden = true

        alphaValue = 0.0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = 1.0
        }
    }

    func updateProgress(fraction: Double, writtenBytes: Int64, totalBytes: Int64) {
        progressBar.isIndeterminate = false
        progressBar.doubleValue = fraction

        let percent = Int(fraction * 100)
        let writtenStr = formatBytes(writtenBytes)
        let totalStr = totalBytes > 0 ? formatBytes(totalBytes) : "--"

        titleLabel.stringValue = "正在下载视频 (\(percent)%)"
        subtitleLabel.stringValue = "\(writtenStr) / \(totalStr)"
    }

    func setIndeterminate(title: String, subtitle: String) {
        autoDismissWorkItem?.cancel()
        targetFileURL = nil
        iconView.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: "Downloading")
        iconView.contentTintColor = .systemBlue

        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = false

        progressBar.isHidden = false
        progressBar.isIndeterminate = true
        progressBar.startAnimation(nil)

        revealButton.isHidden = true

        alphaValue = 0.0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = 1.0
        }
    }

    func showToast(title: String, subtitle: String, systemSymbol: String = "info.circle.fill", tintColor: NSColor = .systemBlue) {
        autoDismissWorkItem?.cancel()
        targetFileURL = nil

        iconView.image = NSImage(systemSymbolName: systemSymbol, accessibilityDescription: title)
        iconView.contentTintColor = tintColor

        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle
        subtitleLabel.isHidden = false

        progressBar.stopAnimation(nil)
        progressBar.isHidden = true
        revealButton.isHidden = true

        alphaValue = 0.0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            self.animator().alphaValue = 1.0
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissAnimated()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    func finishDownload(fileURL: URL) {
        autoDismissWorkItem?.cancel()
        targetFileURL = fileURL
        progressBar.stopAnimation(nil)
        progressBar.isHidden = true
        subtitleLabel.isHidden = true

        iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Success")
        iconView.contentTintColor = .systemGreen

        titleLabel.stringValue = "🎉 视频下载完成！"
        revealButton.isHidden = false

        // Automatically dismiss after 5 seconds if user does not click
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissAnimated()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: workItem)
    }

    func showError(message: String) {
        autoDismissWorkItem?.cancel()
        progressBar.stopAnimation(nil)
        progressBar.isHidden = true

        iconView.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Error")
        iconView.contentTintColor = .systemRed

        titleLabel.stringValue = "下载失败"
        subtitleLabel.stringValue = message
        subtitleLabel.isHidden = false
        revealButton.isHidden = true
        alphaValue = 1.0

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissAnimated()
        }
        autoDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: workItem)
    }

    @objc func revealInFinder() {
        guard let url = targetFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        dismissAnimated()
    }

    @objc private func closeDownload() {
        onCancel?()
        dismissAnimated()
    }

    @objc func dismissAnimated() {
        guard !isDismissing else { return }
        isDismissing = true
        autoDismissWorkItem?.cancel()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0.0
        }, completionHandler: {
            self.removeFromSuperview()
        })
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
