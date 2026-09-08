// Shared type scale, spacing, colors, and reusable views.

import AppKit

enum Typography {
    static var largeTitle: NSFont { .preferredFont(forTextStyle: .largeTitle) }
    static var sectionHeader: NSFont {
        .preferredFont(forTextStyle: .headline)
    }
    static var body: NSFont { .preferredFont(forTextStyle: .body) }
    static var caption: NSFont { .preferredFont(forTextStyle: .subheadline) }
    static var columnHeader: NSFont {
        let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize
        return .systemFont(ofSize: size, weight: .semibold)
    }
}

enum Colors {
    static var cardFill: NSColor {
        NSColor(name: "cardFill") { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return dark ? NSColor(white: 1, alpha: 0.06) : .controlBackgroundColor
        }
    }
    static var hairline: NSColor { .separatorColor.withAlphaComponent(Metrics.hairlineAlpha) }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var quiet: NSColor { .tertiaryLabelColor }
}

enum Metrics {
    static let paneMargin: CGFloat = 24
    static let headerGap: CGFloat = 18
    static let cornerRadius: CGFloat = 10
    static let hairlineAlpha: CGFloat = 0.6
    static let formColumnWidth: CGFloat = 460
}

extension NSView {
    func applyCardSurface() {
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        layer?.borderWidth = 1
        applyCardSurfaceColors()
    }

    func applyCardSurfaceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.layer?.backgroundColor = Colors.cardFill.cgColor
            self?.layer?.borderColor = Colors.hairline.cgColor
        }
    }
}

// MARK: - Grouped settings cards

final class SettingRow: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    let control: NSView

    init(title: String, subtitle: String? = nil, control: NSView) {
        self.control = control
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = Typography.body
        titleLabel.textColor = .labelColor
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        subtitleLabel.font = Typography.caption
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.stringValue = subtitle ?? ""
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 0
        subtitleLabel.isHidden = (subtitle == nil)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        if control.accessibilityLabel()?.isEmpty ?? true {
            control.setAccessibilityLabel(title)
        }
        if let subtitle { control.setAccessibilityHelp(subtitle) }

        let textStack = NSStackView(views: subtitle == nil ? [titleLabel] : [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textStack)
        addSubview(control)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsCard.hInset),
            textStack.topAnchor.constraint(equalTo: topAnchor, constant: SettingsCard.vInset),
            textStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsCard.vInset),

            control.centerYAnchor.constraint(equalTo: textStack.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 16),
            control.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsCard.hInset),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class SettingsCard: NSView {
    static let hInset: CGFloat = 14
    static let vInset: CGFloat = 10

    init(rows: [SettingRow]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        applyCardSurface()

        var previous: NSView?
        for (index, row) in rows.enumerated() {
            addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: leadingAnchor),
                row.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            if let previous {
                let sep = NSBox()
                sep.boxType = .separator
                sep.translatesAutoresizingMaskIntoConstraints = false
                addSubview(sep)
                NSLayoutConstraint.activate([
                    sep.topAnchor.constraint(equalTo: previous.bottomAnchor),
                    sep.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.hInset),
                    sep.trailingAnchor.constraint(equalTo: trailingAnchor),
                    row.topAnchor.constraint(equalTo: sep.bottomAnchor),
                ])
            } else {
                row.topAnchor.constraint(equalTo: topAnchor).isActive = true
            }
            if index == rows.count - 1 {
                row.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            }
            previous = row
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyCardSurfaceColors()
    }

}

@MainActor
func settingsGroupLabel(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = Typography.sectionHeader
    l.textColor = Colors.secondaryText
    l.translatesAutoresizingMaskIntoConstraints = false
    return l
}

@MainActor
func presentAlert(_ title: String, _ message: String, style: NSAlert.Style = .informational) {
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = style
    a.runModal()
}

@MainActor
func presentAppManagementAlert() {
    let a = NSAlert()
    a.messageText = "macSteam needs permission to modify apps"
    a.informativeText = "Enable macSteam under Privacy & Security \u{203A} App Management, "
        + "then try again."
    a.alertStyle = .warning
    a.addButton(withTitle: "Open Settings")
    a.addButton(withTitle: "Cancel")
    guard a.runModal() == .alertFirstButtonReturn else { return }
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
        NSWorkspace.shared.open(url)
    }
}

@MainActor
func makeScrollView(horizontalScroller: Bool = false) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = horizontalScroller
    scroll.autohidesScrollers = true
    scroll.borderType = .noBorder
    return scroll
}

@MainActor
func makeButton(title: String, target: Any?, action: Selector) -> NSButton {
    let b = NSButton(title: title, target: target, action: action)
    b.translatesAutoresizingMaskIntoConstraints = false
    b.bezelStyle = .rounded
    b.controlSize = .regular
    return b
}

enum StatusTone {
    case ok
    case warn
    case bad
    case neutral

    var color: NSColor {
        switch self {
        case .ok: return .systemGreen
        case .warn: return .systemOrange
        case .bad: return .systemRed
        case .neutral: return .tertiaryLabelColor
        }
    }
    var symbol: String {
        switch self {
        case .ok: return "checkmark.circle.fill"
        case .warn, .bad: return "exclamationmark.triangle.fill"
        case .neutral: return "minus"
        }
    }
}

@MainActor
func runBusy(spinner: NSProgressIndicator,
             setBusy: @escaping @MainActor (Bool) -> Void,
             refresh: @escaping @MainActor () -> Void,
             work: @escaping @Sendable () throws -> Void) {
    setBusy(true)
    spinner.startAnimation(nil)
    DispatchQueue.global(qos: .userInitiated).async {
        let result: Result<Void, Error> = Result { try work() }
        DispatchQueue.main.async {
            spinner.stopAnimation(nil)
            setBusy(false)
            if case .failure(let error) = result {
                if error is SteamInstaller.PermissionDenied {
                    presentAppManagementAlert()
                } else {
                    presentAlert("Couldn't complete", error.localizedDescription, style: .warning)
                }
            }
            refresh()
        }
    }
}

let deleteKeyCodes: Set<UInt16> = [51, 117]

// MARK: - Empty state

final class EmptyStateView: NSStackView {
    init(symbol: String, prompt: String, hint: String) {
        super.init(frame: .zero)

        let glyph = NSImageView()
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 34, weight: .regular)
        glyph.contentTintColor = Colors.quiet
        glyph.setAccessibilityElement(false)

        let promptLabel = NSTextField(labelWithString: prompt)
        promptLabel.font = Typography.body
        promptLabel.textColor = Colors.secondaryText
        promptLabel.alignment = .center

        let hintLabel = NSTextField(labelWithString: hint)
        hintLabel.font = Typography.caption
        hintLabel.textColor = Colors.quiet
        hintLabel.alignment = .center

        orientation = .vertical
        alignment = .centerX
        spacing = 4
        setViews([glyph, promptLabel, hintLabel], in: .center)
        setCustomSpacing(8, after: glyph)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class ResettableSlider: NSSlider {
    var defaultValue: Double?

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let value = defaultValue {
            doubleValue = value
            sendAction(action, to: target)
            return
        }
        super.mouseDown(with: event)
    }

    func snappedValue(min minVal: CGFloat, max maxVal: CGFloat, snapDistance: CGFloat) -> CGFloat {
        var h = Swift.min(Swift.max(CGFloat(doubleValue).rounded(), minVal), maxVal)
        if let def = defaultValue, abs(h - CGFloat(def)) <= snapDistance {
            h = CGFloat(def)
            doubleValue = Double(h)
        }
        return h
    }
}

@MainActor
func makeSizeSliderBar(
    slider: ResettableSlider,
    min minVal: CGFloat,
    max maxVal: CGFloat,
    defaultValue: CGFloat,
    currentValue: CGFloat,
    accessibilityLabel: String,
    smallGlyphSize: CGFloat = 11,
    largeGlyphSize: CGFloat = 17
) -> NSStackView {
    slider.minValue = Double(minVal)
    slider.maxValue = Double(maxVal)
    slider.doubleValue = Double(currentValue)
    slider.defaultValue = Double(defaultValue)
    slider.controlSize = .regular
    slider.isContinuous = true
    slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
    slider.setAccessibilityLabel(accessibilityLabel)
    slider.widthAnchor.constraint(equalToConstant: 140).isActive = true
    slider.numberOfTickMarks = 9
    slider.allowsTickMarkValuesOnly = false

    let small = NSImageView()
    small.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
    small.symbolConfiguration = .init(pointSize: smallGlyphSize, weight: .regular)
    small.contentTintColor = Colors.secondaryText
    small.setAccessibilityElement(false)

    let large = NSImageView()
    large.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
    large.symbolConfiguration = .init(pointSize: largeGlyphSize, weight: .regular)
    large.contentTintColor = Colors.secondaryText
    large.setAccessibilityElement(false)

    let bar = NSStackView(views: [small, slider, large])
    bar.orientation = .horizontal
    bar.alignment = .centerY
    bar.spacing = 5
    bar.translatesAutoresizingMaskIntoConstraints = false
    return bar
}
