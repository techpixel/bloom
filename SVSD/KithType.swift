import CoreText
import SwiftUI

// The Kith type scale. Sizes and weights come straight from the Figma text
// styles; the `relativeTo:` pairing is what lets each one answer Dynamic Type
// instead of sitting at a fixed point size.

enum KithType {
    /// AUTHENTIC Sans names its weights by number rather than by word.
    enum Weight: String {
        case w60 = "AUTHENTICSans-60"
        case w90 = "AUTHENTICSans-90"
        case w130 = "AUTHENTICSans-130"
        case w150 = "AUTHENTICSans-150"
    }

    /// Registered from the bundle at launch, so no Info.plist entry is needed.
    /// If a face is missing the call falls through to the system font at the
    /// same size and the layout still holds.
    static func registerFonts() {
        let urls = ["otf", "ttf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        guard !urls.isEmpty else { return }
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// Bloom's wordmark face, Worldstar (Blankids Studio; personal-use
    /// licence — buy the commercial one before Bloom makes money).
    static func wordmark(_ size: CGFloat, _ textStyle: Font.TextStyle) -> Font {
        guard available.contains("Worldstar-Regular") else {
            return .system(size: size, weight: .bold, design: .serif)
        }
        return .custom("Worldstar-Regular", size: size, relativeTo: textStyle)
    }

    static func font(_ weight: Weight, _ size: CGFloat, _ textStyle: Font.TextStyle) -> Font {
        guard isAvailable(weight) else {
            return .system(size: size, weight: systemFallbackWeight(weight))
        }
        return .custom(weight.rawValue, size: size, relativeTo: textStyle)
    }

    private static func isAvailable(_ weight: Weight) -> Bool {
        available.contains(weight.rawValue)
    }

    private static let available: Set<String> = {
        Set(UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) })
    }()

    /// Closest SF Pro weight, for the case where the face did not load.
    private static func systemFallbackWeight(_ weight: Weight) -> Font.Weight {
        switch weight {
        case .w60: return .light
        case .w90: return .regular
        case .w130: return .semibold
        case .w150: return .bold
        }
    }
}

extension Font {
    /// Kith/Typography/Display — 130 @ 36
    static var kithDisplay: Font { KithType.font(.w130, 36, .largeTitle) }
    /// Screen titles on the main tabs ("Your Friends") — 130 @ 32
    static var kithTitle: Font { KithType.font(.w130, 32, .largeTitle) }
    /// Kith/Typography/Welcome — 90 @ 36
    static var kithWelcome: Font { KithType.font(.w90, 36, .largeTitle) }
    /// Kith/Typography/Heading — 90 @ 24
    static var kithHeading: Font { KithType.font(.w90, 24, .title2) }
    /// Kith/Typography/Prompt — 90 @ 20
    static var kithPrompt: Font { KithType.font(.w90, 20, .title3) }
    /// The "bloom" wordmark — Worldstar @ 40
    static var bloomWordmark: Font { KithType.wordmark(40, .largeTitle) }
    // From Body down, the comp's sizes sat a step below Apple's reading sizes
    // (names at 13, details at 12, fine print at 11), so each is raised to the
    // HIG text style it plays the part of: Body 17, Subheadline 15, Footnote 13,
    // Caption 12.

    /// Kith/Typography/Body & button — 90 @ 17 (HIG Body; the comp has 16)
    static var kithBody: Font { KithType.font(.w90, 17, .body) }
    /// Body at the heavier weight, for labels that head a group.
    static var kithBodyStrong: Font { KithType.font(.w130, 17, .body) }
    /// Kith/Typography/Secondary body — 90 @ 15 (HIG Subheadline; the comp has 14)
    static var kithSecondary: Font { KithType.font(.w90, 15, .subheadline) }
    /// Names and row titles — 130 @ 15 (HIG Subheadline; the comp has 13)
    static var kithCardTitle: Font { KithType.font(.w130, 15, .subheadline) }
    /// Timestamps beside a row — 90 @ 13
    static var kithFootnote: Font { KithType.font(.w90, 13, .footnote) }
    /// Kith/Typography/Caption — 90 @ 13 (HIG Footnote; the comp has 12)
    static var kithCaption: Font { KithType.font(.w90, 13, .footnote) }
    /// Caption at the heavier weight, for dates above the timeline.
    static var kithCaptionStrong: Font { KithType.font(.w130, 13, .footnote) }
    /// The mutual friend's name inside a caption ("Friends with **Ishan**") — 150 @ 13
    static var kithCaptionHeavy: Font { KithType.font(.w150, 13, .footnote) }
    /// Suggestion card detail — 60 @ 12 (HIG Caption; the comp has 11)
    static var kithFine: Font { KithType.font(.w90, 12, .caption) }
    /// Feeling tags on a hangout row — 130 @ 12
    static var kithFineStrong: Font { KithType.font(.w130, 12, .caption) }
    /// A section title inside a card — 130 @ 16
    static var kithSectionTitle: Font { KithType.font(.w130, 16, .callout) }
    /// The line under a row's title, and the small labels in a reflection — 90 @ 14
    static var kithRowDetail: Font { KithType.font(.w90, 14, .subheadline) }
    /// A week range over a group of history entries — 90 @ 14
    static var kithSubrange: Font { KithType.font(.w90, 14, .subheadline) }
    /// The welcome tagline — 90 @ 15.62
    static var kithTagline: Font { KithType.font(.w90, 15.62, .subheadline) }
    /// A weekday initial in the week strip — 90 @ 26.841
    static var kithDayLetter: Font { KithType.font(.w90, 26.841, .title) }
    /// Initials in a contact avatar — 90 @ 19
    static var kithInitials: Font { KithType.font(.w90, 19, .title3) }
    /// Initials in a 40pt suggestion avatar — 150 @ 16
    static var kithInitialsSmall: Font { KithType.font(.w150, 16, .callout) }
}

extension View {
    /// The layouts are positioned against the comps' fixed frames, so type
    /// scales up to the first accessibility size and then holds. Past that the
    /// absolute placement would start to collide.
    func kithTypeScaling() -> some View {
        dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// AUTHENTIC Sans has an unusually tall ascender, so SwiftUI's line box sits its
/// letters about 0.077em high: measured on the Send pill, 11.1pt above the ink
/// and 13.4pt below. Figma hides this by trimming text to cap height and
/// baseline; this nudges a label back down by the same amount, scaled with
/// Dynamic Type, so it sits centred in a pill or tab.
private struct CapCentered: ViewModifier {
    @ScaledMetric private var size: CGFloat

    init(size: CGFloat, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    func body(content: Content) -> some View {
        content.offset(y: size * 0.077)
    }
}

extension View {
    /// Optically centres a one-line AUTHENTIC Sans label of `size` points.
    func kithCapCentered(_ size: CGFloat, relativeTo style: Font.TextStyle) -> some View {
        modifier(CapCentered(size: size, relativeTo: style))
    }
}
