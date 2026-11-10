import AppKit
import PawCore
import SwiftUI

/// The settings window: every config key, saved back to `~/.config/paw/config.json5` through
/// `ConfigTemplate.render`, so the file stays the commented source of truth people and agents
/// can read and edit. paw's file watcher applies a save at once.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(settings: Settings) {
        if let window {
            (window.contentViewController as? NSHostingController<SettingsView>)?.rootView.model.reload()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let model = SettingsModel(settings: settings)
        let host = NSHostingController(rootView: SettingsView(model: model))
        let w = NSWindow(contentViewController: host)
        w.title = "paw Settings"
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        w.setContentSize(NSSize(width: 820, height: 620))
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    let settings: Settings
    @Published var config: PawConfig { didSet { dirty = config != saved } }
    @Published private(set) var dirty = false
    @Published var status = ""
    private var saved: PawConfig

    init(settings: Settings) {
        self.settings = settings
        config = settings.config
        saved = settings.config
    }

    func reload() {
        settings.load(notify: false)
        saved = settings.config
        config = settings.config
        status = settings.error.map { "Config error: \($0)" } ?? ""
    }

    func save() {
        do {
            try ConfigTemplate.render(config).write(to: settings.url, atomically: true, encoding: .utf8)
            saved = config
            dirty = false
            status = "Saved \(settings.url.path)"
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }

    func openFile() { NSWorkspace.shared.open(settings.url) }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                GeneralTab(c: $model.config).tabItem { Text("General") }
                WorkspacesTab(c: $model.config).tabItem { Text("Workspaces") }
                RulesTab(c: $model.config).tabItem { Text("Rules") }
                KeysTab(c: $model.config).tabItem { Text("Keys") }
                LookTab(c: $model.config).tabItem { Text("Indicators") }
                HooksTab(c: $model.config).tabItem { Text("Hooks") }
            }
            .padding(12)
            Divider()
            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Button("Open config file") { model.openFile() }
                Button("Revert") { model.reload() }.disabled(!model.dirty)
                Button("Save") { model.save() }.keyboardShortcut("s").disabled(!model.dirty)
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 540)
    }
}

// MARK: - Tabs

private struct GeneralTab: View {
    @Binding var c: PawConfig
    var body: some View {
        Form {
            LayoutSection(c: $c)
            FocusSection(c: $c)
            AnimationSection(c: $c)
            InitiateSetWorkspaceSection(c: $c)
            Section { Toggle("Open at login", isOn: $c.openAtLogin) }
            Section("Updates") {
                Toggle("Check for new versions every day", isOn: $c.updates.check)
                Toggle("Install them without asking", isOn: $c.updates.automatic).disabled(!c.updates.check)
            }
        }
        .formStyle(.grouped)
    }
}

private struct LayoutSection: View {
    @Binding var c: PawConfig
    var body: some View {
        Section("Layout") {
        Picker("New workspaces", selection: $c.layout.`default`) {
            ForEach(LayoutKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Stepper("Workspaces from the start: \(c.layout.workspaces)", value: $c.layout.workspaces, in: 1...20)
        TextField("Unassigned apps go to workspace (empty: stay)", text: $c.layout.unassignedWorkspace)
        NumberField("Gap", value: $c.layout.gap)
        HStack {
            NumberField("Padding top", value: $c.layout.padding.top)
            NumberField("bottom", value: $c.layout.padding.bottom)
            NumberField("left", value: $c.layout.padding.left)
            NumberField("right", value: $c.layout.padding.right)
        }
        HStack {
            NumberField("Status bar top", value: $c.layout.barTop)
            NumberField("bottom", value: $c.layout.barBottom)
        }
    }
    }
}

private struct FocusSection: View {
    @Binding var c: PawConfig
    var body: some View {
        Section("Focus") {
        Toggle("Mouse follows focus", isOn: $c.focus.mouseFollowsFocus)
        Toggle("Focus follows mouse", isOn: $c.focus.focusFollowsMouse)
        Toggle("Stack next/previous wraps around", isOn: $c.focus.wrapStacks)
    }
    }
}

private struct AnimationSection: View {
    @Binding var c: PawConfig
    /// `$c.animation` would be Binding.animation(_:).
    private var anim: Binding<PawConfig.Animation> { Binding(get: { c.animation }, set: { c.animation = $0 }) }
    var body: some View {
        Section("Animation") {
        Toggle("Animate window moves", isOn: anim.enabled)
        NumberField("Duration (ms)", value: anim.durationMs)
        Picker("Curve", selection: anim.curve) {
            ForEach(Easing.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Size changes", selection: anim.resize) {
            Text("start (smooth)").tag("start")
            Text("animate").tag("animate")
            Text("end").tag("end")
        }
        Stepper("Animate at most \(c.animation.maxWindows) windows", value: anim.maxWindows, in: 1...50)
    }
    }
}

private struct InitiateSetWorkspaceSection: View {
    @Binding var c: PawConfig
    var body: some View {
        Section("Initiate (Set Workspace)") {
        TextField("Apps to open (comma separated; empty: every app in the presets)", text: list($c.initiate.apps))
        TextField("Focus afterwards", text: $c.initiate.focus)
        NumberField("Wait for windows (s)", value: $c.initiate.timeout)
    }
    }
}

/// Default presets plus one section per setup.
private struct WorkspacesTab: View {
    @Binding var c: PawConfig
    @State private var newSetup = ""

    var body: some View {
        Form {
            Section {
                Text("Apps in one tile stack (first on top). Tiles: `Brave Browser *2 | T3 Code (Beta)` (`*2` = twice the size). Display: builtin, external, main, secondary, a number or part of the name (DELL).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Default (no setup matches the displays)") {
                PresetsEditor(presets: $c.workspaces)
            }
            ForEach(c.setups.keys.sorted(), id: \.self) { name in
                Section {
                    TextField("Displays (comma separated)", text: list(setupBinding(name).displays))
                    TextField("Focus after switching", text: setupBinding(name).focus)
                    PresetsEditor(presets: setupBinding(name).workspaces)
                    Button("Remove setup \(name)", role: .destructive) { c.setups[name] = nil }
                } header: {
                    Text("Setup: \(name)")
                }
            }
            Section("New setup") {
                HStack {
                    TextField("Name (home, work…)", text: $newSetup)
                    Button("Add") {
                        let n = newSetup.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, c.setups[n] == nil else { return }
                        c.setups[n] = PawConfig.Setup(displays: ["builtin"])
                        newSetup = ""
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setupBinding(_ name: String) -> Binding<PawConfig.Setup> {
        Binding(get: { c.setups[name] ?? PawConfig.Setup() }, set: { c.setups[name] = $0 })
    }
}

private struct PresetsEditor: View {
    @Binding var presets: [String: WorkspacePreset]
    @State private var newName = ""

    var body: some View {
        ForEach(presets.keys.sorted { (Int($0) ?? .max, $0) < (Int($1) ?? .max, $1) }, id: \.self) { name in
            HStack {
                Text(name).font(.body.monospacedDigit()).frame(width: 28, alignment: .leading)
                Picker("", selection: binding(name).layout) {
                    Text("default").tag(LayoutKind?.none)
                    ForEach(LayoutKind.allCases, id: \.self) { Text($0.rawValue).tag(LayoutKind?.some($0)) }
                }
                .labelsHidden().frame(width: 90)
                TextField("display", text: optional(binding(name).display)).frame(width: 100)
                TextField("apps", text: binding(name).tilesText)
                Button { presets[name] = nil } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
            .labelsHidden()
            .multilineTextAlignment(.leading)
        }
        HStack {
            TextField("Workspace", text: $newName).frame(width: 90)
            Button("Add workspace") {
                let n = newName.trimmingCharacters(in: .whitespaces)
                guard !n.isEmpty, presets[n] == nil else { return }
                presets[n] = WorkspacePreset(layout: nil)
                newName = ""
            }
        }
        .labelsHidden()
    }

    private func binding(_ name: String) -> Binding<WorkspacePreset> {
        Binding(get: { presets[name] ?? WorkspacePreset(layout: nil) }, set: { presets[name] = $0 })
    }
}

private struct RulesTab: View {
    @Binding var c: PawConfig
    var body: some View {
        Form {
            Section {
                Text("app: a name or /regex/. Title and unless title: substring or /regex/. Workspace: where new windows of the app open.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Rules") {
                ForEach(c.rules.indices, id: \.self) { i in
                    HStack {
                        TextField("app", text: $c.rules[i].app).labelsHidden()
                        TextField("title", text: optional($c.rules[i].title)).labelsHidden().frame(width: 110)
                        TextField("unless title", text: optional($c.rules[i].unlessTitle)).labelsHidden().frame(width: 110)
                        TextField("workspace", text: optional($c.rules[i].workspace)).labelsHidden().frame(width: 70)
                        Toggle("float", isOn: flag($c.rules[i].float))
                        Toggle("ignore", isOn: Binding(get: { c.rules[i].manage == false },
                                                      set: { c.rules[i].manage = $0 ? false : nil }))
                        Button { c.rules.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                    .multilineTextAlignment(.leading)
                }
                Button("Add rule") { c.rules.append(.init(app: "")) }
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeysTab: View {
    @Binding var c: PawConfig
    var body: some View {
        Form {
            Section {
                Text("Keys: cmd ctrl alt shift fn hyper meh, lalt/ralt…, then a key name (left, return, a, 1) or 0x keycode. Commands are the same as `paw <command>`; chain with ;.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Bindings") { MapEditor(map: $c.bindings, keyLabel: "keys", valueLabel: "command") }
            ForEach(c.modes.keys.sorted(), id: \.self) { name in
                Section("Mode: \(name)") {
                    MapEditor(map: Binding(get: { c.modes[name] ?? [:] }, set: { c.modes[name] = $0 }),
                              keyLabel: "keys", valueLabel: "command")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct LookTab: View {
    @Binding var c: PawConfig
    var body: some View {
        Form {
            Section("Stack indicators") {
                Picker("Side", selection: $c.indicator.side) {
                    ForEach(IndicatorLayout.Side.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                HStack {
                    NumberField("Width", value: $c.indicator.width)
                    NumberField("Cell height", value: $c.indicator.cellHeight)
                    NumberField("Gap", value: $c.indicator.gap)
                    NumberField("Padding", value: $c.indicator.padding)
                }
                HStack {
                    NumberField("Offset x", value: $c.indicator.offsetX)
                    NumberField("Offset y", value: $c.indicator.offsetY)
                    NumberField("Unfocused opacity", value: $c.indicator.unfocusedOpacity)
                    NumberField("Fade (ms)", value: $c.indicator.fadeMs)
                }
                Picker("Titles", selection: $c.indicator.titles) {
                    Text("on hover").tag("hover")
                    Text("never").tag("never")
                }
                Toggle("Click an icon to focus its window", isOn: $c.indicator.clickToFocus)
                Toggle("Scroll to go through the stack", isOn: $c.indicator.scrollToCycle)
            }
            Section("Focus border") {
                Toggle("Line around the focused window", isOn: $c.border.enabled)
                ColorRow("Colour", $c.border.color)
                HStack {
                    NumberField("Width", value: $c.border.width)
                    NumberField("Radius", value: $c.border.radius)
                    NumberField("Offset", value: $c.border.offset)
                }
            }
            Section("Mouse, overview, HUD") {
                Toggle("Drop zones when dragging a tiled window", isOn: $c.mouse.dropZones)
                Toggle("Drag the gaps between tiles to resize", isOn: $c.mouse.seamHandles)
                Picker("Window pictures in the overview", selection: $c.overview.thumbnails) {
                    Text("when allowed").tag("auto")
                    Text("on (asks for Screen Recording)").tag("on")
                    Text("off").tag("off")
                }
                Toggle("Flash the workspace when switching", isOn: $c.hud.workspace)
            }
            Section("App icons") {
                Toggle("Each icon in the app's own colour", isOn: $c.icons.brandColors)
                TextField("Icon map (sketchybar app_icons.lua)", text: $c.icons.map)
                MapEditor(map: Binding(get: { c.icons.colors.mapValues(\.description) },
                                       set: { c.icons.colors = $0.compactMapValues(ARGB.parse) }),
                          keyLabel: "app", valueLabel: "colour (#RRGGBB)")
            }
            Section("Appearance") {
                TextField("Font", text: $c.appearance.font)
                TextField("App icon font", text: $c.appearance.appFont)
                HStack {
                    NumberField("Font size", value: $c.appearance.fontSize)
                    NumberField("Icon size", value: $c.appearance.appIconSize)
                    NumberField("Radius", value: $c.appearance.radius)
                    NumberField("Cell radius", value: $c.appearance.cellRadius)
                    NumberField("Border", value: $c.appearance.borderWidth)
                }
                Toggle("Shadow", isOn: $c.appearance.shadow)
                ColorRow("Island", $c.appearance.colors.island)
                ColorRow("Highlighted cell", $c.appearance.colors.islandHi)
                ColorRow("Border", $c.appearance.colors.border)
                ColorRow("Text", $c.appearance.colors.fg)
                ColorRow("Muted", $c.appearance.colors.muted)
                ColorRow("Dim", $c.appearance.colors.dim)
                ColorRow("Accent", $c.appearance.colors.accent)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HooksTab: View {
    @Binding var c: PawConfig
    var body: some View {
        Form {
            Section {
                Text("Shell commands paw runs on events, e.g. sketchybar --trigger paw_workspace_change. Variables: $PAW_WORKSPACE, $PAW_PREV_WORKSPACE, $PAW_APP, $PAW_WINDOW, $PAW_MODE, $PAW_DISPLAYS.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hooks") {
                TextField("Workspace changed", text: $c.hooks.workspaceChanged)
                TextField("Windows changed", text: $c.hooks.windowsChanged)
                TextField("Window focused", text: $c.hooks.windowFocused)
                TextField("Mode changed", text: $c.hooks.modeChanged)
                TextField("Displays changed", text: $c.hooks.displaysChanged)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Pieces

/// Rows of key → value text fields, with add and remove.
private struct MapEditor: View {
    @Binding var map: [String: String]
    let keyLabel: String
    let valueLabel: String
    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        ForEach(map.keys.sorted(), id: \.self) { key in
            HStack {
                Text(key).font(.body.monospaced()).frame(width: 200, alignment: .leading).textSelection(.enabled)
                TextField(valueLabel, text: Binding(get: { map[key] ?? "" }, set: { map[key] = $0 }))
                Button { map[key] = nil } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
            }
            .labelsHidden()
            .multilineTextAlignment(.leading)
        }
        HStack {
            TextField(keyLabel, text: $newKey).frame(width: 200)
            TextField(valueLabel, text: $newValue)
            Button("Add") {
                let k = newKey.trimmingCharacters(in: .whitespaces)
                guard !k.isEmpty else { return }
                map[k] = newValue
                newKey = ""
                newValue = ""
            }
        }
        .labelsHidden()
    }
}

private struct NumberField: View {
    let label: String
    @Binding var value: Double
    init(_ label: String, value: Binding<Double>) {
        self.label = label
        _value = value
    }
    var body: some View {
        TextField(label, value: $value, format: .number).frame(minWidth: 60)
    }
}

private struct ColorRow: View {
    let label: String
    @Binding var color: ARGB
    init(_ label: String, _ color: Binding<ARGB>) {
        self.label = label
        _color = color
    }
    var body: some View {
        ColorPicker(label, selection: Binding(
            get: { Color(nsColor: NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)) },
            set: { new in
                guard let c = NSColor(new).usingColorSpace(.sRGB) else { return }
                func b(_ x: CGFloat) -> UInt32 { UInt32((max(0, min(1, x)) * 255).rounded()) }
                color = ARGB(b(c.alphaComponent) << 24 | b(c.redComponent) << 16 | b(c.greenComponent) << 8 | b(c.blueComponent))
            }), supportsOpacity: true)
    }
}

/// A list of strings as one comma-separated text field.
private func list(_ b: Binding<[String]>) -> Binding<String> {
    Binding(get: { b.wrappedValue.joined(separator: ", ") },
            set: { b.wrappedValue = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } })
}

/// An optional string as a text field; empty means nil.
private func optional(_ b: Binding<String?>) -> Binding<String> {
    Binding(get: { b.wrappedValue ?? "" }, set: { b.wrappedValue = $0.isEmpty ? nil : $0 })
}

/// An optional flag as a toggle; off means nil.
private func flag(_ b: Binding<Bool?>) -> Binding<Bool> {
    Binding(get: { b.wrappedValue == true }, set: { b.wrappedValue = $0 ? true : nil })
}
