import CoreGraphics

/// A tile holding more than one window, as the indicators draw it.
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

