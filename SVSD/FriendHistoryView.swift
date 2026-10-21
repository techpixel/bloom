import SwiftUI

/// Every time you've spent with one friend (comp 414:2432). Their face and what
/// the pattern says, then the month's entries grouped by the week they fell in,
/// each carrying the feelings you logged and a way into the detail page.
struct FriendHistoryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(HangoutStore.self) private var store

    let contact: KithContact
    var onBack: () -> Void

    @State private var screenWidth: CGFloat = 393
    @State private var openHangout: RecentHangout.ID?
    @State private var selectedMonth = FriendHistoryView.monthName

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    var body: some View {
        let theirs = store.hangouts.filter { $0.contact.name == contact.name }

        ZStack(alignment: .topLeading) {
            KithTheme.canvas(isDark).ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    Text("History")
                        .font(.kithHeading)
                        .foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)

                    HStack {
                        KithBackButton(action: onBack)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 12.25)
                .padding(.top, 20 * scale)

                ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    friendRow
                        .padding(.top, 46 * scale)

                    Rectangle()
                        .fill(secondary.opacity(0.3))
                        .frame(height: 1)
                        .padding(.top, 24)

                    month
                        .padding(.top, 14)

                    ForEach(Array(weeks(of: theirs).enumerated()), id: \.offset) { _, week in
                        Text(week.label)
                            .font(.kithSubrange)
                            .foregroundStyle(secondary)
                            .padding(.top, 18)

                        VStack(spacing: 10) {
                            ForEach(week.hangouts) { hangout in
                                entry(hangout)
                            }
                        }
                        .padding(.top, 10)
                    }

                    if theirs.isEmpty {
                        Text("Nothing logged with \(contact.firstName) yet.")
                            .font(.kithSecondary)
                            .foregroundStyle(secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 40)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .fullScreenCover(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
            if let index = store.hangouts.firstIndex(where: { $0.id == openHangout }) {
                MeetupDetailView(hangout: Bindable(store).hangouts[index]) { openHangout = nil }
            }
        }
    }

    // MARK: - Header

    /// Their face in its glow, their name, and the pattern across every entry.
    private var friendRow: some View {
        HStack(alignment: .center, spacing: 16) {
            ContactAvatar(contact: contact, diameter: 94.1 * scale, initialsFont: .kithInitials)
                .background {
                    Image("MeetupGlow")
                        .resizable()
                        .frame(width: 136 * scale, height: 133 * scale)
                        .rotationEffect(.degrees(-28.12))
                        .offset(x: -12 * scale, y: 3 * scale)
                        .accessibilityHidden(true)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(contact.name)
                    .font(.kithHeading)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text(insight)
                    .font(.kithFine)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }

    /// What the feelings add up to, said plainly.
    private var insight: AttributedString {
        var label = AttributedString("Insight: ")
        label.font = .kithFineStrong
        var body = AttributedString(insightBody)
        body.font = .kithFine
        return label + body
    }

    private var insightBody: String {
        let theirs = store.hangouts.filter { $0.contact.name == contact.name }
        let logged = theirs.flatMap(\.feelings)
        guard !logged.isEmpty else { return "not enough logged yet to see a pattern" }
        let draining = logged.filter(\.isDraining).count
        return draining * 2 > logged.count
            ? "this person tends to leave you drained"
            : "you usually feel positive and energized by this person"
    }

    // MARK: - Month

    private var month: some View {
        Menu {
            Picker("Month", selection: $selectedMonth) {
                ForEach(Self.months, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedMonth)
                    .font(.kithBodyStrong)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(selectedMonth), change month")
        .sensoryFeedback(.selection, trigger: selectedMonth)
    }

    // MARK: - Entries

    /// One entry: how it felt, what it was, and a way into it.
    private func entry(_ hangout: RecentHangout) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                let feelings = Feeling.allCases.filter(hangout.feelings.contains)

                HStack(spacing: 3) {
                    if feelings.isEmpty {
                        FeelingTag(
                            "Needs reflection",
                            fill: KithTheme.canvas(isDark),
                            text: secondary
                        )
                    } else {
                        ForEach(feelings) { feeling in
                            FeelingTag(feeling.rawValue, fill: feeling.pillFill)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(hangout.title)
                        .font(.kithCaptionStrong)
                        .foregroundStyle(ink)
                    Text(hangout.detail)
                        .font(.kithFine)
                        .foregroundStyle(KithTheme.recentMeta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button { openHangout = hangout.id } label: {
                Text("Details")
                    .font(.kithCaption)
                    .kithCapCentered(13, relativeTo: .footnote)
                    .foregroundStyle(KithTheme.canvas(isDark))
                    .frame(width: 70, height: 27)
                    .background(ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Details for \(hangout.title)")
        }
        .padding(12)
        .background(KithTheme.uiFill(isDark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Grouping

    /// The comp groups a month's entries by the week they fell in. Nothing in
    /// the demo carries a real date, so they split evenly into the comp's two.
    private struct Week {
        let label: String
        let hangouts: [RecentHangout]
    }

    static let monthName = "October"
    /// The demo only has the one month's worth, so the rest just relabel.
    static let months = ["August", "September", "October"]
    private static let weekLabels = ["12-19", "20-27"]

    private func weeks(of hangouts: [RecentHangout]) -> [Week] {
        guard !hangouts.isEmpty else { return [] }
        let perWeek = max(1, Int((Double(hangouts.count) / 2).rounded(.up)))
        return stride(from: 0, to: hangouts.count, by: perWeek).enumerated().map { index, start in
            Week(
                label: Self.weekLabels[min(index, Self.weekLabels.count - 1)],
                hangouts: Array(hangouts[start..<min(start + perWeek, hangouts.count)])
            )
        }
    }
}

extension Feeling {
    /// The ones that took something from you read amber; the rest read green.
    var isDraining: Bool {
        self == .distant || self == .draining
    }

    var pillFill: Color {
        isDraining ? KithTheme.feelingDraining : KithTheme.feelingSelected
    }
}
