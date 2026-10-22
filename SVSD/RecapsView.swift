import Observation
import PhotosUI
import SwiftUI

// MARK: - Shared hangouts

/// A place you named when Bloom noticed you kept going back, and the tags
/// you gave it.
struct SavedPlace: Identifiable {
    var name: String
    /// Where it is, as the hangouts there record it.
    var place: String
    var tags: [String]

    var id: String { place }

    /// The place without its town, as lines like "You saw them at Vienna
    /// Cafe" name it.
    var shortPlace: String {
        String(place.split(separator: ",").first ?? Substring(place))
    }
}

/// The hangouts Bloom has logged, shared by Home, Recaps and the entry pages, so
/// a reflection saved in one place shows everywhere.
@Observable
final class HangoutStore {
    var hangouts = RecentHangout.sample.filter { !$0.expired() }
    /// Times Bloom thinks you were with a friend and wants to check.
    var sightings = Sighting.sample
    /// The ones you said weren't a meeting. Kept so suggestions can learn
    /// that being near someone there doesn't mean you met.
    var notMet: [Sighting] = []
    /// Places you've named, newest first. Home's ideas suggest them. Only
    /// ever ones you named: somewhere you've merely been is location data,
    /// not a saved place.
    var savedPlaces: [SavedPlace] = []
    /// The entry page on screen, if any: where the remote's offer to name
    /// the place lands.
    var openEntry: UUID?
    /// Tags you've made for places, offered again whenever Bloom asks you
    /// to name one, and kept between launches.
    var customPlaceTags: [String] = UserDefaults.standard.stringArray(forKey: "places.customTags") ?? [] {
        didSet { UserDefaults.standard.set(customPlaceTags, forKey: "places.customTags") }
    }

    /// A hangout nobody reflected on by the end of the next day is let go,
    /// rather than nagging forever. Run when the app comes forward.
    func dropExpired(now: Date = .now) {
        hangouts.removeAll { $0.expired(now: now) }
    }

    /// Yes: it becomes a hangout, newest of all, so Recent asks how it felt.
    func confirm(_ sighting: Sighting) {
        sightings.removeAll { $0.id == sighting.id }
        hangouts.insert(sighting.hangout, at: 0)
    }

    /// Naming a place renames it everywhere Bloom mentions it: every hangout
    /// there, anything waiting to be confirmed there, and Home's lines about
    /// it. Naming it again replaces what you called it before.
    func name(place: String, as name: String, tags: [String]) {
        let earlier = savedPlaces.first { $0.place == place || $0.name == place }
        let saved = SavedPlace(name: name, place: earlier?.place ?? place, tags: tags)
        savedPlaces.removeAll { $0.place == saved.place }
        savedPlaces.insert(saved, at: 0)

        // The full place before the short one, or "Celery Bog, West
        // Lafayette" would come out as "natureee, West Lafayette".
        let old = [saved.place, saved.shortPlace, earlier?.name].compactMap { $0 }.filter { $0 != name }
        func renamed(_ text: String) -> String {
            old.reduce(text) { $0.replacingOccurrences(of: $1, with: name) }
        }
        for index in hangouts.indices {
            hangouts[index].title = renamed(hangouts[index].title)
            hangouts[index].detail = renamed(hangouts[index].detail)
            hangouts[index].place = renamed(hangouts[index].place)
            if hangouts[index].place == name {
                hangouts[index].placeName = name
                hangouts[index].placeTags = tags
            }
        }
        for index in sightings.indices {
            sightings[index].place = renamed(sightings[index].place)
        }
    }

    /// A line as Bloom would say it now, with every place you've named
    /// called by its name. For anything that arrives after the naming.
    func called(_ text: String) -> String {
        savedPlaces.reduce(text) { line, saved in
            line.replacingOccurrences(of: saved.place, with: saved.name)
                .replacingOccurrences(of: saved.shortPlace, with: saved.name)
        }
    }

    /// No: it's set aside and remembered rather than logged.
    func dismiss(_ sighting: Sighting) {
        sightings.removeAll { $0.id == sighting.id }
        notMet.append(sighting)
    }

    // MARK: Demo remote

    /// Applies a command from the demo remote: nil if it worked, otherwise
    /// what went wrong.
    func apply(remote request: [String: Any]) -> String? {
        let kind = request["kind"] as? String
        if kind == "reset" {
            hangouts = RecentHangout.sample.filter { !$0.expired() }
            sightings = Sighting.sample
            notMet = []
            savedPlaces = []
            return nil
        }
        // "You’ve been here 3 times… Name this new location?" on the open
        // entry, as if Bloom had just noticed you keep coming back.
        if kind == "name" {
            guard let id = openEntry, let index = hangouts.firstIndex(where: { $0.id == id }) else {
                return "Open a hangout on the phone first."
            }
            hangouts[index].visitsThisMonth = max(3, request["visits"] as? Int ?? 3)
            hangouts[index].placeName = nil
            hangouts[index].placeTags = []
            hangouts[index].namingDismissed = false
            return nil
        }
        let name = request["friend"] as? String ?? ""
        guard let contact = friend(named: name) else { return "No friend called “\(name)”." }
        let now = Date.now.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
        let place = request["place"] as? String

        switch kind {
        case "sighting":
            sightings.insert(Sighting(
                contact: contact,
                place: called(place ?? "Vienna Cafe, Lafayette"),
                when: request["when"] as? String ?? "Just now",
                startTime: now
            ), at: 0)
        case "reflect":
            let activity = request["activity"] as? String ?? "Coffee"
            let spot = place ?? "Vienna Cafe"
            hangouts.insert(RecentHangout(
                contact: contact,
                title: "\(activity) with \(contact.firstName)",
                detail: called("Today · \(request["length"] as? String ?? "1 hour") · \(spot)"),
                startTime: now,
                place: called(spot.contains(",") ? spot : "\(spot), Lafayette"),
                photos: RecentHangout.photos(at: spot, seed: contact.name.count)
            ), at: 0)
        default:
            return "Unknown command."
        }
        return nil
    }

    /// Someone you know, by full or first name, case aside.
    /// Everyone the remote can name, your circle first.
    var remoteFriends: [String] {
        var seen: Set<String> = []
        return (KithContact.circleSample + hangouts.map(\.contact) + sightings.map(\.contact))
            .map(\.name)
            .filter { seen.insert($0).inserted }
    }

    private func friend(named name: String) -> KithContact? {
        // The remote may still use a comp's name for the real person playing it.
        let given = name.trimmingCharacters(in: .whitespaces)
        let query = (Recast.person(playing: given)?.name ?? Recast.text(given)).lowercased()
        guard !query.isEmpty else { return nil }
        let known = hangouts.map(\.contact) + sightings.map(\.contact) + KithContact.circleSample
        return known.first { $0.name.lowercased() == query }
            ?? known.first { $0.firstName.lowercased() == query }
    }
}

extension RecentHangout {
    /// Still unanswered after the day following it.
    func expired(now: Date = .now) -> Bool {
        guard feelings.isEmpty else { return false }
        let calendar = Calendar.current
        let dayAfter = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: date)) ?? date
        return now >= dayAfter
    }
}

/// Bloom noticed you and a friend in the same place (comp 283:2193) and asks
/// whether it was a meeting before logging anything.
struct Sighting: Identifiable {
    let contact: KithContact
    var place: String
    var when: String
    var startTime: String

    let id = UUID()

    var hangout: RecentHangout {
        let spot = place.components(separatedBy: ",").first ?? place
        return RecentHangout(
            contact: contact,
            title: "Time with \(contact.firstName)",
            detail: "Today · \(spot)",
            startTime: startTime,
            place: place,
            photos: RecentHangout.photos(at: spot, seed: contact.name.count)
        )
    }

    static let sample: [Sighting] = DemoCast.isJudge
        ? [Sighting(contact: DemoCast.leo, place: "Circle K, West Lafayette", when: "Today at 6:13 PM", startTime: "6 PM")]
        : [Sighting(
            contact: KithContact(
                name: "Ishan Goyal",
                face: .photo(Portrait(asset: "AvatarIshan", width: 1.0751, height: 1.2933, x: -0.0173, y: -0.09))
            ),
            place: "Circle K, West Lafayette",
            when: "Today at 6:13 PM",
            startTime: "6 PM"
        )]
}

// MARK: - Models

enum RecapPeriod: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    /// "OCTOBER 19-25" for the week you're in, "OCTOBER" for the month.
    /// `weeksBack` steps the week range backwards; the month ignores it.
    func dateLabel(weeksBack: Int = 0) -> String {
        let calendar = Calendar.current
        let now = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: Date()) ?? Date()
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
            return "\(month.string(from: week.start).uppercased()) \(day(week.start))–\(day(end))"
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
    /// How many weeks back the recap is showing; 0 is this week.
    @State private var weeksBack = 0
    /// Keeps one pull from stepping several weeks at once.
    @State private var steppingWeek = false
    @State private var screenWidth: CGFloat = 393
    @State private var appeared = RecapsView.hasAppeared
    @State private var openFriend: KithContact?
    @State private var openHangout: RecentHangout.ID?
    /// How far you've dragged the cluster to look around it.


    private static var hasAppeared = false

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    /// Where the cluster starts in the comp, and how tall it is per period, so
    /// "Highlights" lands where each comp puts it.
    private static let clusterTop: CGFloat = 140
    private static let monthHeight: CGFloat = 470
    private func clusterHeight(_ period: RecapPeriod) -> CGFloat {
        period == .week ? 322 : Self.monthHeight
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
                        .padding(.top, 28)
                }
                .padding(.bottom, 28)
                .background {
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.frame(in: .named("recapScroll")).minY) { _, y in
                            week(fromScroll: y)
                        }
                    }
                }
            }
            .progressiveTopBlur()
            .coordinateSpace(name: "recapScroll")
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .task {
            guard !appeared else { return }
            try? await Task.sleep(for: .milliseconds(80))
            appeared = true
            Self.hasAppeared = true
        }
        .drawer(item: $openFriend) { friend in
            FriendRecapView(contact: friend, onBack: { openFriend = nil })
                .environment(store)
        }
        .drawer(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
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

                Text(period.dateLabel(weeksBack: weeksBack))
                    .font(.kithCaption)
                    .foregroundStyle(KithTheme.secondary(isDark))
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 12)
        }
        .sensoryFeedback(.selection, trigger: period)
        .onChange(of: period) { weeksBack = 0 }
    }

    /// Scrolling the page on past the week takes you to the month, and coming
    /// back to the top returns. The two thresholds leave a dead band between
    /// them, so a switch can't immediately undo itself as the layout resizes.
    /// Pulling past the end of a week's recap takes you to the week before it;
    /// pulling back past the top returns. Only while the week is showing — the
    /// month is chosen from the header, not by scrolling.
    private func week(fromScroll y: CGFloat) {
        guard period == .week, !steppingWeek else { return }
        let step: Int
        if y < -150 {
            step = 1
        } else if y > 60, weeksBack > 0 {
            step = -1
        } else {
            return
        }
        steppingWeek = true
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86)) {
            weeksBack = max(0, weeksBack + step)
        }
        // One step per pull; the next needs a fresh gesture.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            steppingWeek = false
        }
    }

    // MARK: - Cluster

    private var cluster: some View {
        let bubbles = Self.bubbles

        return TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    bubbleView(bubble, index: index, time: time)
                }

                // A second pass so no face can cover a neighbour's count.
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    bubbleCount(bubble, index: index, time: time)
                }
            }
        }
        .frame(width: screenWidth, height: clusterHeight(period) * scale, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(true)
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
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
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

    /// The "N times" capsule, drawn above every face so it's never buried.
    @ViewBuilder
    private func bubbleCount(_ bubble: RecapBubble, index: Int, time: Double) -> some View {
        let spot = bubble.spots[period] ?? bubble.spots.values.first!
        let here = bubble.spots[period] != nil
        let diameter = spot.diameter * scale
        let center = CGPoint(x: spot.center.x * scale, y: (spot.center.y - Self.clusterTop) * scale)
        let float = CGSize(width: 1.6 * sin(time * 0.5 + Double(index)), height: 2 * cos(time * 0.42 + Double(index) * 1.3))

        if let times = countShown(bubble), labelFits(centerX: center.x) {
            Text(times == 1 ? "1 time" : "\(times) times")
                .font(.kithCaptionStrong)
                .contentTransition(.numericText(value: Double(times)))
                // Wider than a small bubble is fine; wrapping isn't.
                .fixedSize()
                .kithCapCentered(15, relativeTo: .footnote)
                .foregroundStyle(KithTheme.canvas(isDark))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(ink, in: Capsule())
                .rotationEffect(.degrees(bubble.tilt))
                // Sits on the bubble's lower edge, as it did as an overlay.
                .position(x: center.x, y: center.y + diameter / 2 + 8)
                .offset(float)
                .opacity(here && appeared ? 1 : 0)
                .scaleEffect(here && appeared ? 1 : 0.6)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.76).delay(appeared ? Double(index) * 0.028 : 0),
                    value: appeared
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
        guard let times = bubble.times[period] else { return nil }
        // Earlier weeks are quieter, so stepping back visibly changes the cluster.
        return period == .week ? max(1, times - weeksBack) : times
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
/// time together, everything else behind "See More", and the photos from all
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
    /// The photo open full size in the carousel, if any.
    @State private var viewingPhoto: Int?

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    var body: some View {
        let theirs = store.hangouts.filter { $0.contact.name == contact.name }
        let photos = galleryPhotos

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
            .progressiveTopBlur()

        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .fullScreenCover(isPresented: Binding(get: { viewingPhoto != nil }, set: { if !$0 { viewingPhoto = nil } })) {
            PhotoCarousel(
                photos: galleryPhotos,
                index: viewingPhoto ?? 0
            ) { viewingPhoto = nil }
        }
        .drawer(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
            if let index = store.hangouts.firstIndex(where: { $0.id == openHangout }) {
                MeetupDetailView(hangout: Bindable(store).hangouts[index]) { openHangout = nil }
            }
        }
        .drawer(isPresented: $showingHistory) {
            FriendHistoryView(contact: contact) { showingHistory = false }
        }
        .photosPicker(isPresented: $addingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
    }

    /// Every photo from your time together, one of each. The grid and the
    /// carousel must walk the same list or tapping a tile opens a different
    /// photo than the one you tapped.
    private var galleryPhotos: [MeetupPhoto] {
        var seen: Set<String> = []
        return store.hangouts
            .filter { $0.contact.name == contact.name }
            .flatMap(\.photos)
            .filter { seen.insert($0.id).inserted }
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
                // The 44pt target is kept for the finger; the space it adds
                // around the label is taken back so the gap reads as ~5pt.
                .padding(.vertical, -15)
                .accessibilityHint("Opens every time you’ve spent with \(contact.firstName)")
            }
        }
    }

    /// Your latest time together: a photo from it, what it was, and a way in.
    private func latestCard(_ hangout: RecentHangout) -> some View {
        HangoutRow(hangout: hangout, lead: .photo, title: Self.shortTitle(hangout)) {
            openHangout = hangout.id
        }
    }

    /// "Eleventh House with Manitej" reads "Eleventh House at 9 AM" on
    /// Manitej's own page.
    private static func shortTitle(_ hangout: RecentHangout) -> String {
        "\(hangout.spot) at \(hangout.startTime)"
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
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                    // Opens the whole set big, starting on this one.
                    Button { viewingPhoto = offset } label: {
                        photo.image
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Photo \(offset + 1) of \(photos.count)")
                    .accessibilityHint("Opens it full size")
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
                .fill(KithTheme.uiFill(isDark))
                .frame(width: side, height: side)
                .overlay {
                    Text("+")
                        .font(KithType.font(.w90, 33.376, .largeTitle))
                        .foregroundStyle(ink)
                }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Add a Photo")
    }
}

// MARK: - Shared pieces

/// A hangout at a glance (comp 407:1532): their face, how it felt, what it
/// was. One you haven't answered yet shows a "reflect" tag instead. Tapping
/// opens the entry.
struct HangoutRow: View {
    /// What sits at the leading edge. The row is otherwise identical wherever
    /// it appears, which is the point — Home, a friend's page and their
    /// history all draw the same component.
    enum Lead {
        /// Their face: for lists where the row names a person.
        case avatar
        /// A photo from the hangout: for a friend's own page, where the face
        /// is already at the top of the screen.
        case photo
        /// Nothing, for the history list.
        case none
    }

    @Environment(\.colorScheme) private var colorScheme

    let hangout: RecentHangout
    var lead: Lead = .avatar
    /// Overrides the title; a friend's page says "Studying at 9am" where a
    /// mixed list says "Studying with Manitej".
    var title: String?
    var open: () -> Void

    var body: some View {
        let isDark = colorScheme == .dark
        let feelings = Feeling.allCases.filter(hangout.feelings.contains)

        Button(action: open) {
            HStack(spacing: 12) {
                switch lead {
                case .avatar:
                    ContactAvatar(contact: hangout.contact, diameter: 75)
                case .photo:
                    Group {
                        if let photo = hangout.photos.first {
                            photo.image.resizable().scaledToFill()
                        } else {
                            ContactAvatar(contact: hangout.contact, diameter: 75)
                        }
                    }
                    .frame(width: 75, height: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                case .none:
                    EmptyView()
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        if feelings.isEmpty {
                            FeelingTag(
                                "Needs Reflection",
                                fill: KithTheme.canvas(isDark),
                                text: KithTheme.secondary(isDark)
                            )
                        } else {
                            ForEach(feelings) { feeling in
                                FeelingTag(feeling.rawValue, fill: feeling.pillFill)
                            }
                        }
                    }
                    .offset(x: -2)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(title ?? hangout.heading)
                            .font(.kithCaptionStrong)
                            .foregroundStyle(KithTheme.ink(isDark))
                        Text(hangout.subheading)
                            .font(.kithRowDetail)
                            .foregroundStyle(KithTheme.secondary(isDark))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KithTheme.secondary(isDark))
                    .padding(.trailing, 4)
            }
            .padding(16)
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
    /// Bigger, for tags you tap to change rather than just read.
    var large = false

    init(_ title: String, fill: Color, text: Color? = nil, large: Bool = false) {
        self.title = title
        self.fill = fill
        self.text = text
        self.large = large
    }

    var body: some View {
        Text(title)
            .font(large ? .kithCaptionStrong : .kithFineStrong)
            .kithCapCentered(15, relativeTo: large ? .footnote : .caption)
            .foregroundStyle(text ?? KithTheme.ink(false))
            .lineLimit(1)
            // Never squeezed into "Energiz…" by a tight row; the row wraps instead.
            .fixedSize()
            .padding(.horizontal, large ? 14 : 9.6)
            .frame(height: large ? 34 : 24)
            .background(fill, in: Capsule())
    }
}

/// Your own photo, as Profile shows it: the one you picked, or the empty
/// contact silhouette until you do.
struct YourAvatar: View {
    @AppStorage("profile.name") private var name = DemoCast.placeholderName
    var diameter: CGFloat

    var body: some View {
        if let custom = ProfilePhotoStore.load() {
            Image(uiImage: custom)
                .resizable()
                .scaledToFill()
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
        } else {
            ProfilePhotoStore.blank(diameter: diameter, dark: false)
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
        "Evan": KithContact(name: "Evan Raghunathan", face: .photo(Portrait(asset: "RecapPriya"))),
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
        // The month only shows people you saw three times or more, and only
        // people with a photo: no initials-only faces padding it out.
        let people = listed(friend).map { bubble in
            var bubble = bubble
            let hasPhoto: Bool
            switch bubble.contact.face {
            case .photo, .picture: hasPhoto = true
            case .initials: hasPhoto = DemoCast.isJudge
            }
            if (bubble.times[.month] ?? 0) < 3 || !hasPhoto {
                bubble.spots[.month] = nil
                bubble.times[.month] = nil
            }
            return bubble
        }
        .filter { !$0.spots.isEmpty }
        return fitted(radiating(people))
    }()

    /// Scales and centres the month so the whole circle sits on screen,
    /// edge to edge with a small margin, nobody cut off at the sides.
    private static func fitted(_ bubbles: [RecapBubble]) -> [RecapBubble] {
        let spots = bubbles.compactMap { $0.spots[.month] }
        guard !spots.isEmpty else { return bubbles }
        let margin: CGFloat = 14, labelRoom: CGFloat = 16
        let minX = spots.map { $0.center.x - $0.diameter / 2 }.min()!
        let maxX = spots.map { $0.center.x + $0.diameter / 2 }.max()!
        let minY = spots.map { $0.center.y - $0.diameter / 2 }.min()!
        let maxY = spots.map { $0.center.y + $0.diameter / 2 }.max()! + labelRoom
        let width: CGFloat = 393 - margin * 2, height: CGFloat = monthHeight - margin * 2
        let k = min(width / (maxX - minX), height / (maxY - minY), 1.25)
        let offsetX = margin + (width - (maxX - minX) * k) / 2
        let offsetY = clusterTop + margin + (height - (maxY - minY) * k) / 2
        return bubbles.map { bubble in
            guard let spot = bubble.spots[.month] else { return bubble }
            var bubble = bubble
            bubble.spots[.month] = (
                CGPoint(x: offsetX + (spot.center.x - minX) * k, y: offsetY + (spot.center.y - minY) * k),
                spot.diameter * k
            )
            return bubble
        }
    }

    /// The comp's people and counts. Week keeps the comp's own placement;
    /// Month is laid out by `radiating`.
    private static func listed(_ friend: (String) -> KithContact) -> [RecapBubble] {
        func spot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat) -> (center: CGPoint, diameter: CGFloat) {
            (CGPoint(x: x, y: y), d)
        }
        if DemoCast.isJudge { return judgeListed(spot) }
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
            RecapBubble(contact: friend("Evan"), spots: [.month: spot(-12, 242, 84)], times: [.month: 5], tilt: 2),
            RecapBubble(contact: friend("Sam"), spots: [.month: spot(399.5, 428.5, 79)], times: [.month: 4], tilt: -4)
        ] + ringBubbles(spot)
    }

    /// The outer ring: people you saw once or twice this month, on their own
    /// colour since they have no photo here.
    private static func ringBubbles(_ spot: (CGFloat, CGFloat, CGFloat) -> (center: CGPoint, diameter: CGFloat)) -> [RecapBubble] {
        outerRing.enumerated().map { index, person in
            RecapBubble(
                contact: KithContact(name: person.name, face: DemoCast.initials(person.name, FriendBlob.forName(person.name))),
                spots: [.month: spot(0, 0, 0)],
                times: [.month: person.times],
                tilt: index.isMultiple(of: 2) ? 3 : -3
            )
        }
    }

    /// The judge's build: Nora and Leo, and nobody else.
    private static func judgeListed(_ spot: (CGFloat, CGFloat, CGFloat) -> (center: CGPoint, diameter: CGFloat)) -> [RecapBubble] {
        return [
            RecapBubble(contact: DemoCast.nora, spots: [.week: spot(190, 285, 148), .month: spot(0, 0, 0)], times: [.week: 3, .month: 9], tilt: -2),
            RecapBubble(contact: DemoCast.leo, spots: [.week: spot(298, 214, 106), .month: spot(0, 0, 0)], times: [.week: 2, .month: 6], tilt: 3)
        ]
    }

    private static let outerRing: [(name: String, times: Int)] = [
        ("Aanya Iyer", 2), ("Ben Walsh", 1), ("Camila Diaz", 2), ("Felix Brooks", 1),
        ("Grace Kim", 2), ("Hiro Tanaka", 1), ("Isla Evans", 1), ("Jonah Park", 2),
        ("Maya Gupta", 1), ("Quinn Ferreira", 1), ("Rosa Mehta", 2), ("Wes Nguyen", 1)
    ]

    /// Month as one big circle radiating out from the middle: the friend you
    /// saw most at the centre, everyone else sized by how often and placed
    /// outward in that order, each in the first gap on a golden-angle spiral.
    /// It runs past the screen's edges; you pan around it.
    private static func radiating(_ bubbles: [RecapBubble]) -> [RecapBubble] {
        let center = CGPoint(x: 196.5, y: clusterTop + 223)
        let gap: CGFloat = 8
        var placed: [(center: CGPoint, diameter: CGFloat)] = []
        var result = bubbles
        let order = bubbles.indices.sorted { (bubbles[$0].times[.month] ?? 0) > (bubbles[$1].times[.month] ?? 0) }

        for (rank, index) in order.enumerated() {
            guard let count = bubbles[index].times[.month] else { continue }
            let diameter = min(152, max(54, 44 + 9 * CGFloat(count)))
            var spot = center
            if rank > 0 {
                var distance = (placed[0].diameter + diameter) / 2 + gap
                let start = CGFloat(rank) * 2.39996
                search: while true {
                    for step in 0..<36 {
                        let angle = start + CGFloat(step) * (.pi / 18)
                        let candidate = CGPoint(x: center.x + distance * cos(angle), y: center.y + distance * sin(angle) * 0.92)
                        let clear = placed.allSatisfy { other in
                            hypot(candidate.x - other.center.x, candidate.y - other.center.y) >= (other.diameter + diameter) / 2 + gap
                        }
                        if clear {
                            spot = candidate
                            break search
                        }
                    }
                    distance += 4
                }
            }
            placed.append((spot, diameter))
            result[index].spots[.month] = (spot, diameter)
        }
        return result
    }
}
