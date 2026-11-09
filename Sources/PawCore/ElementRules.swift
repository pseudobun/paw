/// Which accessibility elements get a label, and how they are clicked.
public enum ElementRules {
    public static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXMenuBarItem", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        "AXDisclosureTriangle", "AXRow", "AXDockItem", "AXIncrementor", "AXSlider", "AXSwitch",
        "AXColorWell", "AXTab", "AXSegment", "AXToggle",
    ]

    /// Never labelled, even with AXPress: the containers around everything.
    public static let ignoredRoles: Set<String> = [
        "AXApplication", "AXWindow", "AXSheet", "AXScrollArea", "AXScrollBar", "AXSplitGroup",
        "AXSplitter", "AXWebArea", "AXLayoutArea", "AXMenuBar", "AXMenu", "AXList", "AXTable",
        "AXOutline", "AXBrowser", "AXValueIndicator", "AXDrawer", "AXGrowArea", "AXToolbar",
    ]

    /// Roles whose subtree is the label itself (no need to look inside).
    public static let leafRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField", "AXDisclosureTriangle",
        "AXIncrementor", "AXSlider", "AXSwitch", "AXColorWell", "AXDockItem", "AXMenuBarItem",
    ]

    /// Text inputs: AXPress does nothing useful, a click puts the caret there.
    public static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Roles whose actions are worth a round trip to check for AXPress (leaf web/native content).
    public static let maybePressableRoles: Set<String> = ["AXImage", "AXGroup", "AXCell"]

    public static func isClickable(role: String, subrole: String?, actions: [String]?, parentRole: String?) -> Bool {
        if ignoredRoles.contains(role) { return false }
        if role == "AXCell" {
            // Cells inside a row are covered by the row's label.
            if parentRole == "AXRow" { return actions?.contains("AXPress") == true }
            return true
        }
        if role == "AXRadioButton" || role == "AXButton" { return true }
        if clickableRoles.contains(role) { return true }
        if subrole == "AXTabButton" || subrole == "AXCloseButton" || subrole == "AXMinimizeButton" || subrole == "AXZoomButton" {
            return true
        }
        return actions?.contains("AXPress") == true
    }

    /// Text fields and table rows/cells are clicked with the mouse; the rest is pressed.
    public static func prefersMouse(role: String) -> Bool {
        textRoles.contains(role) || role == "AXRow" || role == "AXCell"
    }

    /// Lower sorts first when two labels would overlap: controls beat rows and groups.
    public static func priority(role: String) -> Int {
        switch role {
        case "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
             "AXMenuItem", "AXMenuBarItem", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
             "AXDockItem", "AXDisclosureTriangle":
            return 0
        case "AXRow", "AXCell": return 2
        default: return 1
        }
    }

    /// Scroll mode: areas worth scrolling.
    public static let scrollRoles: Set<String> = ["AXScrollArea"]

    /// Chromium-based browsers need AXEnhancedUserInterface before their web content shows up.
    public static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.brave.Browser", "com.brave.Browser.beta", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "company.thebrowser.dia", "com.operasoftware.Opera",
        "ai.perplexity.comet", "net.imput.helium", "com.sigmaos.sigmaos.macos",
    ]
}
