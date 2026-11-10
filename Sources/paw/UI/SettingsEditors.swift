import AppKit
import PawCore

/// The Settings window's rows for config collections: workspace presets, setups, rules, key
/// maps, modes, gestures and icon colours. Each item is a row of fields in a card; the card's
/// last row adds one. Adding, removing or renaming saves and lays the page out again.
extension SettingsController {
    func build(_ editor: SettingsEditor) {
        switch editor {
        case .presets(let lens): presets(lens)
        case .setups: setups()
        case .rules: rules()
        case .map(let lens, let key, let value, let check): addCard(map(lens, key: key, value: value, check: check))
        case .modes: modes()
        case .gestures: gestures()
        case .iconColors: iconColors()
        }
    }

    // MARK: - Presets

    private static func workspaceOrder(_ a: String, _ b: String) -> Bool { (Int(a) ?? .max, a) < (Int(b) ?? .max, b) }

    private func presets(_ lens: Lens<[String: WorkspacePreset]>) {
        let presets = lens.get(config)
        func update(_ name: String, rebuild: Bool = false, _ change: @escaping (inout WorkspacePreset) -> Void) {
            write(rebuild: rebuild) { c in
                var all = lens.get(c)
                guard var p = all[name] else { return }
                change(&p)
                all[name] = p
                lens.set(&c, all)
            }
        }
        for name in presets.keys.sorted(by: Self.workspaceOrder) {
            let preset = presets[name]!
            let card = Card()
            let title = label("Workspace \(name)")
            title.setContentHuggingPriority(.init(1), for: .horizontal)
            let layouts = [(value: "", label: "Default layout")] + LayoutKind.allCases.map { (value: $0.rawValue, label: $0.rawValue) }
            let layout = popup(layouts, selected: preset.layout?.rawValue ?? "", width: 130) { v in
                update(name) { $0.layout = LayoutKind(rawValue: v) }
            }
            let axis = popup([("horizontal", "Horizontal"), ("vertical", "Vertical")], selected: preset.axis.rawValue, width: 110) { v in
                update(name) { $0.axis = Axis(rawValue: v) ?? .horizontal }
            }
            let display = textField(preset.display ?? "", placeholder: "display", width: 80) { t in
                let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                update(name) { $0.display = v.isEmpty ? nil : v }
            }
            let remove = removeButton { [unowned self] in
                endEditing()
                write(rebuild: true) { c in
                    var all = lens.get(c)
                    all[name] = nil
                    lens.set(&c, all)
                }
            }
            card.add(lineStack([title, layout, axis, display, remove]))

            for (i, tile) in preset.tiles.enumerated() {
                let number = NSTextField(labelWithString: "\(i + 1)")
                number.font = Theme.meta
                number.textColor = Theme.mutedForeground
                number.widthAnchor.constraint(equalToConstant: 14).isActive = true
                let apps = textField(tile.apps.joined(separator: ", "), placeholder: "App, Other App") { t in
                    let v = Self.list(t.stringValue)
                    guard !v.isEmpty else { NSSound.beep(); t.stringValue = tile.apps.joined(separator: ", "); return }
                    update(name) { if $0.tiles.indices.contains(i) { $0.tiles[i].apps = v } }
                }
                let size = textField(tile.size.map(Self.format) ?? "", placeholder: "size", width: 48) { t in
                    let s = t.stringValue.trimmingCharacters(in: .whitespaces)
                    guard s.isEmpty || (Double(s) ?? 0) > 0 else { NSSound.beep(); t.stringValue = tile.size.map(Self.format) ?? ""; return }
                    update(name) { if $0.tiles.indices.contains(i) { $0.tiles[i].size = Double(s) } }
                }
                size.alignment = .right
                let titleField = textField(tile.title ?? "", placeholder: "title", width: 90) { t in
                    let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                    update(name) { if $0.tiles.indices.contains(i) { $0.tiles[i].title = v.isEmpty ? nil : v } }
                }
                let launch = textField(tile.launch ?? "", placeholder: "launch command") { t in
                    let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                    update(name) { if $0.tiles.indices.contains(i) { $0.tiles[i].launch = v.isEmpty ? nil : v } }
                }
                let remove = removeButton { [unowned self] in
                    endEditing()
                    update(name, rebuild: true) { if $0.tiles.indices.contains(i) { $0.tiles.remove(at: i) } }
                }
                let line = lineStack([number, apps, size, titleField, launch, remove])
                apps.widthAnchor.constraint(equalTo: launch.widthAnchor, multiplier: 1.3).isActive = true
                card.add(line)
            }

            let newApps = textField("", placeholder: "App, Other App")
            let add = {
                let apps = Self.list(newApps.stringValue)
                guard !apps.isEmpty else { NSSound.beep(); return }
                update(name, rebuild: true) { $0.tiles.append(.init(apps: apps)) }
            }
            returns[ObjectIdentifier(newApps)] = add
            card.add(lineStack([newApps, button("Add Tile", add)]))
            addCard(card)
        }
        addCard(addRow("Add a workspace", placeholder: "name") { [unowned self] name in
            guard lens.get(config)[name] == nil else { return false }
            write(rebuild: true) { c in
                var all = lens.get(c)
                all[name] = WorkspacePreset(layout: nil)
                lens.set(&c, all)
            }
            return true
        })
    }

    // MARK: - Setups

    private func setups() {
        for name in config.setups.keys.sorted() {
            let setup = config.setups[name]!
            addTitle("Setup · \(name)")
            let card = Card()
            let displays = textField(setup.displays.joined(separator: ", "), placeholder: "builtin, DELL", width: 240) { [unowned self] t in
                let v = Self.list(t.stringValue)
                write { $0.setups[name]?.displays = v }
            }
            card.add(rowStack([textColumn("Displays", "One entry per display, comma-separated."), displays]))
            let focus = textField(setup.focus, placeholder: "initiate.focus", width: 240) { [unowned self] t in
                let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                write { $0.setups[name]?.focus = v }
            }
            card.add(rowStack([textColumn("Then show", "Workspace to focus after switching; empty keeps initiate's."), focus]))
            card.add(rowStack([textColumn("Remove this setup", nil), button("Remove") { [unowned self] in
                endEditing()
                write(rebuild: true) { $0.setups[name] = nil }
            }]))
            addCard(card)
            presets(Lens(get: { $0.setups[name]?.workspaces ?? [:] }, set: { $0.setups[name]?.workspaces = $1 }))
        }
        addTitle("New setup")
        addCard(addRow("Add a setup", placeholder: "home, work…") { [unowned self] name in
            guard config.setups[name] == nil else { return false }
            write(rebuild: true) { $0.setups[name] = PawConfig.Setup(displays: ["builtin"]) }
            return true
        })
    }

    // MARK: - Rules

    private func rules() {
        let card = Card()
        func update(_ i: Int, _ change: @escaping (inout PawConfig.Rule) -> Void) {
            write { c in if c.rules.indices.contains(i) { change(&c.rules[i]) } }
        }
        func optional(_ t: NSTextField) -> String? {
            let v = t.stringValue.trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        for (i, rule) in config.rules.enumerated() {
            let app = textField(rule.app, placeholder: "app or /regex/") { t in
                let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                guard !v.isEmpty else { NSSound.beep(); t.stringValue = rule.app; return }
                update(i) { $0.app = v }
            }
            let float = checkbox("Float", rule.float == true) { on in update(i) { $0.float = on ? true : nil } }
            let ignore = checkbox("Ignore", rule.manage == false) { on in update(i) { $0.manage = on ? false : nil } }
            let remove = removeButton { [unowned self] in
                endEditing()
                write(rebuild: true) { c in if c.rules.indices.contains(i) { c.rules.remove(at: i) } }
            }
            let title = textField(rule.title ?? "", placeholder: "title") { t in update(i) { $0.title = optional(t) } }
            let unless = textField(rule.unlessTitle ?? "", placeholder: "unless title") { t in update(i) { $0.unlessTitle = optional(t) } }
            let workspace = textField(rule.workspace ?? "", placeholder: "workspace", width: 90) { t in update(i) { $0.workspace = optional(t) } }
            let top = lineStack([app, float, ignore, remove])
            let bottom = lineStack([title, unless, workspace])
            top.edgeInsets.bottom = 4
            bottom.edgeInsets.top = 0
            // Line the second row up under the app field.
            bottom.edgeInsets.right = 16 + 8 + remove.fittingSize.width
            title.widthAnchor.constraint(equalTo: unless.widthAnchor).isActive = true
            let both = NSStackView(views: [top, bottom])
            both.orientation = .vertical
            both.spacing = 0
            for line in [top, bottom] { line.widthAnchor.constraint(equalTo: both.widthAnchor).isActive = true }
            card.add(both)
        }
        let newApp = textField("", placeholder: "app or /regex/")
        let add = { [unowned self] in
            let app = newApp.stringValue.trimmingCharacters(in: .whitespaces)
            guard !app.isEmpty else { NSSound.beep(); return }
            write(rebuild: true) { $0.rules.append(.init(app: app)) }
        }
        returns[ObjectIdentifier(newApp)] = add
        card.add(lineStack([newApp, button("Add Rule", add)]))
        addCard(card)
    }

    // MARK: - Key maps

    /// Rows of key → value; a key is renamed by editing it.
    private func map(_ lens: Lens<[String: String]>, key keyName: String, value valueName: String,
                     check: SettingsEditor.MapCheck) -> Card {
        let card = Card()
        let map = lens.get(config)
        let validKey: (String) -> Bool = check == .bindings ? { KeySpec.parse($0) != nil } : { _ in true }
        let validValue: (String) -> Bool = check == .bindings ? { (try? Command.parseAll($0)) != nil } : { _ in true }
        func mark(_ t: NSTextField, _ ok: Bool) { t.textColor = ok ? Theme.foreground : Theme.destructive }
        for key in map.keys.sorted() {
            let keyField = textField(key, placeholder: keyName, width: 190) { [unowned self] t in
                let new = t.stringValue.trimmingCharacters(in: .whitespaces)
                guard new != key else { return }
                guard !new.isEmpty, lens.get(config)[new] == nil else { NSSound.beep(); t.stringValue = key; return }
                write(rebuild: true) { c in
                    var m = lens.get(c)
                    m[new] = m.removeValue(forKey: key)
                    lens.set(&c, m)
                }
            }
            mark(keyField, validKey(key))
            let valueField = textField(map[key] ?? "", placeholder: valueName) { [unowned self] t in
                let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                mark(t, validValue(v))
                write { c in
                    var m = lens.get(c)
                    m[key] = v
                    lens.set(&c, m)
                }
            }
            mark(valueField, validValue(map[key] ?? ""))
            let remove = removeButton { [unowned self] in
                endEditing()
                write(rebuild: true) { c in
                    var m = lens.get(c)
                    m[key] = nil
                    lens.set(&c, m)
                }
            }
            card.add(lineStack([keyField, valueField, remove]))
        }
        let newKey = textField("", placeholder: keyName, width: 190)
        let newValue = textField("", placeholder: valueName)
        let add = { [unowned self] in
            let k = newKey.stringValue.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty, lens.get(config)[k] == nil else { NSSound.beep(); return }
            let v = newValue.stringValue.trimmingCharacters(in: .whitespaces)
            write(rebuild: true) { c in
                var m = lens.get(c)
                m[k] = v
                lens.set(&c, m)
            }
        }
        returns[ObjectIdentifier(newKey)] = add
        returns[ObjectIdentifier(newValue)] = add
        card.add(lineStack([newKey, newValue, button("Add", add)]))
        return card
    }

    private func modes() {
        for name in config.modes.keys.sorted() {
            addTitle("Mode · \(name)")
            let card = map(Lens(get: { $0.modes[name] ?? [:] }, set: { $0.modes[name] = $1 }),
                           key: "keys", value: "command", check: .bindings)
            card.add(rowStack([textColumn("Remove this mode", "`mode \(name)` turns it on."), button("Remove") { [unowned self] in
                endEditing()
                write(rebuild: true) { $0.modes[name] = nil }
            }]))
            addCard(card)
        }
        addTitle("New mode")
        addCard(addRow("Add a mode", placeholder: "resize") { [unowned self] name in
            guard config.modes[name] == nil else { return false }
            write(rebuild: true) { $0.modes[name] = ["escape": "mode exit"] }
            return true
        })
    }

    // MARK: - Gestures

    private func gestures() {
        let card = Card()
        let buttons = SettingsCatalog.options(["middle", "back", "forward"])
        let directions = SettingsCatalog.options(["left", "right", "up", "down", "click"])
        let validCommand: (String) -> Bool = { (try? Command.parseAll($0)) != nil }
        func update(_ i: Int, _ change: @escaping (inout PawConfig.Gesture) -> Void) {
            write { c in if c.mouse.gestures.indices.contains(i) { change(&c.mouse.gestures[i]) } }
        }
        for (i, g) in config.mouse.gestures.enumerated() {
            let button = popup(buttons, selected: g.button, width: 100) { v in update(i) { $0.button = v } }
            let direction = popup(directions, selected: g.direction, width: 90) { v in update(i) { $0.direction = v } }
            let command = textField(g.command, placeholder: "command") { t in
                let v = t.stringValue.trimmingCharacters(in: .whitespaces)
                t.textColor = validCommand(v) ? Theme.foreground : Theme.destructive
                update(i) { $0.command = v }
            }
            command.textColor = validCommand(g.command) ? Theme.foreground : Theme.destructive
            let remove = removeButton { [unowned self] in
                endEditing()
                write(rebuild: true) { c in if c.mouse.gestures.indices.contains(i) { c.mouse.gestures.remove(at: i) } }
            }
            card.add(lineStack([button, direction, command, remove]))
        }
        var newButton = "middle", newDirection = "click"
        let buttonPopup = popup(buttons, selected: newButton, width: 100) { newButton = $0 }
        let directionPopup = popup(directions, selected: newDirection, width: 90) { newDirection = $0 }
        let newCommand = textField("", placeholder: "command")
        let add = { [unowned self] in
            let cmd = newCommand.stringValue.trimmingCharacters(in: .whitespaces)
            guard !cmd.isEmpty else { NSSound.beep(); return }
            write(rebuild: true) { $0.mouse.gestures.append(.init(button: newButton, direction: newDirection, command: cmd)) }
        }
        returns[ObjectIdentifier(newCommand)] = add
        card.add(lineStack([buttonPopup, directionPopup, newCommand, self.button("Add", add)]))
        addCard(card)
    }

    // MARK: - Icon colours

    private func iconColors() {
        let card = Card()
        let colors = config.icons.colors
        for app in colors.keys.sorted() {
            let name = textField(app, placeholder: "app") { [unowned self] t in
                let new = t.stringValue.trimmingCharacters(in: .whitespaces)
                guard new != app else { return }
                guard !new.isEmpty, config.icons.colors[new] == nil else { NSSound.beep(); t.stringValue = app; return }
                write(rebuild: true) { $0.icons.colors[new] = $0.icons.colors.removeValue(forKey: app) }
            }
            let (_, well) = colorWell(colors[app]!) { [unowned self] c in write { $0.icons.colors[app] = c } }
            let remove = removeButton { [unowned self] in
                endEditing()
                write(rebuild: true) { $0.icons.colors[app] = nil }
            }
            card.add(lineStack([name, well, remove]))
        }
        let newApp = textField("", placeholder: "app, e.g. Brave Browser")
        let add = { [unowned self] in
            let app = newApp.stringValue.trimmingCharacters(in: .whitespaces)
            guard !app.isEmpty, config.icons.colors[app] == nil else { NSSound.beep(); return }
            write(rebuild: true) { $0.icons.colors[app] = AppColors.shared.color(for: app, icons: $0.icons) ?? $0.appearance.colors.accent }
        }
        returns[ObjectIdentifier(newApp)] = add
        card.add(lineStack([newApp, button("Add", add)]))
        addCard(card)
    }

    // MARK: - Pieces

    /// A card row naming a new item: `add` returns false when the name is taken.
    private func addRow(_ title: String, placeholder: String, _ add: @escaping (String) -> Bool) -> Card {
        let card = Card()
        let name = textField("", placeholder: placeholder, width: 160)
        let run = {
            let n = name.stringValue.trimmingCharacters(in: .whitespaces)
            if n.isEmpty || !add(n) { NSSound.beep() }
        }
        returns[ObjectIdentifier(name)] = run
        let controls = NSStackView(views: [name, button("Add", run)])
        controls.spacing = 8
        card.add(rowStack([textColumn(title, nil), controls]))
        return card
    }
}
