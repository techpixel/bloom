import Observation
import PhotosUI
import SwiftUI

// MARK: - Shared hangouts

/// The hangouts Bloom has logged, shared by Home, Recaps and the entry pages, so
/// a reflection saved in one place shows everywhere.
@Observable
final class HangoutStore {
    var hangouts = RecentHangout.sample
}

// MARK: - Models

enum RecapPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    /// "OCTOBER 19-25" for the week you're in, "OCTOBER" for the month.
    var dateLabel: String {
        let calendar = Calendar.current
        let now = Date()
        let month = DateFormatter()
        month.dateFormat = "MMMM"
        switch self {
        case .month:
            return month.string(from: now).uppercased()
        case .week:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
                return month.string(from: now).uppercased()
            }
            let end = calendar.date(byAdding: .day, value: -1, to: week.end) ?? week.end
            let day = { (date: Date) in calendar.component(.day, from: date) }
            return "\(month.string(from: week.start).uppercased()) \(day(week.start))-\(day(end))"
        }
    }
}

/// One friend in the cluster, placed where the comp draws them for each period.
private struct RecapBubble: Identifiable {
    let contact: KithContact
    /// Centre and diameter in the comp's 393pt frame, measured from its top.
    var spots: [RecapPeriod: (center: CGPoint, diameter: CGFloat)]
    /// How many times you saw them, per period.
    var times: [RecapPeriod: Int]
    /// The comp tilts each count a little, as if stuck on by hand.
    var tilt: Double

    var id: String { contact.id }
}

// MARK: - Recaps

/// "Recaps" (comps 84:1668 and 84:2051): who you spent the week or month with,
/// sized by how often, and the hangouts worth reflecting on.
struct RecapsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(HangoutStore.self) private var store

    var onOpenProfile: () -> Void = {}

    @State private var period = RecapPeriod.week
    @State private var screenWidth: CGFloat = 393
    @State private var appeared = RecapsView.hasAppeared
    @State private var openFriend: KithContact?
    @State private var openHangout: RecentHangout.ID?
    private static var hasAppeared = false

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    /// Where the cluster starts in the comp, and how tall it is per period, so
    /// "Highlights" lands where each comp puts it.
    private static let clusterTop: CGFloat = 140
    private func clusterHeight(_ period: RecapPeriod) -> CGFloat {
        period == .week ? 322 : 446
    }

    var body: some View {
        ZStack(alignment: .top) {
            KithTheme.canvas(isDark).ignoresSafeArea()
            backdrop

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 15)

                    cluster
                        .padding(.top, 8)

                    highlights
                        .padding(.horizontal, 20)
                }
                .padding(.bottom, 28)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .task {
            guard !appeared else { return }
            try? await Task.sleep(for: .milliseconds(80))
            appeared = true
            Self.hasAppeared = true
        }
        .fullScreenCover(item: $openFriend) { friend in
            FriendRecapView(contact: friend, onBack: { openFriend = nil })
                .environment(store)
        }
        .fullScreenCover(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
            if let index = store.hangouts.firstIndex(where: { $0.id == openHangout }) {
                MeetupDetailView(hangout: Bindable(store).hangouts[index]) { openHangout = nil }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Menu {
                    Picker("Period", selection: $period.animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82))) {
                        ForEach(RecapPeriod.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(period.rawValue)
                            .font(.kithTitle)
                            .tracking(-1.28)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(ink)
                }
                .accessibilityLabel("\(period.rawValue) recap")
                .accessibilityHint("Switches between this week and this month")

                Text(period.dateLabel)
                    .font(.kithCaption)
                    .foregroundStyle(KithTheme.secondary(isDark))
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 12)
        }
        .sensoryFeedback(.selection, trigger: period)
    }

    // MARK: - Cluster

    private var cluster: some View {
        let bubbles = Self.bubbles

        return TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    bubbleView(bubble, index: index, time: time)
                }
            }
        }
        .frame(width: screenWidth, height: clusterHeight(period) * scale, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private func bubbleView(_ bubble: RecapBubble, index: Int, time: Double) -> some View {
        let spot = bubble.spots[period] ?? bubble.spots.values.first!
        let here = bubble.spots[period] != nil
        let diameter = spot.diameter * scale
        let center = CGPoint(x: spot.center.x * scale, y: (spot.center.y - Self.clusterTop) * scale)
        // A faint float, each bubble on its own phase.
        let float = CGSize(width: 1.6 * sin(time * 0.5 + Double(index)), height: 2 * cos(time * 0.42 + Double(index) * 1.3))

        Button { openFriend = bubble.contact } label: {
            ContactAvatar(contact: bubble.contact, diameter: diameter)
                .overlay(alignment: .bottom) {
                    if let times = countShown(bubble), labelFits(centerX: center.x) {
                        Text(times == 1 ? "1 time" : "\(times) times")
                            .font(.kithCaptionStrong)
                            .contentTransition(.numericText(value: Double(times)))
                            // Wider than a small bubble is fine; wrapping isn't.
                            .fixedSize()
                            .kithCapCentered(13, relativeTo: .footnote)
                            .foregroundStyle(KithTheme.canvas(isDark))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(ink, in: Capsule())
                            .rotationEffect(.degrees(bubble.tilt))
                            .offset(y: 8)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                }
        }
        .buttonStyle(PressableButtonStyle())
        .position(center)
        .offset(float)
        .opacity(here && appeared ? 1 : 0)
        .scaleEffect(here && appeared ? 1 : 0.6)
        .animation(
            reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.76).delay(appeared ? Double(index) * 0.028 : 0),
            value: appeared
        )
        .allowsHitTesting(here)
        .accessibilityHidden(!here)
        .accessibilityLabel(bubble.contact.firstName)
        .accessibilityValue(bubble.times[period].map { $0 == 1 ? "1 time" : "\($0) times" } ?? "")
        .accessibilityHint("Opens your recap with \(bubble.contact.firstName)")
    }

    /// Bubbles at the edges hang off the screen, as more friends past the
    /// edge; a count under one would be cut off, so they go without.
    private func labelFits(centerX: CGFloat) -> Bool {
        let half: CGFloat = 37
        return centerX >= half && centerX <= screenWidth - half
    }

    /// Every bubble shows its count, in both periods; switching rolls the
    /// numbers over rather than swapping the labels.
    private func countShown(_ bubble: RecapBubble) -> Int? {
        bubble.times[period]
    }

    /// The pastel bloom behind the cluster, made of the blobs of the friends
    /// you saw most, drifting like Home's.
    private var backdrop: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let top = Self.bubbles
                .sorted { ($0.times[period] ?? 0) > ($1.times[period] ?? 0) }
                .prefix(3)
                .map(\.contact)
            let anchors = [
                CGPoint(x: size.width * 0.82, y: size.height * 0.30),
                CGPoint(x: size.width * 0.10, y: size.height * 0.48),
                CGPoint(x: size.width * 0.70, y: size.height * 0.70)
            ]

            ZStack {
                ForEach(Array(top.enumerated()), id: \.element.id) { index, friend in
                    DriftingBlob(blob: friend.blob, length: size.width * 0.8, seed: Double(index) * 2.1, wander: 0.08)
                        .position(anchors[index])
                        .transition(.opacity)
                }
            }
            .blur(radius: 30)
            .opacity(isDark ? 0.35 : 0.45)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: top.map(\.id))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    // MARK: - Highlights

    private var highlights: some View {
        let picks = store.hangouts.filter { $0.highlightIn.contains(period) }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Highlights")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            ForEach(picks) { hangout in
                HangoutRow(hangout: hangout) { openHangout = hangout.id }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: period)
    }
}

// MARK: - A friend's recap

/// One friend's overview (comp 136:2412): their face in its glow, your latest
/// time together, everything else behind "See more", and the photos from all
/// of it.
struct FriendRecapView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(HangoutStore.self) private var store

    let contact: KithContact
    var onBack: () -> Void

    @State private var screenWidth: CGFloat = 393
    @State private var openHangout: RecentHangout.ID?
    @State private var showingHistory = false
    @State private var addingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    var body: some View {
        let theirs = store.hangouts.filter { $0.contact.name == contact.name }
        let photos = theirs.flatMap(\.photos)

        ZStack(alignment: .topLeading) {
            KithTheme.canvas(isDark).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ContactAvatar(contact: contact, diameter: 142.83 * scale)
                        .background {
                            Image("MeetupGlow")
                                .resizable()
                                .frame(width: 206.5 * scale, height: 202 * scale)
                                .rotationEffect(.degrees(-28.12))
                                .offset(x: -18.3 * scale, y: 4.6 * scale)
                                .accessibilityHidden(true)
                        }
                        .padding(.top, 49 * scale)

                    Text(contact.firstName)
                        .font(.kithHeading)
                        .foregroundStyle(ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.top, 34 * scale)

                    if let note = contact.note {
                        HStack(spacing: 5) {
                            Text(note)
                                .font(.kithFineStrong)
                                .foregroundStyle(secondary)
                                .multilineTextAlignment(.center)

                            Image("PencilIcon")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 8.833, height: 8.833)
                                .foregroundStyle(secondary)
                        }
                        .padding(.top, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Your note: \(note)")
                    }

                    if let latest = theirs.first {
                        recent(latest, more: Array(theirs.dropFirst()))
                            .padding(.top, 26)
                    } else {
                        Text("Nothing logged with \(contact.firstName) yet.")
                            .font(.kithSecondary)
                            .foregroundStyle(secondary)
                            .padding(.top, 26)
                    }

                    photoGrid(photos)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }

            KithBackButton(action: onBack)
                .padding(.leading, 12.25)
                .padding(.top, 29 * scale)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .fullScreenCover(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
            if let index = store.hangouts.firstIndex(where: { $0.id == openHangout }) {
                MeetupDetailView(hangout: Bindable(store).hangouts[index]) { openHangout = nil }
            }
        }
        .fullScreenCover(isPresented: $showingHistory) {
            FriendHistoryView(contact: contact) { showingHistory = false }
        }
        .photosPicker(isPresented: $addingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
    }

    /// The gallery spans every hangout, so a photo you add lands on the latest.
    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let index = store.hangouts.firstIndex(where: { $0.contact.name == contact.name })
        else { return }
        store.hangouts[index].photos.append(.picked(UUID(), image))
    }

    // MARK: Recent

    private func recent(_ latest: RecentHangout, more: [RecentHangout]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            latestCard(latest)

            if !more.isEmpty {
                Button { showingHistory = true } label: {
                    Text("See More")
                        .font(.kithCaptionStrong)
                        .foregroundStyle(secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens every time you've spent with \(contact.firstName)")
            }
        }
    }

    /// Your latest time together: a photo from it, what it was, and a way in.
    private func latestCard(_ hangout: RecentHangout) -> some View {
        let feelings = Feeling.allCases.filter(hangout.feelings.contains)

        return HStack(spacing: 12) {
            Group {
                if let photo = hangout.photos.first {
                    photo.image
                        .resizable()
                        .scaledToFill()
                } else {
                    KithTheme.suggestionCard(isDark)
                        .overlay(ContactAvatar(contact: hangout.contact, diameter: 56))
                }
            }
            .frame(width: 85, height: 85)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        if feelings.isEmpty {
                            FeelingTag(
                                "Needs reflection",
                                fill: KithTheme.canvas(isDark),
                                text: secondary
                            )
                        } else {
                            ForEach(feelings) { feeling in
                                FeelingTag(feeling.rawValue, fill: KithTheme.feelingSelected)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                    Text(Self.shortTitle(hangout))
                        .font(.kithCaptionStrong)
                        .foregroundStyle(ink)
                    Text(hangout.detail)
                        .font(.kithFine)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button { openHangout = hangout.id } label: {
                    Text("View your time together")
                        .font(.kithCaption)
                        .kithCapCentered(13, relativeTo: .footnote)
                        .foregroundStyle(KithTheme.canvas(isDark))
                        .frame(maxWidth: .infinity)
                        .frame(height: 29)
                        .background(ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.vertical, -7.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(KithTheme.uiFill(isDark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// "Studying with Manitej" reads "Studying at 9am" on Manitej's own page.
    private static func shortTitle(_ hangout: RecentHangout) -> String {
        let activity = hangout.title.components(separatedBy: " with ").first ?? hangout.title
        return "\(activity) at \(hangout.startTime)"
    }

    // MARK: Photos

    /// Every photo from your time together, three to a row. A short gallery
    /// closes with a single tile to add to it, rather than a run of empties.
    private func photoGrid(_ photos: [MeetupPhoto]) -> some View {
        let side = (screenWidth - 44 - 20) / 3

        return VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.offset) { _, photo in
                    photo.image
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }

                addPhotoTile(side: side)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The comp's plus square (69:1107), holding the end of the grid open.
    private func addPhotoTile(side: CGFloat) -> some View {
        Button { addingPhoto = true } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(KithTheme.suggestionCard(isDark))
                .frame(width: side, height: side)
                .overlay {
                    Text("+")
                        .font(KithType.font(.w90, 33.376, .largeTitle))
                        .foregroundStyle(ink)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Add a photo")
    }
}

// MARK: - Shared pieces

/// A hangout at a glance (comp 407:1532): their face, how it felt, what it
/// was. One you haven't answered yet shows a "reflect" tag instead. Tapping
/// opens the entry.
struct HangoutRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let hangout: RecentHangout
    var open: () -> Void

    var body: some View {
        let isDark = colorScheme == .dark
        let feelings = Feeling.allCases.filter(hangout.feelings.contains)

        Button(action: open) {
            HStack(spacing: 12) {
                ContactAvatar(contact: hangout.contact, diameter: 75)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        if feelings.isEmpty {
                            FeelingTag(
                                "Needs reflection",
                                fill: KithTheme.canvas(isDark),
                                text: KithTheme.secondary(isDark)
                            )
                        } else {
                            ForEach(feelings) { feeling in
                                FeelingTag(feeling.rawValue, fill: KithTheme.feelingSelected)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Text(hangout.title)
                            .font(.kithCaptionStrong)
                            .foregroundStyle(KithTheme.ink(isDark))
                        Text(hangout.detail)
                            .font(.kithFine)
                            .foregroundStyle(KithTheme.recentMeta)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KithTheme.secondary(isDark))
            }
            .padding(12)
            .background(KithTheme.uiFill(isDark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(feelings.isEmpty ? "Opens the entry to reflect on it" : "Opens the entry")
    }

}

/// The pill on a hangout: how it felt, or a nudge to say.
struct FeelingTag: View {
    let title: String
    let fill: Color
    var text: Color?

    init(_ title: String, fill: Color, text: Color? = nil) {
        self.title = title
        self.fill = fill
        self.text = text
    }

    var body: some View {
        Text(title)
            .font(.kithFineStrong)
            .kithCapCentered(12, relativeTo: .caption)
            .foregroundStyle(text ?? KithTheme.ink(false))
            .lineLimit(1)
            .padding(.horizontal, 9.6)
            .frame(height: 24)
            .background(fill, in: Capsule())
    }
}

/// Your own photo, as Profile shows it: the one you picked, or the comp's.
struct YourAvatar: View {
    @AppStorage("profile.name") private var name = "Amber"
    var diameter: CGFloat

    var body: some View {
        if let custom = ProfilePhotoStore.load() {
            Image(uiImage: custom)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        } else {
            ContactAvatar(
                contact: KithContact(
                    name: name,
                    face: .photo(Portrait(asset: "ProfilePhoto", width: 1.0105, height: 1.3474, x: 0.0053, y: 0.1737))
                ),
                diameter: diameter
            )
        }
    }
}

// MARK: - Sample data

extension RecentHangout {
    /// Friends from the recap comps who aren't anywhere else in the app yet.
    /// The comps don't name them, so these names are placeholders.
    static let recapFriends: [String: KithContact] = [
        "Dev": KithContact(
            name: "Dev Shah",
            face: .photo(Portrait(asset: "RecapDev", width: 1.89, height: 1.263, x: -0.3274))
        ),
        "Theo": KithContact(name: "Theo Lindqvist", face: .photo(Portrait(asset: "RecapTheo"))),
        "Amara": KithContact(name: "Amara Okafor", face: .photo(Portrait(asset: "RecapAmara"))),
        "Nina": KithContact(name: "Nina Alvarez", face: .photo(Portrait(asset: "RecapNina"))),
        "Kenji": KithContact(name: "Kenji Watanabe", face: .photo(Portrait(asset: "RecapKenji"))),
        "Sofia": KithContact(name: "Sofia Marchetti", face: .photo(Portrait(asset: "RecapSofia"))),
        "Priya": KithContact(name: "Priya Raghunathan", face: .photo(Portrait(asset: "RecapPriya"))),
        "Sam": KithContact(name: "Sam Reyes", face: .photo(Portrait(asset: "RecapSam")))
    ]
}

private extension RecapsView {
    static let manitej = KithContact(
        name: "Manitej Boorgu",
        face: .photo(Portrait(asset: "FriendAvatar", width: 2.4184, height: 1.6158, x: 0.0634, y: -0.0342))
    )
    static let ishan = KithContact(
        name: "Ishan Goyal",
        face: .photo(Portrait(asset: "AvatarIshan", width: 1.0751, height: 1.2933, x: -0.0173, y: -0.09))
    )
    static let ray = KithContact(
        name: "Ray Arayilikath",
        face: .photo(Portrait(asset: "AvatarRay", width: 1.2465, height: 1.5581, y: 0.164))
    )
    static let jadden = KithContact(
        name: "Jadden Picardal",
        face: .photo(Portrait(asset: "AvatarJadden", width: 1.54, height: 1.54))
    )
    static let michelle = KithContact(name: "Michelle Xuan", face: .photo(Portrait(asset: "RecapMichelle")))

    /// Measured off the comps: centre and diameter in the 393pt frame.
    static let bubbles: [RecapBubble] = {
        let friend = { (key: String) in RecentHangout.recapFriends[key]! }
        func spot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) -> (center: CGPoint, diameter: CGFloat) {
            (CGPoint(x: x, y: y), d)
        }
        return [
            RecapBubble(contact: manitej, spots: [.week: spot(187, 281, 152), .month: spot(180, 362, 152)], times: [.week: 5, .month: 12], tilt: -2),
            RecapBubble(contact: ishan, spots: [.week: spot(301, 213, 101), .month: spot(103, 221, 101)], times: [.week: 4, .month: 8], tilt: -3),
            RecapBubble(contact: michelle, spots: [.week: spot(104, 380, 100), .month: spot(222, 221, 100)], times: [.week: 4, .month: 8], tilt: -4),
            RecapBubble(contact: ray, spots: [.week: spot(88, 207, 85), .month: spot(50, 321, 84)], times: [.week: 3, .month: 5], tilt: 3),
            RecapBubble(contact: friend("Dev"), spots: [.week: spot(262, 389, 93), .month: spot(324, 345, 93)], times: [.week: 3, .month: 6], tilt: 4),
            RecapBubble(contact: friend("Theo"), spots: [.week: spot(78, 292, 60), .month: spot(390, 256, 60)], times: [.week: 2, .month: 3], tilt: -5),
            RecapBubble(contact: friend("Amara"), spots: [.week: spot(223, 170, 55), .month: spot(317, 240, 62)], times: [.week: 1, .month: 3], tilt: 2),
            RecapBubble(contact: jadden, spots: [.week: spot(295, 305, 56), .month: spot(165, 501, 90)], times: [.week: 1, .month: 6], tilt: 4),
            RecapBubble(contact: friend("Nina"), spots: [.month: spot(290.5, 467.5, 99)], times: [.month: 7], tilt: -2),
            RecapBubble(contact: friend("Kenji"), spots: [.month: spot(70, 442, 84)], times: [.month: 5], tilt: 3),
            RecapBubble(contact: friend("Sofia"), spots: [.month: spot(-3.5, 385.5, 53)], times: [.month: 2], tilt: -3),
            RecapBubble(contact: friend("Priya"), spots: [.month: spot(-12, 242, 84)], times: [.month: 5], tilt: 2),
            RecapBubble(contact: friend("Sam"), spots: [.month: spot(399.5, 428.5, 79)], times: [.month: 4], tilt: -4)
        ]
    }()
}
