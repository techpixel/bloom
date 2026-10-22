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
    /// The month on screen. It trails `selectedMonth` by a beat, so the old
    /// entries can leave before the new ones step in.
    @State private var displayedMonth = FriendHistoryView.monthName
    @State private var listShown = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    var body: some View {
        let theirs = entries(for: displayedMonth)
        let weeks = weeks(of: theirs)

        ZStack(alignment: .topLeading) {
            KithTheme.canvas(isDark).ignoresSafeArea()

            VStack(spacing: 0) {
                Text("History")
                    .font(.kithHeading)
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity)
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

                    ForEach(Array(weeks.enumerated()), id: \.offset) { weekIndex, week in
                        let before = weeks.prefix(weekIndex).reduce(0) { $0 + $1.hangouts.count + 1 }

                        Text(week.label)
                            .font(.kithSubrange)
                            .foregroundStyle(secondary)
                            .padding(.top, 18)
                            .stepIn(listShown, order: before, reduceMotion: reduceMotion)

                        VStack(spacing: 10) {
                            ForEach(Array(week.hangouts.enumerated()), id: \.element.id) { index, hangout in
                                entry(hangout)
                                    .stepIn(listShown, order: before + 1 + index, reduceMotion: reduceMotion)
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
        .onChange(of: selectedMonth) { _, month in
            listShown = false
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : 0.16)) {
                displayedMonth = month
                listShown = true
            }
        }
        .drawer(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
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
                // The glow reaches well past the circle it sits behind, so the
                // row's spacing alone would measure the gap from the photo and
                // let the gradient run into the text. This hands the overhang
                // back, so the gap you see is gradient to text.
                .padding(.trailing, 24 * scale)

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
        .accessibilityLabel("Month")
        .accessibilityValue(selectedMonth)
        .accessibilityHint("Shows another month")
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
                            "Needs Reflection",
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
    /// The demo only has October's worth of entries, so the rest just relabel.
    static let months = [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    // MARK: - Entries per month

    /// This month is the real log. The others are invented on the spot so the
    /// page actually changes when you switch, seeded off the friend and the
    /// month so flipping back and forth shows the same thing again.
    private func entries(for month: String) -> [RecentHangout] {
        let theirs = store.hangouts.filter { $0.contact.name == contact.name }
        guard month != Self.monthName else { return theirs }
        return Self.invented(for: contact, month: month)
    }

    /// What you did, with the kinds of place it happens.
    private static let outings: [(activity: String, spots: [String])] = [
        ("Coffee", ["Vienna Cafe", "Eleventh House"]),
        ("Brunch", ["Another Broken Egg"]),
        ("Lunch", ["Purdue Memorial Union"]),
        ("Walk", ["Celery Bog", "Wabash Riverfront", "Purdue Mall"]),
        ("Study session", ["Hicks Library", "Purdue Memorial Union"]),
        ("Dinner", ["Lafayette Brewing", "Main Street"]),
        ("Bouldering", ["Climbing gym"]),
        ("Farmers market", ["Lafayette Farmers Market"])
    ]
    private static let startTimes = ["9 AM", "10 AM", "12 PM", "1 PM", "3 PM", "5 PM", "7 PM"]
    private static let lengths = ["45 min", "1 hour", "1 hr 30 min", "2 hours", "3 hours"]
    private static let weekdays = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
    ]

    static func invented(for contact: KithContact, month: String) -> [RecentHangout] {
        let seed = (months.firstIndex(of: month) ?? 0) * 31 + contact.name.count
        var roll = Roll(seed)
        let feelings = Feeling.allCases.filter { $0 != .somethingElse }

        return (0..<roll.next(from: 3, to: 6)).map { _ in
            let outing = outings[roll.next(outings.count)]
            let activity = outing.activity
            let spot = outing.spots[roll.next(outing.spots.count)]
            // A third are left unreflected, the way the real log has them.
            var picked: Set<Feeling> = []
            if roll.next(3) > 0 {
                for _ in 0..<roll.next(from: 1, to: 2) {
                    picked.insert(feelings[roll.next(feelings.count)])
                }
            }
            return RecentHangout(
                contact: contact,
                title: "\(activity) with \(contact.firstName)",
                detail: "\(weekdays[roll.next(weekdays.count)]) · \(lengths[roll.next(lengths.count)]) · \(spot)",
                startTime: startTimes[roll.next(startTimes.count)],
                place: "\(spot), Lafayette",
                photos: RecentHangout.photos(at: spot, seed: seed + roll.next(7)),
                feelings: picked
            )
        }
    }

    /// A small deterministic generator — same seed, same entries, every time.
    struct Roll {
        private var state: UInt64

        init(_ seed: Int) {
            state = UInt64(truncatingIfNeeded: seed) &* 2654435761 &+ 1
        }

        mutating func next(_ upper: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(max(1, upper)))
        }

        mutating func next(from low: Int, to high: Int) -> Int {
            low + next(max(1, high - low + 1))
        }
    }

    /// Entries spread over the month's real weeks (Sunday to Saturday, as the
    /// comp's "12-19" runs), up to three of them, newest first.
    private func weeks(of hangouts: [RecentHangout]) -> [Week] {
        guard !hangouts.isEmpty else { return [] }
        let labels = Self.weekRanges(of: displayedMonth)
        let used = Array(labels.suffix(min(3, labels.count, hangouts.count)).reversed())
        let perWeek = max(1, Int((Double(hangouts.count) / Double(used.count)).rounded(.up)))
        return stride(from: 0, to: hangouts.count, by: perWeek).enumerated().map { index, start in
            Week(
                label: used[min(index, used.count - 1)],
                hangouts: Array(hangouts[start..<min(start + perWeek, hangouts.count)])
            )
        }
    }

    /// "1–7", "8-14"… for each Sunday-to-Saturday week of the month this
    /// year, clipped to the month. The current month stops at this week.
    static func weekRanges(of month: String) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        let now = Date()
        guard let monthNumber = months.firstIndex(of: month).map({ $0 + 1 }),
              let start = calendar.date(from: DateComponents(year: calendar.component(.year, from: now), month: monthNumber, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: start)
        else { return ["1–7"] }

        let isCurrent = calendar.isDate(start, equalTo: now, toGranularity: .month)
        let lastDay = isCurrent ? calendar.component(.day, from: now) : days.count
        var ranges: [String] = []
        var day = 1
        while day <= lastDay {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: start) else { break }
            let weekday = calendar.component(.weekday, from: date)
            let end = min(days.count, day + (7 - weekday))
            ranges.append("\(day)–\(end)")
            day = end + 1
        }
        return ranges.isEmpty ? ["1–7"] : ranges
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

private extension View {
    /// History's rows: out quickly together, back in with just a hint of a
    /// stagger, so a new month reads as new without putting on a show.
    func stepIn(_ shown: Bool, order: Int, reduceMotion: Bool) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 3)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.2)
                    : (shown ? .easeOut(duration: 0.25).delay(Double(min(order, 5)) * 0.025) : .easeOut(duration: 0.1)),
                value: shown
            )
    }
}
