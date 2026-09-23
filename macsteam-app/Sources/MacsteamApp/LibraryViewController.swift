import AppKit

final class LibraryViewController: NSViewController,
    NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let search = NSSearchField()
    private let summary = NSTextField(labelWithString: "")
    private let table = NSTableView()
    private var refreshButton: NSButton!
    private var result = LibraryScanResult(games: [], warnings: [])
    private var visibleGames: [InstalledGame] = []
    private var isScanning = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 460))
        search.placeholderString = "Filter by name or App ID"
        search.delegate = self
        search.setAccessibilityLabel("Filter installed games")

        summary.font = Typography.body
        summary.textColor = .secondaryLabelColor
        summary.setAccessibilityLabel("Library scan status")

        for (identifier, title, width) in [
            ("title", "Game", 145.0),
            ("appID", "App ID", 65.0),
            ("library", "Library", 70.0),
            ("size", "Size", 70.0),
            ("compatibility", "Compatibility", 110.0),
            ("path", "Install Path", 132.0),
        ] {
            let column = NSTableColumn(identifier: .init(identifier))
            column.title = title
            column.width = width
            column.minWidth = 60
            column.sortDescriptorPrototype = NSSortDescriptor(
                key: identifier,
                ascending: true,
                selector: #selector(NSString.localizedCaseInsensitiveCompare(_:))
            )
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.setAccessibilityLabel("Installed Steam games")

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder

        refreshButton = makeButton(title: "Scan Again", target: self, action: #selector(scanLibrary))
        refreshButton.keyEquivalent = "r"
        refreshButton.keyEquivalentModifierMask = [.command]
        refreshButton.setAccessibilityHelp("Scans every configured Steam library again.")

        search.nextKeyView = table
        table.nextKeyView = refreshButton
        refreshButton.nextKeyView = search

        let stack = NSStackView(views: [search, summary, scroll, refreshButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Metrics.paneMargin),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Metrics.paneMargin),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: Metrics.paneMargin),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Metrics.paneMargin),
            search.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
        view = root
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if result.games.isEmpty && !isScanning { scanLibrary() }
    }

    func controlTextDidChange(_ notification: Notification) { render() }

    @objc private func scanLibrary() {
        guard !isScanning else { return }
        isScanning = true
        refreshButton?.isEnabled = false
        summary.stringValue = "Scanning configured Steam libraries…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = SteamLibraryScanner.scan()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isScanning = false
                self.refreshButton.isEnabled = true
                self.result = scanned
                self.render()
            }
        }
    }

    private func render() {
        let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        visibleGames = query.isEmpty ? result.games : result.games.filter {
            $0.title.localizedCaseInsensitiveContains(query) || String($0.appID).contains(query)
        }
        applySortDescriptors()
        table.reloadData()

        if result.games.isEmpty {
            summary.stringValue = "No installed Steam games were found. "
                + (result.warnings.first ?? "Open Steam once, then choose Scan Again.")
        } else if visibleGames.isEmpty {
            summary.stringValue = "No installed games match “\(query)”."
        } else {
            let warnings = result.warnings.isEmpty ? "" : " \(result.warnings.count) scan warning(s)."
            summary.stringValue = "Showing \(visibleGames.count) of \(result.games.count) installed game(s).\(warnings)"
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visibleGames.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, visibleGames.indices.contains(row) else { return nil }
        let game = visibleGames[row]
        let value: String
        switch tableColumn.identifier.rawValue {
        case "title": value = game.title
        case "appID": value = String(game.appID)
        case "library": value = game.libraryLabel
        case "size":
            value = game.sizeOnDisk.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                ?? "Unknown"
        case "compatibility": value = game.compatibility.rawValue
        default: value = "steamapps/common/\(game.installDirectory.lastPathComponent)"
        }
        let field = NSTextField(labelWithString: value)
        field.lineBreakMode = .byTruncatingMiddle
        field.setAccessibilityLabel("\(tableColumn.title): \(value)")
        return field
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        applySortDescriptors()
        table.reloadData()
    }

    private func applySortDescriptors() {
        guard let descriptor = table.sortDescriptors.first else { return }
        let ascending = descriptor.ascending
        let less: (InstalledGame, InstalledGame) -> Bool
        switch descriptor.key {
        case "appID": less = { $0.appID < $1.appID }
        case "library": less = { $0.libraryLabel.localizedCaseInsensitiveCompare($1.libraryLabel) == .orderedAscending }
        case "size": less = { ($0.sizeOnDisk ?? -1) < ($1.sizeOnDisk ?? -1) }
        case "compatibility": less = { $0.compatibility.rawValue < $1.compatibility.rawValue }
        case "path": less = { $0.installDirectory.lastPathComponent.localizedCaseInsensitiveCompare($1.installDirectory.lastPathComponent) == .orderedAscending }
        default: less = { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        visibleGames.sort { ascending ? less($0, $1) : less($1, $0) }
    }
}
