import AppKit

final class DiagnosticsViewController: NSViewController {
    private let stateLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let details = NSTextView()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        stateLabel.font = Typography.largeTitle
        stateLabel.setAccessibilityLabel("Installation health")
        summaryLabel.font = Typography.body
        summaryLabel.textColor = .secondaryLabelColor

        details.isEditable = false
        details.isSelectable = true
        details.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        details.textContainerInset = NSSize(width: 10, height: 10)
        details.setAccessibilityLabel("Health checks")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = details

        let refreshButton = makeButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshButton.keyEquivalent = "r"
        refreshButton.keyEquivalentModifierMask = [.command]
        let copyButton = makeButton(title: "Copy Report", target: self, action: #selector(copyReport))
        let exportButton = makeButton(title: "Export Report…", target: self, action: #selector(exportReport))
        let buttons = NSStackView(views: [refreshButton, copyButton, exportButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [stateLabel, summaryLabel, scroll, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        buttons.alignment = .centerY
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.paneMargin),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
        ])
        view = root
        refresh()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        refresh()
    }

    @objc private func refresh() {
        let health = HealthDiagnostics.inspect()
        stateLabel.stringValue = health.state.rawValue
        summaryLabel.stringValue = health.summary
        details.string = health.checks.map { "[\($0.status.rawValue.uppercased())] \($0.name)\n\($0.detail)" }
            .joined(separator: "\n\n")
    }

    @objc private func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(HealthDiagnostics.report(HealthDiagnostics.inspect()), forType: .string)
    }

    @objc private func exportReport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "macsteam-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try HealthDiagnostics.report(HealthDiagnostics.inspect()).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }
}
