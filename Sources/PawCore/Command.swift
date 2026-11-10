import Foundation

/// What a binding or `paw <command>` does. Several commands chain with ";".
public enum Command: Equatable, Sendable {
    public enum FocusTarget: Equatable, Sendable { case dir(Direction), stackNext, stackPrev, stackFirst, stackLast, back, forward }
    public enum WorkspaceTarget: Equatable, Sendable { case name(String), next, prev, last }
    public enum DisplayTarget: Equatable, Sendable { case dir(Direction), next, prev, index(Int) }
    public enum Toggle: String, Sendable { case float, zoom, split }
    public struct Grid: Equatable, Sendable {
        public var rows, cols, x, y, w, h: Int
    }

    case focus(FocusTarget)
    case swap(Direction)
    /// Moves the focused window one place through its stack (negative: towards the top).
    case swapStack(Int)
    case warp(Direction)
    case stack(Direction)
    case unstack(all: Bool)
    case layout(LayoutKind)
    case toggle(Toggle)
    case balance
    case rotate(Int)
    case resize(Direction, Double)
    case grid(Grid)
    case workspace(WorkspaceTarget)
    case workspaceNew
    case workspaceClose
    case moveTo(WorkspaceTarget, follow: Bool)
    case focusDisplay(DisplayTarget)
    case moveToDisplay(DisplayTarget, follow: Bool)
    /// Moves the focused workspace's windows, tiles and layout to another workspace (its
    /// contents trade places with that one's); next/prev step through the bar's order, which
    /// crosses to the next display at the end of one.
    case moveWorkspace(WorkspaceTarget)
    /// Moves the focused workspace, windows and all, to another display (it shows there).
    case moveWorkspaceToDisplay(DisplayTarget)
    case arrange(String?)
    /// Open the preset apps and arrange everything; with a name, use that setup whatever
    /// displays are connected.
    case initiate(String?)
    /// Turns a mode on (again: off); nil turns any mode off.
    case mode(String?)
    case exec(String)
    /// Undo / redo the last layout change of the focused workspace.
    case undo
    case redo
    /// Focus the window that best matches (app or title).
    case find(String)
    /// The overview of every workspace and window (again: close it).
    case overview
    /// Through the tree: in (true) shows the branch holding the focused window, one level
    /// deeper each time; out goes back up.
    case zoom(in: Bool)
    case retile
    case recover
    case reload

    public static func parseAll(_ text: String) throws -> [Command] {
        try text.split(separator: ";").map { try parse(String($0)) }
    }

    public static func parse(_ text: String) throws -> Command {
        let raw = text.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("exec ") { return .exec(String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        if raw.hasPrefix("find ") {
            let q = String(raw.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { throw ConfigProblem("“\(raw)”: find <app or title>") }
            return .find(q)
        }
        var words = raw.split(separator: " ").map(String.init)
        let follow = words.contains("--follow")
        words.removeAll { $0 == "--follow" }
        guard let verb = words.first?.lowercased() else { throw ConfigProblem("empty command") }
        let args = Array(words.dropFirst())
        func arg(_ i: Int) throws -> String {
            guard args.indices.contains(i) else { throw ConfigProblem("“\(raw)”: missing argument") }
            return args[i]
        }
        func dir(_ i: Int) throws -> Direction {
            let s = try arg(i)
            guard let d = Direction(s) else { throw ConfigProblem("“\(raw)”: “\(s)” is not west, east, north or south") }
            return d
        }
        func workspace(_ i: Int) throws -> WorkspaceTarget {
            switch try arg(i).lowercased() {
            case "next": return .next
            case "prev", "previous": return .prev
            case "last", "back": return .last
            default: return .name(args[i])
            }
        }
        func display(_ i: Int) throws -> DisplayTarget {
            let s = try arg(i).lowercased()
            if let d = Direction(s) { return .dir(d) }
            if s == "next" { return .next }
            if s == "prev" || s == "previous" { return .prev }
            if let n = Int(s), n > 0 { return .index(n) }
            throw ConfigProblem("“\(raw)”: “\(s)” is not a display")
        }
        switch verb {
        case "focus":
            switch try arg(0).lowercased() {
            case "stack.next", "next": return .focus(.stackNext)
            case "stack.prev", "prev": return .focus(.stackPrev)
            case "stack.first": return .focus(.stackFirst)
            case "stack.last": return .focus(.stackLast)
            case "back", "previous": return .focus(.back)
            case "forward": return .focus(.forward)
            default: return .focus(.dir(try dir(0)))
            }
        case "swap":
            switch try arg(0).lowercased() {
            case "stack.next", "next": return .swapStack(1)
            case "stack.prev", "prev": return .swapStack(-1)
            default: return .swap(try dir(0))
            }
        case "warp": return .warp(try dir(0))
        case "stack": return .stack(try dir(0))
        case "unstack": return .unstack(all: args.first == "all")
        case "layout":
            let s = try arg(0).lowercased()
            guard let k = LayoutKind(rawValue: s) else { throw ConfigProblem("“\(raw)”: layout is bsp, columns, master, stack or float") }
            return .layout(k)
        case "toggle":
            let s = try arg(0).lowercased()
            guard let t = Toggle(rawValue: s) else { throw ConfigProblem("“\(raw)”: toggle float, zoom or split") }
            return .toggle(t)
        case "balance": return .balance
        case "rotate":
            let d = args.first.flatMap(Int.init) ?? 90
            guard [90, 180, 270].contains(d) else { throw ConfigProblem("“\(raw)”: rotate 90, 180 or 270") }
            return .rotate(d)
        case "resize":
            let d = try dir(0)
            guard let px = Double(try arg(1)) else { throw ConfigProblem("“\(raw)”: resize <direction> <points>") }
            return .resize(d, px)
        case "grid":
            let parts = try arg(0).split(separator: ":").compactMap { Int($0) }
            guard parts.count == 6, parts[0] > 0, parts[1] > 0, parts[4] > 0, parts[5] > 0 else {
                throw ConfigProblem("“\(raw)”: grid rows:cols:x:y:w:h")
            }
            return .grid(Grid(rows: parts[0], cols: parts[1], x: parts[2], y: parts[3], w: parts[4], h: parts[5]))
        case "workspace", "ws":
            switch try arg(0).lowercased() {
            case "new", "create": return .workspaceNew
            case "close", "destroy": return .workspaceClose
            default: return .workspace(try workspace(0))
            }
        case "move-to", "send": return .moveTo(try workspace(0), follow: follow)
        case "display": return .focusDisplay(try display(0))
        case "move-to-display": return .moveToDisplay(try display(0), follow: follow)
        case "move-workspace":
            // A direction is a display; next/prev/N are workspaces.
            if let d = Direction(try arg(0)) { return .moveWorkspaceToDisplay(.dir(d)) }
            return .moveWorkspace(try workspace(0))
        case "move-workspace-to-display": return .moveWorkspaceToDisplay(try display(0))
        case "arrange": return .arrange(args.first)
        case "initiate", "init", "reset": return .initiate(args.first)
        case "mode":
            let name = try arg(0)
            return ["exit", "off", "default", "none"].contains(name.lowercased()) ? .mode(nil) : .mode(name)
        case "undo": return .undo
        case "redo": return .redo
        case "overview", "expose": return .overview
        case "zoom":
            switch try arg(0).lowercased() {
            case "in": return .zoom(in: true)
            case "out": return .zoom(in: false)
            default: throw ConfigProblem("“\(raw)”: zoom in or zoom out")
            }
        case "retile": return .retile
        case "recover": return .recover
        case "reload": return .reload
        default: throw ConfigProblem("unknown command “\(verb)”")
        }
    }
}

extension Command.Grid {
    /// The cell's frame inside `area`.
    public func frame(in area: CGRect) -> CGRect {
        let cw = area.width / Double(cols), ch = area.height / Double(rows)
        return CGRect(x: area.minX + Double(x) * cw, y: area.minY + Double(y) * ch, width: Double(w) * cw, height: Double(h) * ch).integral
    }
}
