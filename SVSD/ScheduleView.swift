import SwiftUI

/// Which day the strip is showing.
enum ScheduleRange: String, CaseIterable, Identifiable {
    case today
    case tomorrow
    case thisWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        }
    }

    var dayOffset: Int {
        switch self {
        case .today: return 0
        case .tomorrow: return 1
        case .thisWeek: return 3
        }
    }

    /// Placeholder calendars until real availability is wired up.
    var myAvailability: [AvailabilityWindow] {
        switch self {
        case .today: return [AvailabilityWindow(start: 11, end: 16)]
        case .tomorrow: return [AvailabilityWindow(start: 9, end: 12), AvailabilityWindow(start: 17, end: 21)]
        case .thisWeek: return [AvailabilityWindow(start: 8, end: 10), AvailabilityWindow(start: 14, end: 19)]
        }
    }

    var friendAvailability: [AvailabilityWindow] {
        switch self {
        case .today: return [AvailabilityWindow(start: 13, end: 22.5)]
        case .tomorrow: return [AvailabilityWindow(start: 10.5, end: 13), AvailabilityWindow(start: 18, end: 22)]
        case .thisWeek: return [AvailabilityWindow(start: 9, end: 11), AvailabilityWindow(start: 15, end: 17.5)]
        }
    }
}

/// "Find a time that works" — the overlap view from the Kith comp.
struct ScheduleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var messageFocused: Bool
    @State private var message = ""

    @Binding var range: ScheduleRange
    var onBack: (() -> Void)?
    var onSend: ((ScheduleRange, String) -> Void)?

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }

    // The comp is an iPhone 16 frame: 393 x 852.
    private let designWidth: CGFloat = 393
    private let designHeight: CGFloat = 852
    private let contentWidth: CGFloat = 353

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack(alignment: .top) {
                KithTheme.canvas(isDark)

                FriendAvatarHeader()
                    .position(x: size.width / 2, y: size.height * (145.61 / designHeight))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                KithBackButton {
                    messageFocused = false
                    onBack?()
                }
                    .padding(.leading, 12.25)
                    .frame(width: size.width, alignment: .leading)
                    .position(x: size.width / 2, y: size.height * (96.5 / designHeight))

                VStack(spacing: 0) {
                    Color.clear.frame(height: size.height * (226 / designHeight))
                    picker
                    composer
                    Spacer(minLength: 0)
                    sendButton
                        .padding(.bottom, max(24, size.height * (62 / designHeight)))
                }
                .frame(width: min(contentWidth, size.width - 40))
                .frame(maxWidth: .infinity)
            }
            .frame(width: size.width, height: size.height)
        }
        .background(KithTheme.canvas(isDark))
        .ignoresSafeArea(.container, edges: .all)
        .statusBarHidden(true)
        .contentShape(Rectangle())
        .onTapGesture { messageFocused = false }
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(spacing: 20) {
            Text("Find a time that works")
                .font(.kithHeading)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            VStack(spacing: 15) {
                RangeTabs(selection: $range)

                VStack(spacing: 8) {
                    Text(dayLabel)
                        .font(.kithCaptionStrong)
                        .textCase(.uppercase)
                        .monospacedDigit()
                        .foregroundStyle(ink)

                    Text(overlapLabel)
                        .font(.kithCaption)
                        .monospacedDigit()
                        .foregroundStyle(secondary)

                    AvailabilityTimeline(
                        mine: range.myAvailability,
                        theirs: range.friendAvailability
                    )
                    .environment(\.layoutDirection, .leftToRight)
                    .id(range)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Message")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(KithTheme.uiFill(isDark))

                TextEditor(text: $message)
                    .font(.kithBody)
                    .foregroundStyle(ink)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .focused($messageFocused)
            }
            .frame(minHeight: 120, maxHeight: 258.379)
            .accessibilityLabel("Your message")
        }
        .padding(.top, 15)
    }

    private var sendButton: some View {
        KithPillButton(title: "Send", accessibilityLabel: "Send invitation") {
            messageFocused = false
            onSend?(range, message)
        }
        .padding(.top, 18)
    }

    // MARK: - Labels

    private var dayLabel: String {
        let date = Calendar.current.date(byAdding: .day, value: range.dayOffset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        return formatter.string(from: date)
    }

    private var overlapLabel: String {
        let overlaps = range.myAvailability.intersection(range.friendAvailability)
        guard !overlaps.isEmpty else { return "No overlap — try another day" }
        return overlaps
            .map { "\(AvailabilityTimeline.timeLabel($0.start)) - \(AvailabilityTimeline.timeLabel($0.end))" }
            .joined(separator: " · ")
    }
}

#Preview {
    PlanFlowView()
}
