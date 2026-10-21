import SwiftUI

/// Design tokens from the Kith comp. Light values are the Figma tokens verbatim;
/// dark values are the warm equivalents the onboarding flow already uses.
enum KithTheme {
    static func canvas(_ dark: Bool) -> Color {
        dark ? Color(white: 0.07) : Color(red: 0.992, green: 0.980, blue: 0.961) // #FDFAF5
    }

    /// Kith/Colors/Primary — #24211D
    static func ink(_ dark: Bool) -> Color {
        dark ? Color(red: 0.945, green: 0.929, blue: 0.902) : Color(red: 0.141, green: 0.129, blue: 0.114)
    }

    /// Kith/Colors/Secondary — #716B62
    static func secondary(_ dark: Bool) -> Color {
        dark ? Color(red: 0.643, green: 0.620, blue: 0.576) : Color(red: 0.443, green: 0.420, blue: 0.384)
    }

    /// Secondary text sitting on Ui Fill. A shade darker than
    /// Kith/Colors/Secondary, which measures 4.23:1 there — under the 4.5:1
    /// floor. Only for labels on an interactive control; disabled controls are
    /// exempt and keep the token colour.
    static func secondaryOnFill(_ dark: Bool) -> Color {
        dark ? Color(red: 0.643, green: 0.620, blue: 0.576) : Color(red: 0.424, green: 0.400, blue: 0.365)
    }

    /// Kith/Colors/Ui Fill — #EEE5D8
    static func uiFill(_ dark: Bool) -> Color {
        dark ? Color(white: 0.16) : Color(red: 0.933, green: 0.898, blue: 0.847)
    }

    /// Timeline trough — #F1EEE7
    static func timelineTrack(_ dark: Bool) -> Color {
        dark ? Color(white: 0.13) : Color(red: 0.945, green: 0.933, blue: 0.906)
    }

    /// Hour ticks inside the trough — #EEE5D8
    static func timelineTick(_ dark: Bool) -> Color {
        dark ? Color(white: 0.21) : Color(red: 0.933, green: 0.898, blue: 0.847)
    }

    /// Someone is free — #60E5AB
    static let availability = Color(red: 0.376, green: 0.898, blue: 0.671)

    /// Both people are free — #18A165
    static let overlap = Color(red: 0.094, green: 0.631, blue: 0.396)

    /// The hatch drawn over single-person availability (black at 15% in the comp).
    static let availabilityHatch = Color.black.opacity(0.15)

    /// Grip on each edge of a chosen slot — #1BB773
    static let slotHandle = Color(red: 0.106, green: 0.718, blue: 0.451)

    /// Suggestion cards, unavailable day tiles, neutral timeline bands — #EDE8E0
    static func suggestionCard(_ dark: Bool) -> Color {
        dark ? Color(white: 0.15) : Color(red: 0.929, green: 0.910, blue: 0.878)
    }

    /// Month and date headings above the calendar — #374151
    static func calendarHeading(_ dark: Bool) -> Color {
        dark ? Color(red: 0.733, green: 0.769, blue: 0.824) : Color(red: 0.216, green: 0.255, blue: 0.318)
    }

    /// A weekday with no shared time — #9C9C9C
    static func mutedDay(_ dark: Bool) -> Color {
        dark ? Color(white: 0.45) : Color(red: 0.612, green: 0.612, blue: 0.612)
    }

    /// Thumbnail plate on a suggestion card
    static func thumbnail(_ dark: Bool) -> Color {
        dark ? Color(white: 0.24) : canvas(false)
    }

    /// The Messages badge on a friend who is not on Kith yet. Apple's system
    /// green, so the affordance reads the way it does everywhere else on iOS.
    static let messagesGreen = Color(red: 0.204, green: 0.780, blue: 0.349)

    /// A picked feeling on Home's reflection card — #7ECCAA
    static let feelingSelected = Color(red: 0.494, green: 0.800, blue: 0.667)

    /// A feeling that took something out of you — #F3AA18
    static let feelingDraining = Color(red: 0.953, green: 0.667, blue: 0.094)

    /// The "reflect" / "view" pill on a recap row — #FDEECB
    static let reflectPill = Color(red: 0.992, green: 0.933, blue: 0.796)

    /// The selected tab in the bottom nav — #4F46E5
    static let navActive = Color(red: 0.310, green: 0.275, blue: 0.898)

    /// The suggestion line on a Today card — #A44E1A
    static let suggestionAccent = Color(red: 0.643, green: 0.306, blue: 0.102)

    /// Metadata under a recent hangout — #706777
    static let recentMeta = Color(red: 0.439, green: 0.404, blue: 0.467)

    /// Glow behind the friend's avatar — #C3AFFE
    static let glow = Color(red: 0.765, green: 0.686, blue: 0.996)

    /// Log out, in a dusty red that reads as "careful" without shouting — #A04C46,
    /// 4.7:1 on the settings card.
    static let logOut = Color(red: 0.627, green: 0.298, blue: 0.275)
}
