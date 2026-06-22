import Carbon

struct HotkeyConfig: Equatable {
    struct Modifiers: OptionSet, Equatable {
        let rawValue: UInt32

        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    var keyCode: UInt32
    var modifiers: Modifiers
    var displayName: String

    static let runActiveAgents = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_O),
        modifiers: [.control, .command],
        displayName: "Control + Command + O"
    )
}
