import AppKit

extension BookTableColumnID {
    var identifier: NSUserInterfaceItemIdentifier { NSUserInterfaceItemIdentifier(rawValue) }
}

private func makeLabel() -> NSTextField {
    let f = NSTextField(labelWithString: "")
    f.translatesAutoresizingMaskIntoConstraints = false
    f.lineBreakMode = .byTruncatingTail
    f.cell?.usesSingleLineMode = true
    f.cell?.truncatesLastVisibleLine = true
    return f
}

/// Своё `NSControl`, а не `NSButton`: вид — 14×14 из CompactCheckbox, а клик
/// не должен ни выделять строку, ни брать фокус.
final class BookCheckbox: NSControl {
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true } } }
    var isEmphasized = false { didSet { if isEmphasized != oldValue { needsDisplay = true } } }
    var onToggle: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        refusesFirstResponder = true
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: 14, height: 14) }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onToggle?() }
    }

    override func accessibilityValue() -> Any? { NSNumber(value: isOn ? 1 : 0) }

    override func accessibilityPerformPress() -> Bool {
        guard let onToggle else { return false }
        onToggle()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: (bounds.width - 14) / 2, y: (bounds.height - 14) / 2, width: 14, height: 14)
        let fill: NSColor
        let stroke: NSColor
        let tick: NSColor
        switch (isEmphasized, isOn) {
        case (false, false): fill = .white; stroke = NSColor(white: 0.78, alpha: 1); tick = .clear
        case (false, true): fill = .controlAccentColor; stroke = .controlAccentColor; tick = .white
        case (true, false): fill = .clear; stroke = .white; tick = .clear
        case (true, true): fill = .white; stroke = .white; tick = .controlAccentColor
        }
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 2.5, yRadius: 2.5)
        path.lineWidth = 1
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.stroke()
        guard isOn,
              let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [tick])))
        else { return }
        let s = image.size
        image.draw(in: NSRect(x: box.midX - s.width / 2, y: box.midY - s.height / 2,
                              width: s.width, height: s.height),
                   from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

/// Галочка живёт в ячейке названия: только так отступ книги серии сдвигает
/// галочку и название вместе, а правые колонки стоят на месте.
final class BookTitleCellView: NSTableCellView {
    let checkbox = BookCheckbox()
    let titleLabel = makeLabel()
    private(set) var leadingInset: CGFloat = BookTableColumns.rowInset
    private(set) var showsSelected = false
    private var checkboxLeading: NSLayoutConstraint!
    private var labelLeading: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .labelColor
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(checkbox)
        addSubview(titleLabel)
        textField = titleLabel
        checkboxLeading = checkbox.leadingAnchor.constraint(equalTo: leadingAnchor)
        labelLeading = titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor)
        NSLayoutConstraint.activate([
            checkboxLeading, labelLeading,
            checkbox.widthAnchor.constraint(equalToConstant: 14),
            checkbox.heightAnchor.constraint(equalToConstant: 14),
            checkbox.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        applyInset()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { checkbox.isEmphasized = backgroundStyle == .emphasized }
    }

    func configure(book: Book, inSeries: Bool, isChecked: Bool, isSelected: Bool,
                   onToggle: @escaping () -> Void) {
        leadingInset = BookTableColumns.rowInset + (inSeries ? BookTableColumns.indent : 0)
        applyInset()
        showsSelected = isSelected
        titleLabel.stringValue = book.title
        titleLabel.font = .systemFont(ofSize: 13, weight: isSelected ? .semibold : .regular)
        checkbox.isOn = isChecked
        checkbox.onToggle = onToggle
        checkbox.setAccessibilityLabel("Отметить: \(book.title)")
    }

    private func applyInset() {
        checkboxLeading.constant = leadingInset + (BookTableColumns.checkboxWidth - 14) / 2
        labelLeading.constant = leadingInset + BookTableColumns.checkboxWidth + BookTableColumns.spacing
    }
}

final class BookTextCellView: NSTableCellView {
    let column: BookTableColumnID
    let label = makeLabel()

    init(column: BookTableColumnID) {
        precondition(column != .title, "Название рисует BookTitleCellView")
        self.column = column
        super.init(frame: .zero)
        identifier = column.identifier
        label.textColor = .secondaryLabelColor
        label.alignment = column == .genres ? .left : .right
        label.font = column == .genres
            ? .systemFont(ofSize: 13)
            : .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(label)
        textField = label
        var constraints = [
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BookTableColumns.spacing),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]
        switch column {
        case .num: constraints.append(label.widthAnchor.constraint(equalToConstant: BookTableColumns.numWidth))
        case .size: constraints.append(label.widthAnchor.constraint(equalToConstant: BookTableColumns.sizeWidth))
        case .date: constraints.append(label.widthAnchor.constraint(equalToConstant: BookTableColumns.dateWidth))
        case .genres: constraints.append(label.trailingAnchor.constraint(equalTo: trailingAnchor,
                                                                         constant: -BookTableColumns.rowInset))
        case .title: break
        }
        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(text: String) { label.stringValue = text }
}

final class SeriesHeaderCellView: NSTableCellView {
    let nameLabel = makeLabel()
    let countLabel = makeLabel()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.textColor = .labelColor
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        countLabel.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(nameLabel)
        addSubview(countLabel)
        textField = nameLabel
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: BookTableColumns.rowInset),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            countLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 4),
            countLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor,
                                                 constant: -BookTableColumns.rowInset),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(series: Series, count: Int) {
        nameLabel.stringValue = series.name
        countLabel.stringValue = "(\(count))"
    }
}

final class BooksRowView: NSTableRowView {
    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    override func drawBackground(in dirtyRect: NSRect) {
        // Групповая строка — заголовок серии: без системного фона и без hover.
        guard !isGroupRowStyle else { return }
        super.drawBackground(in: dirtyRect)
        if isHovered && !isSelected {
            NSColor.black.withAlphaComponent(0.03).setFill()
            bounds.fill()
        }
    }
}

final class BooksNSTableView: NSTableView {
    static let bookRowHeight: CGFloat = 24
    static let seriesHeaderHeight: CGFloat = 32

    /// Поднят на время `super.keyDown`: заголовок серии, предложенный стрелкой,
    /// перескакивается, а предложенный мышью — нет.
    private(set) var isHandlingKeyDown = false
    private(set) var reloadDataCount = 0

    var lastTypeSelectKey: Date?
    var now: () -> Date = Date.init
    var onSpaceToggle: (() -> Void)?
    var menuProvider: ((Int) -> NSMenu?)?
    private(set) var hoveredRow = -1
    private var hoverArea: NSTrackingArea?

    override func reloadData() {
        reloadDataCount += 1
        hoveredRow = -1
        super.reloadData()
    }

    override func keyDown(with event: NSEvent) {
        let commandKeys = event.modifierFlags.intersection([.command, .control, .option])
        if commandKeys.isEmpty, event.charactersIgnoringModifiers == " " {
            if spaceRoute(lastTypeSelectKey: lastTypeSelectKey, now: now()) == .toggleCheck {
                onSpaceToggle?()
                return
            }
        } else if commandKeys.isEmpty, Self.isPrintable(event.characters) {
            lastTypeSelectKey = now()
        }
        isHandlingKeyDown = true
        defer { isHandlingKeyDown = false }
        super.keyDown(with: event)
    }

    private static func isPrintable(_ characters: String?) -> Bool {
        guard let characters, !characters.isEmpty else { return false }
        return characters.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !(0xF700 ... 0xF8FF).contains($0.value)
        }
    }

    /// Без `super`: штатная реализация выставляет `clickedRow` и обводит строку.
    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHoveredRow(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHoveredRow(-1)
    }

    /// После прокрутки колёсиком `mouseMoved` не приходит — строка под курсором другая.
    func updateHoverFromMouse() {
        guard let window, window.isKeyWindow else { setHoveredRow(-1); return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHoveredRow(visibleRect.contains(point) ? row(at: point) : -1)
    }

    func setHoveredRow(_ row: Int) {
        guard row != hoveredRow else { return }
        if (0 ..< numberOfRows).contains(hoveredRow) {
            (rowView(atRow: hoveredRow, makeIfNecessary: false) as? BooksRowView)?.isHovered = false
        }
        hoveredRow = row
        if (0 ..< numberOfRows).contains(row) {
            (rowView(atRow: row, makeIfNecessary: false) as? BooksRowView)?.isHovered = true
        }
    }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is BookCheckbox { return true }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}

enum DateHeaderState: Equatable { case normal, active, disabled }
enum DatePress: Equatable { case open, close, ignore }

final class BooksHeaderCell: NSTableHeaderCell {
    let column: BookTableColumnID
    /// Верх подписи от верха шапки: 40pt строки заголовка + 2 = 42pt от верха панели, как в SwiftUI-шапке.
    static let labelTop: CGFloat = 2

    init(column: BookTableColumnID) {
        self.column = column
        super.init(textCell: column.headerTitle)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    static func contentRect(for column: BookTableColumnID, in frame: NSRect) -> NSRect {
        let s = BookTableColumns.spacing
        func fixed(_ width: CGFloat) -> NSRect {
            NSRect(x: frame.minX + s, y: frame.minY, width: width, height: frame.height)
        }
        switch column {
        case .title:
            let x = frame.minX + BookTableColumns.rowInset + BookTableColumns.checkboxWidth + s
            return NSRect(x: x, y: frame.minY, width: frame.maxX - x, height: frame.height)
        case .num: return fixed(BookTableColumns.numWidth)
        case .size: return fixed(BookTableColumns.sizeWidth)
        case .date: return fixed(BookTableColumns.dateWidth)
        case .genres:
            return NSRect(x: frame.minX + s, y: frame.minY,
                          width: frame.width - s - BookTableColumns.rowInset, height: frame.height)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        let header = controlView as? BooksHeaderView
        var color = NSColor.secondaryLabelColor
        if column == .date {
            switch header?.dateState ?? .normal {
            case .normal: break
            case .active: color = .controlAccentColor
            case .disabled: color = .tertiaryLabelColor
            }
        }
        let text = NSAttributedString(
            string: column.headerTitle.uppercased(),
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                         .kern: 0.6, .foregroundColor: color])
        let size = text.size()
        let content = Self.contentRect(for: column, in: cellFrame)
        let top = cellFrame.minY + Self.labelTop

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        if column == .date, header?.isDatePressed == true {
            NSGraphicsContext.current?.cgContext.setAlpha(0.5)
        }
        switch column {
        case .title, .genres:
            text.draw(at: NSPoint(x: content.minX, y: top))
        case .num, .size:
            text.draw(at: NSPoint(x: content.maxX - size.width, y: top))
        case .date:
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                    .applying(NSImage.SymbolConfiguration(paletteColors: [color])))
            let cs = chevron?.size ?? .zero
            let chevronX = content.maxX - cs.width
            text.draw(at: NSPoint(x: chevronX - 3 - size.width, y: top))
            chevron?.draw(in: NSRect(x: chevronX, y: top + (size.height - cs.height) / 2,
                                     width: cs.width, height: cs.height),
                          from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}

final class BooksHeaderView: NSTableHeaderView {
    static let height: CGFloat = 33
    var dateState: DateHeaderState = .disabled
    private(set) var isDatePressed = false
    var datePressAction: ((TimeInterval) -> DatePress)?
    var performDatePress: ((DatePress) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        if let tableView {
            for (index, column) in tableView.tableColumns.enumerated() where !column.isHidden {
                column.headerCell.draw(withFrame: headerRect(ofColumn: index), in: self)
            }
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.minX, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }

    /// Без `super`: у колонок нет сортировки и выбора, кликабельна только «Дата».
    override func mouseDown(with event: NSEvent) {
        guard let tableView else { return }
        let index = column(at: convert(event.locationInWindow, from: nil))
        guard index >= 0,
              tableView.tableColumns[index].identifier == BookTableColumnID.date.identifier,
              let action = datePressAction?(event.timestamp), action != .ignore
        else { return }
        let rect = headerRect(ofColumn: index)
        var inside = true
        setDatePressed(true)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            inside = rect.contains(convert(next.locationInWindow, from: nil))
            setDatePressed(inside)
            if next.type == .leftMouseUp { break }
        }
        setDatePressed(false)
        if inside { performDatePress?(action) }
    }

    private func setDatePressed(_ pressed: Bool) {
        guard pressed != isDatePressed else { return }
        isDatePressed = pressed
        needsDisplay = true
    }
}
