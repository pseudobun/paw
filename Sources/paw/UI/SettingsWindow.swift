import AppKit
import PawCore

/// Opens the one Settings window (`paw settings`, the menu bar's Settings…).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var controller: SettingsController?

    func show(settings: Settings) {
        let c = controller ?? SettingsController(settings: settings)
        controller = c
        c.show()
    }

    /// The config was read again (saved here, in an editor, or reloaded): show its values.
    func configDidChange() { controller?.configDidChange() }
}

/// The Settings window, laid out like hop's: categories on the left, grouped like the config;
/// the selected one's values on the right. Every change is written to `config.json5` at once
/// through `ConfigTemplate.render`, so the commented file stays the source of truth, and paw's
/// file watcher applies it like a saved edit.
final class SettingsWindow: NSWindow {
    static let size = NSSize(width: 880, height: 620)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = "paw Settings"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        standardWindowButton(.zoomButton)?.isEnabled = false
    }

    /// paw has no main menu, so the usual window and editing shortcuts are routed here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard mods.contains(.command), let c = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }
        let selector: Selector? = switch (c, mods) {
        case ("w", .command), (",", .command): #selector(performClose(_:))
        case ("m", .command): #selector(performMiniaturize(_:))
        case ("a", .command): #selector(NSText.selectAll(_:))
        case ("c", .command): #selector(NSText.copy(_:))
        case ("v", .command): #selector(NSText.paste(_:))
        case ("x", .command): #selector(NSText.cut(_:))
        case ("z", .command): Selector(("undo:"))
        case ("z", [.command, .shift]): Selector(("redo:"))
        case ("f", .command): #selector(SettingsController.focusSearch(_:))
        default: nil
        }
        if let selector, NSApp.sendAction(selector, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc closes, as in hop.
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

@MainActor
final class SettingsController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
    NSTextFieldDelegate, NSSearchFieldDelegate {
    let window = SettingsWindow()
    let settings: Settings
    /// What the file holds: the last config read, plus changes written since.
    private(set) var config: PawConfig

    private var pageID = SettingsCatalog.general.id
    private var filter = ""
    private var previousApp: NSRunningApplication?

    private enum SidebarRow {
        case header(String)
        case page(SettingsPage)
    }

    private var sidebarRows: [SidebarRow] = []
    private let sidebar = NSTableView()
    private let search = NSSearchField()
    private let contentScroll = NSScrollView()
    let contentStack = NSStackView()

    /// Controls on the current page, refreshed when the config changes.
    private var bindings: [(get: (PawConfig) -> Any, view: NSView, set: (Any) -> Void)] = []
    private var gated: [NSView] = []
    /// Text fields: what ending an edit does, and what ↵ does in an "add" row.
    var commits: [ObjectIdentifier: (NSTextField) -> Void] = [:]
    var returns: [ObjectIdentifier: () -> Void] = [:]
    private var handlers: [Handler] = []
    private var shown: (error: String?, warnings: [String]) = (nil, [])
    private var colorWrite: DispatchWorkItem?

    init(settings: Settings) {
        self.settings = settings
        config = settings.config
        super.init()
        Theme.registerFonts()
        build()
    }

    func show() {
        if !window.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            config = settings.config
            window.center()
        }
        reloadSidebar()
        showPage()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func configDidChange() {
        guard window.isVisible else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // The echo of a change written here only refreshes, so a control in use stays.
            let same = settings.config == config && settings.error == shown.error && settings.warnings == shown.warnings
            config = settings.config
            if same || editingText { refreshValues() } else { showPage(keepScroll: true) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        window.makeFirstResponder(nil) // commits a field being edited
        NSColorPanel.shared.orderOut(nil)
        if let app = previousApp, !app.isTerminated { app.activate() }
        previousApp = nil
    }

    // MARK: - Layout

    private static let sidebarWidth: CGFloat = 224
    private static let contentWidth: CGFloat = SettingsWindow.size.width - sidebarWidth
    private static let pad: CGFloat = 32
    /// Width of a row's text column next to its control.
    nonisolated static let textWidth: CGFloat = 260
    /// Width inside a card's 16 pt row padding.
    static let rowWidth: CGFloat = contentWidth - 2 * pad - 32

    private func build() {
        window.delegate = self
        window.appearance = Theme.appearance
        window.backgroundColor = Theme.background
        NSColorPanel.shared.showsAlpha = true

        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = Theme.background.cgColor
        window.contentView = root

        // Sidebar
        let side = NSView()
        side.wantsLayer = true
        side.layer?.backgroundColor = Theme.card.cgColor
        side.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(side)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = Theme.border.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        search.placeholderString = "Search settings"
        search.font = Theme.sans(13)
        search.focusRingType = .none
        search.delegate = self
        search.sendsSearchStringImmediately = true
        search.target = self
        search.action = #selector(searchChanged)
        search.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(search)

        sidebar.addTableColumn(NSTableColumn(identifier: .init("page")))
        sidebar.headerView = nil
        sidebar.backgroundColor = .clear
        sidebar.selectionHighlightStyle = .none
        sidebar.intercellSpacing = NSSize(width: 0, height: 2)
        sidebar.focusRingType = .none
        sidebar.style = .plain
        sidebar.dataSource = self
        sidebar.delegate = self
        let sideScroll = NSScrollView()
        sideScroll.documentView = sidebar
        sideScroll.drawsBackground = false
        sideScroll.hasVerticalScroller = true
        sideScroll.autohidesScrollers = true
        sideScroll.scrollerStyle = .overlay
        sideScroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        sideScroll.translatesAutoresizingMaskIntoConstraints = false
        side.addSubview(sideScroll)

        // Content
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.edgeInsets = NSEdgeInsets(top: 46, left: Self.pad, bottom: Self.pad, right: Self.pad)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.setHuggingPriority(.required, for: .vertical)
        doc.addSubview(contentStack)
        contentScroll.documentView = doc
        contentScroll.drawsBackground = false
        contentScroll.hasVerticalScroller = true
        contentScroll.autohidesScrollers = true
        contentScroll.scrollerStyle = .overlay
        contentScroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentScroll)

        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            side.topAnchor.constraint(equalTo: root.topAnchor),
            side.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            side.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
            divider.leadingAnchor.constraint(equalTo: side.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            search.topAnchor.constraint(equalTo: side.topAnchor, constant: 44),
            search.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 12),
            search.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -12),
            sideScroll.topAnchor.constraint(equalTo: search.bottomAnchor, constant: 10),
            sideScroll.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 8),
            sideScroll.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -8),
            sideScroll.bottomAnchor.constraint(equalTo: side.bottomAnchor),

            contentScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            contentScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentScroll.topAnchor.constraint(equalTo: root.topAnchor),
            contentScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: contentScroll.contentView.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: doc.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])
    }

    // MARK: - Sidebar

    @objc func focusSearch(_ sender: Any?) { window.makeFirstResponder(search) }

    @objc private func searchChanged() {
        filter = search.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        reloadSidebar()
        // Follow the filter to the first match when the open page dropped out.
        if !visiblePages.contains(where: { $0.id == pageID }), let first = visiblePages.first {
            pageID = first.id
            showPage()
        }
        selectCurrentRow()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === search {
            switch selector {
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertNewline(_:)):
                window.makeFirstResponder(sidebar)
                return true
            case #selector(NSResponder.cancelOperation(_:)) where !search.stringValue.isEmpty:
                search.stringValue = ""
                searchChanged()
                return true
            default:
                return false
            }
        }
        if selector == #selector(NSResponder.insertNewline(_:)), let add = returns[ObjectIdentifier(control)] {
            add()
            return true
        }
        return false
    }

    private var visiblePages: [SettingsPage] {
        sidebarRows.compactMap { if case .page(let p) = $0 { p } else { nil } }
    }

    private func reloadSidebar() {
        let words = filter.split(separator: " ")
        sidebarRows = []
        for group in SettingsCatalog.groups {
            let pages = group.pages.filter { page in words.allSatisfy { page.haystack.contains($0) } }
            guard !pages.isEmpty else { continue }
            sidebarRows.append(.header(group.title))
            sidebarRows += pages.map { .page($0) }
        }
        sidebar.reloadData()
        selectCurrentRow()
    }

    private func selectCurrentRow() {
        guard let row = sidebarRows.firstIndex(where: { if case .page(let p) = $0 { p.id == pageID } else { false } }) else {
            sidebar.deselectAll(nil)
            return
        }
        sidebar.selectRowIndexes([row], byExtendingSelection: false)
        sidebar.scrollRowToVisible(row)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { sidebarRows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = sidebarRows[row] { return row == 0 ? 22 : 34 }
        return 30
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .page = sidebarRows[row] { return true }
        return false
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { SidebarRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSView()
        switch sidebarRows[row] {
        case .header(let title):
            let label = NSTextField(labelWithAttributedString: Theme.labelString(title))
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
            ])
        case .page(let page):
            let icon = NSImageView(image: Theme.tile(page.symbol, page.color, size: 20))
            let label = NSTextField(labelWithString: page.title)
            label.font = Theme.sans(13.5, page.id == pageID ? 500 : 400)
            label.textColor = Theme.foreground
            label.lineBreakMode = .byTruncatingTail
            for v in [icon, label] as [NSView] {
                v.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(v)
            }
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebar.selectedRow
        guard row >= 0, row < sidebarRows.count, case .page(let page) = sidebarRows[row], page.id != pageID else { return }
        window.makeFirstResponder(sidebar) // commits a field being edited on the old page
        pageID = page.id
        sidebar.reloadData(forRowIndexes: IndexSet(integersIn: 0..<sidebarRows.count), columnIndexes: [0])
        showPage()
    }

    // MARK: - Page

    private var page: SettingsPage {
        SettingsCatalog.pages.first { $0.id == pageID } ?? SettingsCatalog.general
    }

    private var editingText: Bool {
        guard let editor = window.firstResponder as? NSTextView else { return false }
        return (editor.delegate as? NSView)?.isDescendant(of: contentStack) == true
    }

    /// Builds the current page again, e.g. after rows were added or removed.
    func showPage(keepScroll: Bool = false) {
        let scroll = contentScroll.contentView.bounds.origin
        bindings = []
        gated = []
        commits = [:]
        returns = [:]
        handlers = []
        contentStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let page = page
        shown = (settings.error, settings.warnings)

        contentStack.addArrangedSubview(header(page))
        contentStack.setCustomSpacing(22, after: contentStack.arrangedSubviews.last!)
        if let error = settings.error {
            addBanner(errorBanner(error))
        } else if !settings.warnings.isEmpty {
            addBanner(warningsBanner(settings.warnings))
        }
        let banners = contentStack.arrangedSubviews.count
        for section in page.sections {
            if let title = section.title { addTitle(title) }
            switch section.content {
            case .rows(let rows):
                let card = Card()
                for row in rows {
                    switch row {
                    case .field(let field): card.add(fieldRow(field, page: page))
                    case .info(let info): card.add(infoRow(info))
                    case .note(let note): card.add(noteRow(note))
                    }
                }
                addCard(card)
            case .editor(let editor):
                build(editor)
            }
        }
        if settings.error != nil {
            // Writing now would replace the broken file with the last config that read.
            for view in contentStack.arrangedSubviews.dropFirst(banners) { Self.lock(view, on: false) }
        } else {
            refreshGate()
        }
        contentStack.layoutSubtreeIfNeeded()
        contentScroll.contentView.scroll(to: keepScroll ? scroll : .zero)
        contentScroll.reflectScrolledClipView(contentScroll.contentView)
    }

    func addTitle(_ title: String) {
        let label = NSTextField(labelWithAttributedString: Theme.labelString(title))
        contentStack.addArrangedSubview(label)
        contentStack.setCustomSpacing(8, after: label)
    }

    func addCard(_ card: NSView) {
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -2 * Self.pad).isActive = true
        contentStack.setCustomSpacing(24, after: card)
    }

    private func addBanner(_ banner: NSView) {
        contentStack.addArrangedSubview(banner)
        banner.widthAnchor.constraint(equalTo: contentStack.widthAnchor, constant: -2 * Self.pad).isActive = true
        contentStack.setCustomSpacing(22, after: banner)
    }

    private func header(_ page: SettingsPage) -> NSView {
        let icon = NSImageView(image: Theme.tile(page.symbol, page.color, size: 36))
        icon.widthAnchor.constraint(equalToConstant: 36).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let title = NSTextField(labelWithString: page.title)
        title.font = Theme.sans(22, 500)
        title.textColor = Theme.foreground
        let subtitle = NSTextField(labelWithString: page.subtitle)
        subtitle.font = Theme.meta
        subtitle.textColor = Theme.mutedForeground
        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3
        let row = NSStackView(views: [icon, text])
        row.spacing = 14
        row.alignment = .centerY
        return row
    }

    private func errorBanner(_ error: String) -> NSView {
        let card = Card(tint: Theme.destructive)
        let text = label("The config can't be read: \(error). paw keeps using the last config that read; fix the file to change settings again.",
                         help: true, width: Self.rowWidth - 140)
        text.textColor = Theme.foreground
        card.add(rowStack([text, button("Open Config") { [unowned self] in perform(.openConfig) }]))
        return card
    }

    private func warningsBanner(_ warnings: [String]) -> NSView {
        let card = Card(tint: Theme.warn)
        let shown = warnings.prefix(6).joined(separator: "\n") + (warnings.count > 6 ? "\n…and \(warnings.count - 6) more" : "")
        let text = label(shown, help: true, width: Self.rowWidth - 140)
        text.textColor = Theme.foreground
        card.add(rowStack([text, button("Open Config") { [unowned self] in perform(.openConfig) }]))
        return card
    }

    // MARK: Rows

    func label(_ text: String, help: Bool = false, width: CGFloat = textWidth) -> NSTextField {
        let l = help ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        l.font = help ? Theme.sans(12) : Theme.sans(13.5, 500)
        l.textColor = help ? Theme.mutedForeground : Theme.foreground
        l.isSelectable = false
        if help {
            // Measured and drawn at the same width, so a wrapped help text gets its full height.
            l.preferredMaxLayoutWidth = width
            l.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return l
    }

    func textColumn(_ title: String, _ help: String?, width: CGFloat = textWidth) -> NSStackView {
        var views: [NSView] = [label(title)]
        if let help, !help.isEmpty { views.append(label(help, help: true, width: width)) }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }

    /// Text on the left, pinned to the row's padding so it sets the height; the control
    /// on the right, centred.
    func rowStack(_ views: [NSView]) -> NSView {
        let row = NSView()
        let text = views[0], control = views[1]
        for v in [text, control] {
            v.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(v)
        }
        text.setContentHuggingPriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            text.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
            text.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: text.trailingAnchor, constant: 16),
            control.topAnchor.constraint(greaterThanOrEqualTo: row.topAnchor, constant: 8),
        ])
        return row
    }

    /// Controls side by side across a card row, as in the collection editors; a view with low
    /// hugging (a text field) takes the room left.
    func lineStack(_ views: [NSView]) -> NSStackView {
        let line = NSStackView(views: views)
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 8
        line.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        return line
    }

    private func infoRow(_ info: SettingsInfo) -> NSView {
        let action = info.action
        return rowStack([textColumn(info.label, info.help, width: Self.textWidth + 100),
                         button(info.button) { [unowned self] in perform(action) }])
    }

    private func noteRow(_ text: String) -> NSView {
        let note = label(text, help: true, width: Self.rowWidth)
        let column = NSStackView(views: [note])
        column.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        return column
    }

    private func fieldRow(_ field: SettingsField, page: SettingsPage) -> NSView {
        let value = field.value.get(config)
        let row: NSView
        switch field.kind {
        case .toggle:
            let toggle = NSSwitch()
            toggle.controlSize = .small
            toggle.state = (value as? Bool) == true ? .on : .off
            on(toggle) { [unowned self] in
                write(field, toggle.state == .on)
                refreshGate()
            }
            bind(field, toggle) { toggle.state = ($0 as? Bool) == true ? .on : .off }
            row = rowStack([textColumn(field.label, field.help), toggle])
        case .text(let placeholder):
            let text = textField(value as? String ?? "", placeholder: placeholder, width: 240) { [unowned self] t in
                write(field, t.stringValue.trimmingCharacters(in: .whitespaces))
            }
            bind(field, text) { text.stringValue = $0 as? String ?? "" }
            row = rowStack([textColumn(field.label, field.help), text])
        case .wide(let placeholder):
            let text = textField(value as? String ?? "", placeholder: placeholder) { [unowned self] t in
                write(field, t.stringValue.trimmingCharacters(in: .whitespaces))
            }
            bind(field, text) { text.stringValue = $0 as? String ?? "" }
            let column = NSStackView(views: [textColumn(field.label, field.help, width: Self.rowWidth), text])
            column.orientation = .vertical
            column.alignment = .leading
            column.spacing = 10
            column.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 14, right: 16)
            text.widthAnchor.constraint(equalTo: column.widthAnchor, constant: -32).isActive = true
            row = column
        case .list(let placeholder):
            let text = textField((value as? [String] ?? []).joined(separator: ", "), placeholder: placeholder, width: 240) { [unowned self] t in
                write(field, Self.list(t.stringValue))
            }
            bind(field, text) { text.stringValue = ($0 as? [String] ?? []).joined(separator: ", ") }
            row = rowStack([textColumn(field.label, field.help), text])
        case .number(let min, let max, let step, let unit):
            let stepper = NSStepper()
            let text = textField(Self.format(value as? Double ?? 0), placeholder: "", width: 72) { [unowned self] t in
                let current = field.value.get(config) as? Double ?? 0
                guard let n = Double(t.stringValue.trimmingCharacters(in: .whitespaces)), (min...max).contains(n) else {
                    NSSound.beep()
                    t.stringValue = Self.format(current)
                    return
                }
                stepper.doubleValue = n
                write(field, n)
            }
            text.alignment = .right
            stepper.minValue = min
            stepper.maxValue = max
            stepper.increment = step
            stepper.valueWraps = false
            stepper.doubleValue = value as? Double ?? 0
            stepper.controlSize = .small
            on(stepper) { [unowned self] in
                let n = (stepper.doubleValue / step).rounded() * step
                text.stringValue = Self.format(n)
                write(field, n)
            }
            bind(field, text) {
                text.stringValue = Self.format($0 as? Double ?? 0)
                stepper.doubleValue = $0 as? Double ?? 0
            }
            var controls: [NSView] = [text, stepper]
            if !unit.isEmpty {
                let u = NSTextField(labelWithString: unit)
                u.font = Theme.meta
                u.textColor = Theme.mutedForeground
                controls.append(u)
            }
            let group = NSStackView(views: controls)
            group.spacing = 6
            row = rowStack([textColumn(field.label, field.help), group])
        case .choice(let options):
            let popup = self.popup(options, selected: value as? String ?? "") { [unowned self] v in write(field, v) }
            bind(field, popup) { Self.select($0 as? String ?? "", in: popup) }
            row = rowStack([textColumn(field.label, field.help), popup])
        case .color:
            let (well, group) = colorWell(value as? ARGB ?? ARGB(0)) { [unowned self] c in write(field, c) }
            bind(field, group) { value in
                guard let c = value as? ARGB, !well.isActive else { return }
                well.color = c.ns
                (group.views.last as? NSTextField)?.stringValue = c.description
            }
            row = rowStack([textColumn(field.label, field.help), group])
        }
        if let gate = page.gate, field.key != gate { gated.append(row) }
        return row
    }

    private func bind(_ field: SettingsField, _ view: NSView, _ set: @escaping (Any) -> Void) {
        bindings.append((field.value.get, view, set))
    }

    // MARK: Controls

    /// An editable mono field; `commit` runs when an edit ends (↵, ⇥ or a click elsewhere).
    func textField(_ value: String, placeholder: String, width: CGFloat? = nil,
                   commit: ((NSTextField) -> Void)? = nil) -> NSTextField {
        let text = NSTextField(string: value)
        text.placeholderString = placeholder
        text.font = Theme.mono(12.5)
        text.textColor = Theme.foreground
        text.isBordered = true
        text.isBezeled = true
        text.bezelStyle = .roundedBezel
        text.focusRingType = .default
        text.lineBreakMode = .byTruncatingTail
        text.usesSingleLineMode = true
        text.cell?.isScrollable = true
        text.delegate = self
        if let width {
            text.widthAnchor.constraint(equalToConstant: width).isActive = true
        } else {
            text.setContentHuggingPriority(.init(1), for: .horizontal)
            text.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        }
        if let commit { commits[ObjectIdentifier(text)] = commit }
        return text
    }

    func button(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.bezelStyle = .push
        b.controlSize = .regular
        b.font = Theme.sans(13)
        on(b, action)
        return b
    }

    /// The borderless ⓧ that removes a row.
    func removeButton(_ action: @escaping () -> Void) -> NSButton {
        let b = NSButton()
        b.isBordered = false
        b.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")
        b.contentTintColor = Theme.mutedForeground
        b.toolTip = "Remove"
        b.widthAnchor.constraint(equalToConstant: 16).isActive = true
        on(b, action)
        return b
    }

    func checkbox(_ title: String, _ value: Bool, _ action: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.font = Theme.sans(12.5)
        b.state = value ? .on : .off
        on(b) { action(b.state == .on) }
        return b
    }

    func popup(_ options: [(value: String, label: String)], selected: String, width: CGFloat? = nil,
               _ action: @escaping (String) -> Void) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.font = Theme.sans(13)
        for option in options {
            popup.addItem(withTitle: option.label)
            popup.lastItem?.representedObject = option.value
        }
        Self.select(selected, in: popup)
        if let width { popup.widthAnchor.constraint(equalToConstant: width).isActive = true }
        on(popup) {
            if let v = popup.selectedItem?.representedObject as? String { action(v) }
        }
        return popup
    }

    /// Selects `value`, adding it when it isn't one of the options (a value typed in the file).
    static func select(_ value: String, in popup: NSPopUpButton) {
        if let i = popup.itemArray.firstIndex(where: { $0.representedObject as? String == value }) {
            popup.selectItem(at: i)
        } else {
            popup.addItem(withTitle: value)
            popup.lastItem?.representedObject = value
            popup.select(popup.lastItem)
        }
    }

    /// A colour well and its 0xAARRGGBB value; picking writes once the colour rests.
    func colorWell(_ value: ARGB, _ action: @escaping (ARGB) -> Void) -> (NSColorWell, NSStackView) {
        let well = NSColorWell(style: .default)
        well.color = value.ns
        well.widthAnchor.constraint(equalToConstant: 44).isActive = true
        well.heightAnchor.constraint(equalToConstant: 22).isActive = true
        let hex = NSTextField(labelWithString: value.description)
        hex.font = Theme.meta
        hex.textColor = Theme.mutedForeground
        on(well) { [unowned self] in
            let c = ARGB(well.color)
            hex.stringValue = c.description
            colorWrite?.cancel()
            let work = DispatchWorkItem { action(c) }
            colorWrite = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
        let group = NSStackView(views: [well, hex])
        group.spacing = 8
        return (well, group)
    }

    func on(_ control: NSControl, _ action: @escaping () -> Void) {
        let handler = Handler(action)
        handlers.append(handler)
        control.target = handler
        control.action = #selector(Handler.fire)
    }

    private func refreshValues() {
        let editor = window.firstResponder as? NSTextView
        for binding in bindings {
            // Leave the field being typed in alone.
            if let editor, editor.delegate === binding.view as AnyObject { continue }
            binding.set(binding.get(config))
        }
        refreshGate()
    }

    private func refreshGate() {
        guard settings.error == nil, let gate = page.gate, let field = page.fields.first(where: { $0.key == gate }) else { return }
        let on = field.value.get(config) as? Bool ?? true
        for view in gated { Self.lock(view, on: on) }
    }

    private static func lock(_ view: NSView, on: Bool) {
        view.alphaValue = on ? 1 : 0.45
        setEnabled(on, in: view)
    }

    private static func setEnabled(_ on: Bool, in view: NSView) {
        if let control = view as? NSControl { control.isEnabled = on }
        for sub in view.subviews { setEnabled(on, in: sub) }
    }

    // MARK: - Writing

    private func write(_ field: SettingsField, _ value: Any) {
        write { field.value.set(&$0, value) }
    }

    /// Applies `change` to the config and saves the file at once; `rebuild` lays the page out
    /// again afterwards (rows added, removed or reordered).
    func write(rebuild: Bool = false, _ change: (inout PawConfig) -> Void) {
        guard settings.error == nil else { NSSound.beep(); return }
        var c = config
        change(&c)
        guard c != config else { return }
        do {
            try ConfigTemplate.render(c).write(to: settings.url, atomically: true, encoding: .utf8)
            config = c
        } catch {
            NSAlert(error: error).beginSheetModal(for: window)
            return
        }
        if rebuild { DispatchQueue.main.async { [weak self] in self?.showPage(keepScroll: true) } }
    }

    /// Ends the edit in progress (saving it) before rows move.
    func endEditing() { window.makeFirstResponder(nil) }

    private func perform(_ action: SettingsAction) {
        switch action {
        case .openConfig: NSWorkspace.shared.open(settings.url)
        case .revealConfig: NSWorkspace.shared.activateFileViewerSelecting([settings.url])
        case .reloadConfig: settings.load()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let text = obj.object as? NSTextField, let commit = commits[ObjectIdentifier(text)] else { return }
        commit(text)
    }

    static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func format(_ n: Double) -> String {
        n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(format: "%g", n)
    }
}

extension ARGB {
    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? .black
        func byte(_ x: CGFloat) -> UInt32 { UInt32((max(0, min(1, x)) * 255).rounded()) }
        self.init(byte(c.alphaComponent) << 24 | byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent))
    }
}

// MARK: - Small views

/// Target of a control's action: runs a closure.
@MainActor
private final class Handler: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A rounded card holding rows separated by hairlines.
final class Card: NSView {
    let stack = NSStackView()

    init(tint: NSColor? = nil) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = (tint?.withAlphaComponent(0.10) ?? Theme.card).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = (tint?.withAlphaComponent(0.35) ?? Theme.border).cgColor
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.setHuggingPriority(.required, for: .vertical)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Adds a full-width row, under a hairline when it isn't the first.
    func add(_ row: NSView) {
        if !stack.arrangedSubviews.isEmpty { stack.addArrangedSubview(Hairline()) }
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}

private final class Hairline: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.border.cgColor
        heightAnchor.constraint(equalToConstant: 1).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let stack = superview as? NSStackView { widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
    }
}

private final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {}

    override func drawBackground(in dirtyRect: NSRect) {
        guard isSelected else { return }
        Theme.wash(0.09).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    override var isSelected: Bool { didSet { needsDisplay = true } }
}
