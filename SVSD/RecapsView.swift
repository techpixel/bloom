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
    @State private var screenWidth: CGFloat = 393
    @State private var appeared = RecapsView.hasAppeared
    @State private var openFriend: KithContact?
    @State private var openHangout: RecentHangout.ID?
    /// How far you've dragged the cluster to look around it.
    @State private var pan: CGSize = .zero
    @GestureState private var dragging: CGSize = .zero
    /// The float's own clock: frozen while you drag, shifted by however long
    /// that took, so letting go doesn't snap the bubbles forward.
    @State private var floatShift: Double = 0
    @State private var frozenAt: Double?
    private static var hasAppeared = false

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    /// Where the cluster starts in the comp, and how tall it is per period, so
    /// "Highlights" lands where each comp puts it.
    private static let clusterTop: CGFloat = 140
    private func clusterHeight(_ period: RecapPeriod) -> CGFloat {
        period == .week ? 322 : 470
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
            }
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

        return TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : (frozenAt ?? (timeline.date.timeIntervalSinceReferenceDate - floatShift))
            ZStack(alignment: .topLeading) {
                ForEach(Array(bubbles.enumerated()), id: \.element.id) { index, bubble in
                    bubbleView(bubble, index: index, time: time)
                }
            }
            .offset(currentPan)
        }
        .frame(width: screenWidth, height: clusterHeight(period) * scale, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(panGesture)
        .onChange(of: period) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.85)) { pan = .zero }
        }
    }

    private var currentPan: CGSize {
        let raw = CGSize(width: pan.width + dragging.width, height: pan.height + dragging.height)
        let range = panRange
        return CGSize(width: rubberBand(raw.width, range.x), height: rubberBand(raw.height, range.y))
    }

    /// Drag the cluster to look around it. It gives a little past the edges
    /// of what's there, and settles back inside when you let go.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragging) { value, state, _ in state = value.translation }
            .onChanged { _ in
                if frozenAt == nil {
                    frozenAt = Date().timeIntervalSinceReferenceDate - floatShift
                }
            }
            .onEnded { value in
                if let frozen = frozenAt {
                    floatShift = Date().timeIntervalSinceReferenceDate - frozen
                    frozenAt = nil
                }
                let range = panRange
                let thrown = CGSize(
                    width: pan.width + value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.35,
                    height: pan.height + value.translation.height + (value.predictedEndTranslation.height - value.translation.height) * 0.35
                )
                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.86)) {
                    pan = CGSize(
                        width: min(max(thrown.width, range.x.lowerBound), range.x.upperBound),
                        height: min(max(thrown.height, range.y.lowerBound), range.y.upperBound)
                    )
                }
            }
    }

    /// How far the cluster can travel each way: enough to bring the outermost
    /// friend fully on screen, and no further.
    private var panRange: (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let spots = Self.bubbles.compactMap { $0.spots[period] }
        guard !spots.isEmpty else { return (0...0, 0...0) }
        let margin: CGFloat = 16
        let left = spots.map { ($0.center.x - $0.diameter / 2) * scale }.min()!
        let right = spots.map { ($0.center.x + $0.diameter / 2) * scale }.max()!
        let top = spots.map { ($0.center.y - Self.clusterTop - $0.diameter / 2) * scale }.min()!
        let bottom = spots.map { ($0.center.y - Self.clusterTop + $0.diameter / 2 + 14) * scale }.max()!
        let width = screenWidth, height = clusterHeight(period) * scale
        let x = min(0, width - margin - right)...max(0, margin - left)
        let y = min(0, height - margin - bottom)...max(0, margin - top)
        return (x, y)
    }

    /// Past the range the drag moves a third as far, so the edge is felt.
    private func rubberBand(_ value: CGFloat, _ range: ClosedRange<CGFloat>) -> CGFloat {
        if value < range.lowerBound { return range.lowerBound + (value - range.lowerBound) / 3 }
        if value > range.upperBound { return range.upperBound + (value - range.upperBound) / 3 }
        return value
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
                    if let times = countShown(bubble), labelFits(centerX: center.x + currentPan.width) {
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
        // Every hangout draws from the same pool, so the friend's gallery would
        // otherwise show the same place three or four times over.
        var seenPhotos: Set<String> = []
        let photos = theirs.flatMap(\.photos).filter { seenPhotos.insert($0.id).inserted }

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
        .fullScreenCover(isPresented: Binding(get: { viewingPhoto != nil }, set: { if !$0 { viewingPhoto = nil } })) {
            PhotoCarousel(
                photos: store.hangouts.filter { $0.contact.name == contact.name }.flatMap(\.photos),
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
                .accessibilityHint("Opens every time you’ve spent with \(contact.firstName)")
            }
        }
    }

    /// Your latest time together: a photo from it, what it was, and a way in.
    private func latestCard(_ hangout: RecentHangout) -> some View {
        let feelings = Feeling.allCases.filter(hangout.feelings.contains)

        // The photo runs the card's full height, however much the text beside
        // it takes, so the two always line up.
        let thumbnail: CGFloat = 92

        return VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 3) {
                        if feelings.isEmpty {
                            FeelingTag(
                                "Needs Reflection",
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
                    Text("View Your Time Together")
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
            .padding(.leading, thumbnail + 12)
            .frame(minHeight: thumbnail)
            .overlay(alignment: .leading) {
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
                .frame(width: thumbnail)
                .frame(maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            }
        .padding(12)
        .background(KithTheme.uiFill(isDark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// "Studying with Manitej" reads "Studying at 9 AM" on Manitej's own page.
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
                .fill(KithTheme.suggestionCard(isDark))
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
                                "Needs Reflection",
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KithTheme.secondary(isDark))
                    .padding(.trailing, 4)
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
            .kithCapCentered(large ? 13 : 12, relativeTo: large ? .footnote : .caption)
            .foregroundStyle(text ?? KithTheme.ink(false))
            .lineLimit(1)
            // Never squeezed into "Energiz…" by a tight row; the row wraps instead.
            .fixedSize()
            .padding(.horizontal, large ? 14 : 9.6)
            .frame(height: large ? 34 : 24)
            .background(fill, in: Capsule())
    }
}

/// Your own photo, as Profile shows it: the one you picked, or the comp's.
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
        } else if ProfilePhotoStore.removed {
            ProfilePhotoStore.blank(diameter: diameter, dark: false)
        } else if DemoCast.isJudge {
            ContactAvatar(contact: KithContact(name: name, face: DemoCast.initials(name, .mint)), diameter: diameter)
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
        return radiating(listed(friend))
    }()

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
            RecapBubble(contact: friend("Priya"), spots: [.month: spot(-12, 242, 84)], times: [.month: 5], tilt: 2),
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

    /// The judge's build: Nora and Leo, with a few people you saw once this
    /// week, and the same outer ring for the month.
    private static func judgeListed(_ spot: (CGFloat, CGFloat, CGFloat) -> (center: CGPoint, diameter: CGFloat)) -> [RecapBubble] {
        let weekSpots = [spot(96, 214, 62), spot(86, 352, 58), spot(292, 380, 64)]
        let ring = ringBubbles(spot).enumerated().map { index, bubble in
            var bubble = bubble
            if index < weekSpots.count {
                bubble.spots[.week] = weekSpots[index]
                bubble.times[.week] = 1
            }
            return bubble
        }
        return [
            RecapBubble(contact: DemoCast.nora, spots: [.week: spot(190, 285, 148), .month: spot(0, 0, 0)], times: [.week: 3, .month: 9], tilt: -2),
            RecapBubble(contact: DemoCast.leo, spots: [.week: spot(298, 214, 106), .month: spot(0, 0, 0)], times: [.week: 2, .month: 6], tilt: 3)
        ] + ring
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
