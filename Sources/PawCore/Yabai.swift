import CoreGraphics
import Foundation

/// The parts of `yabai -m query --windows` paw uses.
public struct YabaiWindow: Decodable, Equatable, Sendable {
    public struct Frame: Decodable, Equatable, Sendable {
        public var x, y, w, h: Double
    }

    public var id: Int
    public var pid: Int
    public var app: String
    public var title: String
    public var frame: Frame
    public var display: Int
    public var space: Int
    public var stackIndex: Int
    public var hasFocus: Bool
    public var isVisible: Bool
    public var isMinimized: Bool
    public var isHidden: Bool

    enum CodingKeys: String, CodingKey {
        case id, pid, app, title, frame, display, space
        case stackIndex = "stack-index", hasFocus = "has-focus", isVisible = "is-visible"
        case isMinimized = "is-minimized", isHidden = "is-hidden"
    }

    public init(id: Int, pid: Int = 0, app: String, title: String = "", frame: CGRect, display: Int = 1, space: Int = 1,
                stackIndex: Int, hasFocus: Bool = false, isVisible: Bool = false, isMinimized: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.pid = pid
        self.app = app
        self.title = title
        self.frame = Frame(x: frame.minX, y: frame.minY, w: frame.width, h: frame.height)
        self.display = display
        self.space = space
        self.stackIndex = stackIndex
        self.hasFocus = hasFocus
        self.isVisible = isVisible
        self.isMinimized = isMinimized
        self.isHidden = isHidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        pid = try c.decodeIfPresent(Int.self, forKey: .pid) ?? 0
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        frame = try c.decode(Frame.self, forKey: .frame)
        display = try c.decodeIfPresent(Int.self, forKey: .display) ?? 0
        space = try c.decodeIfPresent(Int.self, forKey: .space) ?? 0
        stackIndex = try c.decodeIfPresent(Int.self, forKey: .stackIndex) ?? 0
        hasFocus = try c.decodeIfPresent(Bool.self, forKey: .hasFocus) ?? false
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? false
        isMinimized = try c.decodeIfPresent(Bool.self, forKey: .isMinimized) ?? false
        isHidden = try c.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
    }

    /// Top-left origin, global (same space as Quartz and Accessibility).
    public var rect: CGRect { CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h) }
}

/// The parts of `yabai -m query --spaces` paw uses.
public struct YabaiSpace: Decodable, Equatable, Sendable {
    public var index: Int
    public var display: Int
    public var isVisible: Bool

    enum CodingKeys: String, CodingKey {
        case index, display
        case isVisible = "is-visible"
    }

    public init(index: Int, display: Int = 1, isVisible: Bool) {
        self.index = index
        self.display = display
        self.isVisible = isVisible
    }
}

/// One yabai stack on a visible space: its windows in stack order.
public struct Stack: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public var id: Int
        public var app: String
        public var title: String
        /// The window on top of the stack (the one you see).
        public var isActive: Bool
        public var hasFocus: Bool

        public init(id: Int, app: String, title: String, isActive: Bool, hasFocus: Bool) {
            self.id = id
            self.app = app
            self.title = title
            self.isActive = isActive
            self.hasFocus = hasFocus
        }
    }

    public var space: Int
    /// The stack's frame (all its windows share it).
    public var frame: CGRect
    public var items: [Item]

    public init(space: Int, frame: CGRect, items: [Item]) {
        self.space = space
        self.frame = frame
        self.items = items
    }

    /// Key that stays the same while the stack keeps its place, for reusing its panel.
    public var key: String { "\(space)|\(Int(frame.minX))|\(Int(frame.minY))" }
    public var hasFocus: Bool { items.contains { $0.hasFocus } }
    public var activeIndex: Int? { items.firstIndex { $0.isActive } }
}

public enum StackBuilder {
    /// Groups windows with a `stack-index` on visible spaces into stacks. Windows of one
    /// stack share a frame; `fuzz` (points) tolerates the off-by-a-few frames some apps report.
    public static func stacks(windows: [YabaiWindow], spaces: [YabaiSpace], fuzz: Double = 30) -> [Stack] {
        let visible = Set(spaces.filter(\.isVisible).map(\.index))
        let f = max(1, fuzz)
        func r(_ v: Double) -> Int { Int((v / f).rounded()) }
        var groups: [String: [YabaiWindow]] = [:]
        var order: [String] = []
        for w in windows where w.stackIndex > 0 && !w.isMinimized && !w.isHidden && (visible.isEmpty || visible.contains(w.space)) {
            let key = "\(w.space)|\(r(w.frame.x))|\(r(w.frame.y))|\(r(w.frame.w))|\(r(w.frame.h))"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(w)
        }
        var out: [Stack] = []
        for key in order {
            let ws = groups[key]!.sorted { $0.stackIndex != $1.stackIndex ? $0.stackIndex < $1.stackIndex : $0.id < $1.id }
            guard ws.count > 1 else { continue }
            // The top window is the visible one; without that flag, the focused one.
            let top = ws.first(where: \.isVisible)?.id ?? ws.first(where: \.hasFocus)?.id ?? ws[0].id
            let frame = (ws.first { $0.id == top } ?? ws[0]).rect
            out.append(Stack(space: ws[0].space, frame: frame, items: ws.map {
                Stack.Item(id: $0.id, app: $0.app, title: $0.title, isActive: $0.id == top, hasFocus: $0.hasFocus)
            }))
        }
        return out.sorted { ($0.space, $0.frame.minX, $0.frame.minY) < ($1.space, $1.frame.minX, $1.frame.minY) }
    }
}
