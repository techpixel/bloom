import SwiftUI

/// One day in the week strip, with both calendars for it.
struct WeekDay: Identifiable {
    let date: Date
    let mine: [AvailabilityWindow]
    let theirs: [AvailabilityWindow]

    var id: Date { date }
    var shared: [AvailabilityWindow] { mine.intersection(theirs) }
    var isAvailable: Bool { !shared.isEmpty }

    /// The slot the picker opens on: the first shared window, capped at three hours.
    var defaultSlot: AvailabilityWindow? {
        guard let first = shared.first else { return nil }
        return AvailabilityWindow(start: first.start, end: min(first.end, first.start + 3))
    }
}

/// An idea Kith offers. It never picks for you — these are prompts, not decisions.
struct ActivitySuggestion: Identifiable {
    let id: Int
    var title: String?
    var detail: String
}

/// The "This Week" comps: pick a day from the week strip, then drag out a time on it.
struct WeekScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedDay: WeekDay?
    @State private var slot = AvailabilityWindow(start: 13, end: 16)

    @Binding var range: ScheduleRange
    var onBack: (() -> Void)?
    /// Lets the dev menu open straight onto a chosen day.
    var openFirstDay = false
    var onSend: ((Date, AvailabilityWindow) -> Void)?

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }

    // The comps are iPhone 16 frames: 393 x 852.
    private let designHeight: CGFloat = 852
    private let contentWidth: CGFloat = 353
    /// Height reserved between the tabs and the suggestions, so both comps
    /// park "Activity Suggestions" at the same place on the screen.
    private let middleHeight: CGFloat = 125.5

    private let week = WeekDay.currentWeek()
    private let suggestions = ActivitySuggestion.sample

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack(alignment: .top) {
                KithTheme.canvas(isDark)

                FriendAvatarHeader()
                    .position(x: size.width / 2, y: size.height * (145.61 / designHeight))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                KithBackButton(action: back)
                    .padding(.leading, 12.25)
                    .frame(width: size.width, alignment: .leading)
                    .position(x: size.width / 2, y: size.height * (96.5 / designHeight))

                VStack(spacing: 0) {
                    // The title hangs off the bottom of the spacer so the tabs stay
                    // parked at 264, level with the Today / Tomorrow comps.
                    Color.clear
                        .frame(height: size.height * (264 / designHeight))
                        .overlay(alignment: .bottom) {
                            Text("Find a Time That Works")
                                .font(.kithHeading)
                                .foregroundStyle(ink)
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.bottom, 15)
                        }

                    RangeTabs(selection: $range)

                    middle
                        .padding(.top, 12)
                        .frame(height: middleHeight + 12, alignment: .top)

                    suggestionList

                    Spacer(minLength: 0)

                    KithPillButton(
                        title: "Send",
                        accessibilityLabel: selectedDay == nil
                            ? "Send invitation — pick a day first"
                            : "Send invitation",
                        isEnabled: selectedDay != nil,
                        action: send
                    )
                        .padding(.top, 18)
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
        .onAppear {
            if openFirstDay, let day = week.first(where: \.isAvailable) {
                select(day)
            }
        }
    }

    // MARK: - Week strip / day picker

    @ViewBuilder
    private var middle: some View {
        if let day = selectedDay {
            dayPicker(day)
        } else {
            weekPicker
        }
    }

    private var weekPicker: some View {
        VStack(spacing: 10) {
            Text(monthLabel)
                .font(.kithCaptionStrong)
                .textCase(.uppercase)
                .foregroundStyle(KithTheme.calendarHeading(isDark))
                .frame(height: 24)

            HStack(spacing: 9.983) {
                ForEach(week) { day in
                    dayTile(day)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dayTile(_ day: WeekDay) -> some View {
        Button {
            select(day)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9.663, style: .continuous)
                        .fill(KithTheme.uiFill(isDark))

                    if !day.isAvailable {
                        DiagonalHatch()
                            .stroke(KithTheme.availabilityHatch, lineWidth: 1.6)
                            .clipShape(RoundedRectangle(cornerRadius: 9.663, style: .continuous))
                    }

                    Text(day.letter)
                        .font(.kithDayLetter)
                        .foregroundStyle(day.isAvailable ? ink : KithTheme.mutedDay(isDark))
                }
                .aspectRatio(1, contentMode: .fit)

                Text(day.dayNumber)
                    .font(.kithCaption)
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!day.isAvailable)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityValue(day.isAvailable ? "Shared time available" : "No shared time")
    }

    // MARK: - Chosen day

    private func dayPicker(_ day: WeekDay) -> some View {
        VStack(spacing: 8) {
            Text(day.longLabel)
                .font(.kithCaptionStrong)
                .textCase(.uppercase)
                .monospacedDigit()
                .foregroundStyle(KithTheme.calendarHeading(isDark))

            Text("\(AvailabilityTimeline.timeLabel(slot.start)) - \(AvailabilityTimeline.timeLabel(slot.end))")
                .font(.kithCaption)
                .monospacedDigit()
                .foregroundStyle(KithTheme.secondary(isDark))

            AvailabilityTimeline(
                mine: day.mine,
                theirs: day.theirs,
                initialHour: max(0, slot.start - 4),
                style: .slotPicker,
                slot: $slot
            )
            .environment(\.layoutDirection, .leftToRight)
            .id(day.id)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Suggestions

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activity Suggestions")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)

            VStack(spacing: 12) {
                ForEach(suggestions) { suggestion in
                    suggestionCard(suggestion)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Activity Suggestions")
    }

    private func suggestionCard(_ suggestion: ActivitySuggestion) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(KithTheme.thumbnail(isDark))
                .frame(width: 52, height: 52)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                if let title = suggestion.title {
                    Text(title)
                        .font(.kithCardTitle)
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(suggestion.detail)
                    .font(.kithFine)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(KithTheme.uiFill(isDark))
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func select(_ day: WeekDay) {
        guard let opening = day.defaultSlot else { return }
        slot = opening
        selectedDay = day
    }

    /// Back steps out of the day before it leaves the screen.
    private func back() {
        if selectedDay != nil {
            selectedDay = nil
        } else {
            onBack?()
        }
    }

    private func send() {
        guard let day = selectedDay else { return }
        onSend?(day.date, slot)
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: week.first?.date ?? Date())
    }
}

// MARK: - Sample data

extension WeekDay {
    var letter: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }

    var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    var longLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE MMMM d"
        return formatter.string(from: date)
    }

    var accessibilityLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    /// Placeholder calendars until real availability is wired up.
    static func currentWeek(from reference: Date = Date()) -> [WeekDay] {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: reference)?.start ?? reference

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startOfWeek) else { return nil }
            let (mine, theirs) = sampleCalendars(forWeekday: calendar.component(.weekday, from: date))
            return WeekDay(date: date, mine: mine, theirs: theirs)
        }
    }

    private static func sampleCalendars(
        forWeekday weekday: Int
    ) -> (mine: [AvailabilityWindow], theirs: [AvailabilityWindow]) {
        switch weekday {
        case 1: // Sunday
            return ([AvailabilityWindow(start: 10, end: 18)], [AvailabilityWindow(start: 12, end: 20)])
        case 2: // Monday — nothing lines up
            return ([AvailabilityWindow(start: 9, end: 11)], [AvailabilityWindow(start: 14, end: 16)])
        case 3: // Tuesday
            return ([AvailabilityWindow(start: 15, end: 22)], [AvailabilityWindow(start: 17, end: 21)])
        case 4: // Wednesday
            return ([AvailabilityWindow(start: 10, end: 23)], [AvailabilityWindow(start: 11, end: 22.5)])
        case 5: // Thursday
            return ([AvailabilityWindow(start: 8, end: 13)], [AvailabilityWindow(start: 11, end: 19)])
        case 6: // Friday
            return ([AvailabilityWindow(start: 16, end: 23)], [AvailabilityWindow(start: 18, end: 23)])
        default: // Saturday
            return ([AvailabilityWindow(start: 11, end: 22.5)], [AvailabilityWindow(start: 12, end: 21)])
        }
    }
}

extension ActivitySuggestion {
    static let sample = [
        ActivitySuggestion(
            id: 0,
            title: "Eleventh House West Lafayette",
            detail: "You seemed to enjoy your time with \(DemoCast.isJudge ? "Nora" : Recast.text("Manitej")) here."
        ),
        ActivitySuggestion(
            id: 1,
            title: "Dinner at a new restaurant",
            detail: "Try a new cuisine together!"
        ),
        ActivitySuggestion(
            id: 2,
            title: nil,
            detail: "Exercising with a friend is always the best."
        )
    ]
}

#Preview {
    PlanFlowView()
}
