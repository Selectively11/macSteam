import AppKit

final class DiagnosticsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let stateLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let table = NSTableView()
    private var health = InstallationHealth(state: .missing, summary: "", checks: [])

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 460))
        stateLabel.font = Typography.largeTitle
        stateLabel.setAccessibilityLabel("Installation health")
        summaryLabel.font = Typography.body
        summaryLabel.textColor = .secondaryLabelColor

        for (identifier, title, width) in [("status", "Status", 90.0), ("check", "Check", 150.0), ("detail", "Detail", 280.0)] {
            let column = NSTableColumn(identifier: .init(identifier))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.setAccessibilityLabel("Installation health checks")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = table

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
        health = HealthDiagnostics.inspect()
        stateLabel.stringValue = health.state.rawValue
        summaryLabel.stringValue = health.summary
        table.reloadData()
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

    func numberOfRows(in tableView: NSTableView) -> Int { health.checks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn else { return nil }
        let check = health.checks[row]
        let text: String
        switch tableColumn.identifier.rawValue {
        case "status": text = check.status.rawValue.capitalized
        case "check": text = check.name
        default: text = check.detail
        }
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel("\(tableColumn.title): \(text)")
        return field
    }
}
