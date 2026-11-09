import ApplicationServices
import CoreGraphics

/// Something paw can label: an accessibility element with its frame (global, top-left origin).
struct Element {
    enum Source: String { case window, menu, menuBar, extras, dock }

    let ref: AXUIElement
    let frame: CGRect
    let role: String
    let subrole: String?
    var title: String?
    var desc: String?
    var value: String?
    var roleDescription: String?
    var placeholder: String?
    let source: Source
    /// The visible region the element was found in (window ∩ scroll areas ∩ screen).
    let clip: CGRect
    /// AXPress is known to be there (nil: not checked).
    var canPress: Bool?

    /// Text fields for search mode, best first.
    var searchFields: [(text: String?, weight: Double)] {
        [(title, 1.0), (desc, 0.95), (placeholder, 0.8), (value, 0.7), (roleDescription, 0.3)]
    }

    var displayName: String { title ?? desc ?? placeholder ?? value ?? roleDescription ?? role }
}
