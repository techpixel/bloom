import SwiftUI

// Chrome shared by every planning screen: the comps repeat the same header,
// back arrow, range tabs and pill button around a changing middle section.

/// The friend's photo with the soft purple shape behind it (176.81 × 179.78 in the comp).
struct FriendAvatarHeader: View {
    var body: some View {
        ZStack {
            AvatarGlowShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: KithTheme.glow, location: 0),
                            .init(color: KithTheme.glow, location: 0.35),
                            .init(color: KithTheme.glow.opacity(0.8), location: 0.64),
                            .init(color: KithTheme.glow.opacity(0.3), location: 0.85),
                            .init(color: KithTheme.glow.opacity(0.03), location: 1)
                        ],
                        startPoint: UnitPoint(x: 0.1469, y: 0.8666),
                        endPoint: UnitPoint(x: 0.9222, y: 0.0869)
                    )
                )
                .frame(width: 167.888, height: 175.121)
                .blur(radius: 9.94)
                .rotationEffect(.degrees(-28.12))
                .offset(x: -19.1)

            Image("FriendAvatar")
                .resizable()
                .scaledToFill()
                .frame(width: 232.17, height: 155.12)
                .offset(x: 6.08, y: -3.28)
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                .offset(x: -0.5, y: 3.11)
        }
        .frame(width: 176.81, height: 179.78)
    }
}

struct KithBackButton: View {
    @Environment(\.colorScheme) private var colorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("BackArrow")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22.51, height: 13.72)
                .flipsForRightToLeftLayoutDirection(true)
                .foregroundStyle(KithTheme.ink(colorScheme == .dark))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Back")
    }
}

/// Today / Tomorrow / This Week, with the selection as a filled pill.
struct RangeTabs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var pill

    @Binding var selection: ScheduleRange
    /// With counts, the tabs take Home's softer look (comp 406:1755): a filled
    /// track, the chosen tab lifted onto the page with a fine outline, and a
    /// badge of how many friends are free in each.
    var counts: [ScheduleRange: Int]? = nil

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }

    var body: some View {
        if let counts {
            soft(counts)
        } else {
            solid
        }
    }

    private func choose(_ option: ScheduleRange) {
        if reduceMotion {
            selection = option
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                selection = option
            }
        }
    }

    private var solid: some View {
        HStack(spacing: 8) {
            ForEach(ScheduleRange.allCases) { option in
                Button { choose(option) } label: {
                    Text(option.title)
                        .font(.kithCaption)
                        .kithCapCentered(13, relativeTo: .footnote)
                        .foregroundStyle(selection == option ? KithTheme.canvas(isDark) : ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                        .background {
                            if selection == option {
                                Capsule()
                                    .fill(ink)
                                    .matchedGeometryEffect(id: "tab", in: pill)
                                    .padding(.vertical, 7)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == option ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(height: 30)
        .overlay(Capsule().strokeBorder(ink, lineWidth: 1))
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func soft(_ counts: [ScheduleRange: Int]) -> some View {
        HStack(spacing: 8) {
            ForEach(ScheduleRange.allCases) { option in
                let chosen = selection == option
                Button { choose(option) } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                            .font(KithType.font(.w90, 12, .caption))
                            .kithCapCentered(12, relativeTo: .caption)
                            .foregroundStyle(ink)
                        Text("\(counts[option] ?? 0)")
                            .font(.kithFine)
                            .monospacedDigit()
                            .kithCapCentered(12, relativeTo: .caption)
                            .foregroundStyle(chosen ? KithTheme.uiFill(isDark) : ink)
                            .frame(minWidth: 17, minHeight: 17)
                            .padding(.horizontal, 2)
                            .background(chosen ? KithTheme.secondary(isDark) : KithTheme.canvas(isDark), in: Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background {
                        if chosen {
                            Capsule()
                                .fill(KithTheme.canvas(isDark))
                                .overlay(Capsule().strokeBorder(KithTheme.secondary(isDark), lineWidth: 1))
                                .matchedGeometryEffect(id: "tab", in: pill)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(option.title), \(counts[option] ?? 0) free")
                .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
            }
        }
        .frame(height: 38)
        .background(KithTheme.uiFill(isDark), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The 194pt capsule every comp ends on. `.muted` is the comp's quiet treatment
/// for an action that is live but not yet the thing to do — the permission
/// prompts use it — and is distinct from simply being disabled.
struct KithPillButton: View {
    enum Style { case solid, muted }

    @Environment(\.colorScheme) private var colorScheme

    let title: String
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var isEnabled = true
    var style: Style = .solid
    let action: () -> Void

    private var isDark: Bool { colorScheme == .dark }
    private var isQuiet: Bool { style == .muted || !isEnabled }

    /// A disabled label is exempt from the contrast floor; an enabled one on the
    /// same fill is not, so it takes the darker secondary.
    private var labelColor: Color {
        guard isEnabled else { return KithTheme.secondary(isDark) }
        return isQuiet ? KithTheme.secondaryOnFill(isDark) : KithTheme.canvas(isDark)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.kithBody)
                .kithCapCentered(17, relativeTo: .body)
                .foregroundStyle(labelColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minWidth: 194, maxWidth: 194, minHeight: 44)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isQuiet ? KithTheme.uiFill(isDark) : KithTheme.ink(isDark))
                }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}

/// A light press-down, skipped when the reader has asked for less motion.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Evenly spaced diagonal lines; `slope` is horizontal travel per unit of height.
/// Measured off the comps at 17.25pt apart, slope 0.7, in black at 15%.
struct DiagonalHatch: Shape {
    var spacing: CGFloat = 17.25
    var slope: CGFloat = 0.7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard spacing > 0 else { return path }
        let run = slope * rect.height
        var x = rect.minX - run - spacing
        while x <= rect.maxX + spacing {
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x + run, y: rect.maxY))
            x += spacing
        }
        return path
    }
}

/// The soft purple shape behind the avatar (Polygon 3 in the comp).
struct AvatarGlowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 167.888
        let sy = rect.height / 175.121
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(87.7433, 27.2003))
        path.addCurve(
            to: point(130.257, 37.6504),
            control1: point(101.406, 13.8659),
            control2: point(124.566, 19.5588)
        )
        path.addLine(to: point(146.813, 118.102))
        path.addCurve(
            to: point(124.69, 149.418),
            control1: point(152.72, 136.88),
            control2: point(135.431, 168.293)
        )
        path.addLine(to: point(39.2862, 128.425))
        path.addCurve(
            to: point(33.569, 93.9559),
            control1: point(9.43118, 118.167),
            control2: point(19.389, 107.796)
        )
        path.closeSubpath()
        return path
    }
}

/// The app's entrance, from the opening study: fade up 12pt out of a 4pt blur,
/// easing out. `order` staggers it, so a screen arrives top to bottom rather
/// than all at once. Reduce Motion keeps the fade and drops the movement.
private struct EntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let order: Int
    let visible: Bool

    func body(content: Content) -> some View {
        let settled = visible || reduceMotion
        content
            .opacity(visible ? 1 : 0)
            .offset(y: settled ? 0 : 12)
            .blur(radius: settled ? 0 : 4)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.3)
                    : .easeOut(duration: 0.55).delay(Double(order) * 0.12),
                value: visible
            )
    }
}

extension View {
    /// Part of a staggered entrance. Flip `visible` once to play it.
    func entrance(_ order: Int, visible: Bool) -> some View {
        modifier(EntranceModifier(order: order, visible: visible))
    }
}

// MARK: - Drawers

extension View {
    /// A page that slides up over the one you're on and swipes back down to
    /// close: the friend page, their history, a hangout. The handle says it can.
    func drawer<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented) {
            content().drawerStyle()
        }
    }

    func drawer<Item: Identifiable, Content: View>(item: Binding<Item?>, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item) { value in
            content(value).drawerStyle()
        }
    }

    fileprivate func drawerStyle() -> some View {
        presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(KithTheme.canvas(false))
            // Every drawer opens to the same height, editors included, so they
            // don't each arrive at a different size.
            .presentationDetents([.large])
    }
}
