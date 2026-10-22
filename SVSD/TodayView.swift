import SwiftUI

// MARK: - Models

/// A nudge on the Today carousel: someone you crossed paths with, when you are
/// both free, and one idea for what to do about it.
struct TodayNudge: Identifiable {
    let contact: KithContact
    /// When and where you last saw them, as one sentence.
    var seen: String
    /// When you're both free, for each range they're free in. The range tabs
    /// only show the friends who have an opening in that range.
    var free: [ScheduleRange: String]
    var idea: String

    var id: String { contact.id }
}

/// A hangout Bloom has already logged for you, and what you made of it. Home
/// asks how it felt; the detail page holds the photos and the place.
struct RecentHangout: Identifiable {
    let contact: KithContact
    var title: String
    var detail: String
    /// The detail page's title reads "9 AM with Manitej".
    var startTime: String
    var place: String
    /// Coming back often enough is what makes Bloom offer to name the place.
    var visitsThisMonth = 0
    var placeName: String?
    var placeTags: [String] = []
    var namingDismissed = false
    var photos: [MeetupPhoto] = []
    var feelings: Set<Feeling> = []
    var reflection = ""
    /// Which recap periods pick it out as a highlight.
    var highlightIn: Set<RecapPeriod> = []

    let id = UUID()
}

// MARK: - Screen

/// Home: the greeting, the day range, a carousel of nudges, and what you
/// have been up to lately.
struct TodayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var range = ScheduleRange.today
    /// The carousel slot in the middle. Slots repeat the nudges so the carousel
    /// loops; `slot % count` is the nudge.
    @State private var focusedSlot: Int?
    @State private var composing: MessageDraft?
    @State private var planning: KithContact?
    @Environment(HangoutStore.self) private var store
    /// The hangout open in detail.
    @State private var openHangout: RecentHangout.ID?
    /// What you've picked and written on the card, until you save it into the entry.
    @State private var draftFeelings: Set<Feeling> = []
    @State private var draftReflection = ""
    @State private var savedReflection = 0
    /// The wait between your last tap on a feeling and the card filing it.
    @State private var settling: Task<Void, Never>?
    @Namespace private var recentCards
    @AppStorage("profile.name") private var name = DemoCast.placeholderName
    /// Taking a break (Profile) pauses suggestions along with everything shared.
    @AppStorage("settings.onBreak") private var onBreak = false
    /// The entrance plays the first time Home opens each launch, not on every
    /// return to the tab.
    @State private var screenWidth: CGFloat = 393
    @State private var overviewFriend: KithContact?
    @State private var entered = TodayView.hasEntered
    @State private var friendSectionShown = TodayView.hasEntered
    private static var hasEntered = false

    /// Newest first; the first is the one Home asks you to reflect on.
    private var recents: [RecentHangout] { store.hangouts }

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var card: Color { KithTheme.uiFill(isDark) }

    // The comp is an iPhone 16 frame: 393 x 852.
    private let designWidth: CGFloat = 393
    /// The comp's card is 291 of a 393 frame, with 51 either side. Kept as a
    /// ratio so a narrower phone scales it down rather than running off the edge.
    private func cardWidth(in width: CGFloat) -> CGFloat { width * 291 / 393 }
    private func carouselMargin(in width: CGFloat) -> CGFloat {
        max(0, (width - cardWidth(in: width)) / 2)
    }
    /// A recent card, plus a sliver of the next one so the strip reads as scrollable.
    /// One row fills the gutter-to-gutter width less a 28pt peek of the next.
    private func recentCardWidth(in width: CGFloat) -> CGFloat {
        max(280, width - 40 - 28)
    }
    /// Copies of the nudges laid end to end. Odd, so the first nudge can start
    /// in the true middle with as many laps available either way.
    private static let laps = 101

    private var nudges: [TodayNudge] { TodayNudge.sample.filter { $0.free[range] != nil } }

    /// How many friends are free in each range, for the tabs' badges.
    private var nudgeCounts: [ScheduleRange: Int] {
        Dictionary(uniqueKeysWithValues: ScheduleRange.allCases.map { option in
            (option, TodayNudge.sample.filter { $0.free[option] != nil }.count)
        })
    }

    private var slots: [Int] {
        nudges.count > 1 ? Array(0..<(nudges.count * Self.laps)) : Array(nudges.indices)
    }

    private var middleSlot: Int {
        nudges.count > 1 ? nudges.count * (Self.laps / 2) : 0
    }

    private var focusedNudge: TodayNudge? {
        guard !nudges.isEmpty else { return nil }
        return nudges[(focusedSlot ?? middleSlot) % nudges.count]
    }

    var body: some View {
        ZStack(alignment: .top) {
            KithTheme.canvas(isDark)

            backdrop
                .opacity(entered ? 1 : 0)
                .animation(.easeOut(duration: 1), value: entered)

            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Scrolls away with everything else rather than sitting
                        // over it.
                        greeting

                        recentSection
                            .padding(.top, 24)

                        // The whole section enters as one, after Recent, on its own
                        // flag: the carousel inside kept a view-scoped entrance from
                        // animating, so this one is flipped with an explicit animation.
                        VStack(alignment: .leading, spacing: 0) {
                            Text("See a Friend")
                                .font(.kithBodyStrong)
                                .foregroundStyle(ink)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.top, 26)
                                .padding(.horizontal, 20)

                            if onBreak {
                                breakNote
                                    .padding(.top, 12)
                                    .padding(.horizontal, 20)
                            } else {
                                RangeTabs(selection: $range, counts: nudgeCounts)
                                    .padding(.top, 12)
                                    .padding(.horizontal, 16)

                                // A new range is a new set of friends: the old cards blur
                                // out as the new ones blur in, in the same place.
                                VStack(spacing: 12) {
                                    ZStack {
                                        carousel
                                            .id(range)
                                            .transition(.blurReplace)
                                    }

                                    // The card's own width, so the two share edges.
                                    if !nudges.isEmpty {
                                        sendButton
                                            .frame(width: cardWidth(in: screenWidth))
                                    }
                                }
                                .padding(.top, 12)
                            }
                        }
                        .opacity(friendSectionShown ? 1 : 0)
                        .offset(y: friendSectionShown || reduceMotion ? 0 : 12)
                        .blur(radius: friendSectionShown || reduceMotion ? 0 : 4)
                    }
                    // Room to scroll the last card and its button clear of the
                    // floating tab bar.
                    .padding(.bottom, 110)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)

            }
        }
        .background(KithTheme.canvas(isDark))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .drawer(item: $overviewFriend) { friend in
            FriendRecapView(contact: friend, onBack: { overviewFriend = nil })
                .environment(store)
        }
        .task { await playEntrance() }
        .messageSheet($composing)
        .fullScreenCover(item: $planning) { _ in
            PlanFlowView(onBack: { planning = nil })
        }
        .sensoryFeedback(.success, trigger: savedReflection)
        // Back from the entry: the card picks up whatever was changed there.
        .onChange(of: openHangout) { _, open in
            if open == nil { loadDraft() }
        }
        .onAppear(perform: loadDraft)
        .drawer(isPresented: Binding(get: { openHangout != nil }, set: { if !$0 { openHangout = nil } })) {
            if let index = recents.firstIndex(where: { $0.id == openHangout }) {
                MeetupDetailView(hangout: Bindable(store).hangouts[index]) { openHangout = nil }
            }
        }
    }

    /// The pastel blooms, made of the blobs of the friends you're looking at:
    /// two overlap top right and two bottom left, the way the comp's backdrop
    /// placed its blooms, each drifting on its own so the colours mix and shift.
    private var backdrop: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let anchors = [
                CGPoint(x: size.width * 0.98, y: size.height * 0.05),
                CGPoint(x: size.width * 0.80, y: size.height * 0.13),
                CGPoint(x: size.width * 0.34, y: size.height * 0.80),
                CGPoint(x: size.width * 0.66, y: size.height * 0.88)
            ]
            let friends = Array(nudges.map(\.contact).prefix(anchors.count))

            ZStack {
                ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                    DriftingBlob(blob: friend.blob, length: size.width * 0.66, seed: Double(index) * 1.9, wander: 0.08)
                        .position(anchors[index])
                        .transition(.opacity)
                }
            }
            .blur(radius: 26)
            .opacity(isDark ? 0.4 : 0.5)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: friends.map(\.id))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(partOfDay), \(name)")
                .font(.kithTitle)
                .foregroundStyle(ink)
                .entrance(0, visible: entered)

            Text("Take a little time to tend to your relationships.")
                .font(.kithCaption)
                .foregroundStyle(secondary)
                .entrance(1, visible: entered)
        }
        .padding(.top, 30)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .combine)
    }

    /// A beat after the screen first draws, so there's something to animate from.
    private func playEntrance() async {
        guard !entered else { return }
        try? await Task.sleep(for: .milliseconds(60))
        entered = true
        Self.hasEntered = true
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .easeOut(duration: 0.6).delay(0.8)) {
            friendSectionShown = true
        }
    }

    private var partOfDay: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 0..<12: return "Morning"
        case 12..<17: return "Afternoon"
        default: return "Evening"
        }
    }

    /// While you're on a break there's no one to suggest: friends can't see
    /// you, and Bloom isn't looking.
    private var breakNote: some View {
        VStack(spacing: 8) {
            Text("You’re taking a break")
                .font(.kithCardTitle)
                .foregroundStyle(ink)
            Text("Friends can’t see you or when you’re free, so Bloom won’t suggest anyone. Turn it off in Profile whenever you’re ready.")
                .font(.kithCaption)
                .foregroundStyle(secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity)
        .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Carousel

    /// Cards sit in a paging scroller so the neighbours peek in at the edges,
    /// the way the comp draws them. The nudges repeat end to end, so swiping
    /// past the last one comes back round to the first.
    @ViewBuilder
    private var carousel: some View {
        if nudges.isEmpty {
            Text("No one’s free \(range == .thisWeek ? "this week" : range.title.lowercased()) yet.")
                .font(.kithSecondary)
                .foregroundStyle(secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
        } else {
            // The send button's 44pt target already pads 4pt above the pill, so
            // the visible gap under the cards is 4 + 4.
            ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(slots, id: \.self) { slot in
                            nudgeCard(nudges[slot % nudges.count])
                                .frame(width: cardWidth(in: screenWidth))
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $focusedSlot, anchor: .center)
                .contentMargins(.horizontal, carouselMargin(in: screenWidth), for: .scrollContent)
                // A tick as each card settles, not when the carousel first parks.
                .sensoryFeedback(.selection, trigger: focusedSlot) { old, new in old != nil && new != nil }
            .onAppear {
                // A beat later, once the strip has laid out, or the jump is lost.
                let start = middleSlot
                DispatchQueue.main.async { focusedSlot = start }
            }
        }
    }

    /// One friend to see (comp 406:1695): the idea up top, their face in a
    /// glow of their colour, when you last saw them and when you're both free.
    private func nudgeCard(_ nudge: TodayNudge) -> some View {
        VStack(spacing: 12) {
            // Bloom offers the idea; it never picks for you.
            Text(nudge.idea.prefix(1).uppercased() + nudge.idea.dropFirst())
                .font(.kithCardTitle)
                .foregroundStyle(ink)
                .multilineTextAlignment(.center)

            haloAvatar(nudge.contact)

            VStack(spacing: 8) {
                Text(nudge.contact.name)
                    .font(.kithCardTitle)
                    .foregroundStyle(ink)
                // Two lines kept for each, filled or not, so every card in the
                // carousel is the same height.
                Text(nudge.seen)
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity)

            Text(nudge.free[range] ?? "")
                .font(.kithCaptionStrong)
                .foregroundStyle(KithTheme.suggestionAccent)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        // Contain, not combine: the face inside is its own button.
        .accessibilityElement(children: .contain)
    }

    /// The friend's colour as a soft, blurred glow behind their face, the
    /// comp's halo, reaching past the photo mostly down and to the left.
    /// Tapping their face opens their overview.
    private func haloAvatar(_ contact: KithContact) -> some View {
        Button { overviewFriend = contact } label: {
            ContactAvatar(contact: contact, diameter: 96.664, badgeRing: card)
                .background {
                    DriftingBlob(blob: contact.blob, length: 150, seed: Double(contact.name.count), wander: 0.025)
                        .blur(radius: 5)
                        .offset(x: -3, y: 4)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(contact.name)
        .accessibilityHint("Opens your time with \(contact.firstName)")
    }

    private var sendButton: some View {
        Button {
            if let nudge = focusedNudge {
                composing = MessageDraft(contact: nudge.contact)
            }
        } label: {
            Text("Send a Text")
                .font(.kithSecondary)
                .kithCapCentered(15, relativeTo: .subheadline)
                .foregroundStyle(KithTheme.canvas(isDark))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(focusedNudge.map { "Send \($0.contact.firstName) a text" } ?? "Send a Text")
    }

    // MARK: - Recent

    /// The latest hangout asks how it went (comp 345:1849). Pick a feeling or
    /// two and, after a beat, the card shrinks into a row like the ones under
    /// it (comp 407:1532); "Something Else" asks for a few words first. Under
    /// it, the last few friends you've already answered for.
    @ViewBuilder
    private var recentSection: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.kithBodyStrong)
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .entrance(2, visible: entered)

                VStack(spacing: 10) {
                    if let asking = awaitingReflection {
                        reflectionCard(asking)
                            .matchedGeometryEffect(id: asking.id, in: recentCards)
                            .transition(.opacity)
                            .padding(.horizontal, 20)
                    } else if !answeredRecents.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 10) {
                                ForEach(answeredRecents) { hangout in
                                    HangoutRow(hangout: hangout) { openHangout = hangout.id }
                                        .frame(width: recentCardWidth(in: screenWidth))
                                        .matchedGeometryEffect(id: hangout.id, in: recentCards)
                                        .transition(.opacity)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .contentMargins(.horizontal, 20, for: .scrollContent)
                    }
                }
                .entrance(3, visible: entered)
            }
        }
    }

    /// Recent's one action item: the newest hangout, while it still wants a
    /// reflection. Deliberately not "any unanswered hangout" — older ones are
    /// reflected on from their own page, and treating them as action items here
    /// would mean the queue never empties, so the card could never settle into
    /// its row. It also keeps this in step with `answer()`, which writes to the
    /// newest entry.
    private var awaitingReflection: RecentHangout? {
        recents.first.flatMap { $0.feelings.isEmpty ? $0 : nil }
    }

    /// The newest hangout with each friend, the ones still wanting a reflection
    /// first so they're what you land on.
    private var answeredRecents: [RecentHangout] {
        var seen: Set<String> = []
        let newestPerFriend = recents.filter { hangout in
            guard !seen.contains(hangout.contact.name) else { return false }
            seen.insert(hangout.contact.name)
            return true
        }
        // The one the card above is already asking about isn't repeated here.
        let asking = recents.first.flatMap { $0.feelings.isEmpty ? $0.id : nil }
        // Newest first, deliberately unsorted beyond that: the card settles into
        // the row at the head of the strip, so the one you just answered has to
        // be the one sitting there. Sorting unanswered entries to the front sent
        // it to the far end, where the shrink played off-screen.
        return newestPerFriend.filter { $0.id != asking }
    }

    private func reflectionCard(_ hangout: RecentHangout) -> some View {
        let friend = hangout.contact
        let wantsWords = draftFeelings.contains(.somethingElse)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ContactAvatar(contact: friend, diameter: 60, badgeRing: card)

                VStack(alignment: .leading, spacing: 5) {
                    Text(hangout.title)
                        .font(.kithCardTitle)
                        .foregroundStyle(ink)
                    Text(hangout.detail)
                        .font(.kithCaption)
                        .foregroundStyle(KithTheme.recentMeta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .contextMenu {
                Button("Text \(friend.firstName)", systemImage: "message") {
                    composing = MessageDraft(contact: friend)
                }
                if !DemoCast.isJudge {
                    Button("Plan Another", systemImage: "calendar") {
                        planning = friend
                    }
                }
            }

            VStack(alignment: .leading, spacing: 15) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How did your time with \(friend.firstName) feel?")
                        .font(.kithCardTitle)
                        .foregroundStyle(ink)
                    FeelingChips(selected: $draftFeelings)
                }

                if wantsWords {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What was it like?")
                            .font(.kithCardTitle)
                            .foregroundStyle(ink)
                        ReflectionField(text: $draftReflection, minHeight: 72, fill: KithTheme.canvas(isDark))
                    }
                    .transition(reveal(order: 1))

                    saveButton
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(reveal(order: 2))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.9), value: wantsWords)
        .onChange(of: draftFeelings) { _, picked in settle(after: picked) }
    }

    /// Fades and rises in a beat after the one before; leaves with a plain fade.
    private func reveal(order: Int) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 10))
                .animation(.easeOut(duration: 0.45).delay(0.12 + Double(order) * 0.08)),
            removal: .opacity.animation(.easeOut(duration: 0.15))
        )
    }

    /// Two feelings is an answer; one waits a little longer in case a second
    /// is coming. "Something Else" waits for words and the Save button.
    private func settle(after picked: Set<Feeling>) {
        settling?.cancel()
        guard !picked.isEmpty, !picked.contains(.somethingElse) else { return }
        let wait: Duration = picked.count >= 2 ? .milliseconds(700) : .milliseconds(1600)
        settling = Task { @MainActor in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            answer()
        }
    }

    private var saveButton: some View {
        let hasWords = !draftReflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return Button(action: answer) {
            Text("Save")
                .font(.kithCaption)
                .kithCapCentered(13, relativeTo: .footnote)
                .foregroundStyle(hasWords ? KithTheme.canvas(isDark) : KithTheme.secondaryOnFill(isDark))
                .padding(.horizontal, 22)
                .frame(height: 36)
                .background(hasWords ? ink : KithTheme.canvas(isDark), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!hasWords)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: hasWords)
        .accessibilityHint(hasWords ? "Saves it into the entry" : "Write a few words first")
    }

    /// Files the answer into the entry; the card shrinks into its row.
    private func answer() {
        guard !store.hangouts.isEmpty, !draftFeelings.isEmpty else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let words = draftReflection.trimmingCharacters(in: .whitespacesAndNewlines)
        savedReflection += 1
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86)) {
            store.hangouts[0].feelings = draftFeelings
            store.hangouts[0].reflection = words
        }
        draftFeelings = []
        draftReflection = ""
    }

    private func loadDraft() {
        guard let hangout = recents.first else { return }
        draftFeelings = hangout.feelings
        draftReflection = hangout.reflection
    }
}

// MARK: - Sample data

extension TodayNudge {
    static let sample: [TodayNudge] = DemoCast.isJudge ? DemoCast.nudges : comps

    private static let comps: [TodayNudge] = [
        TodayNudge(
            contact: KithContact(
                name: "Jadden Picardal",
                face: .photo(Portrait(asset: "AvatarJadden", width: 1.54, height: 1.54))
            ),
            seen: "You saw them at Vienna Cafe yesterday.",
            free: [
                .today: "You’re both free at 4:00 PM.",
                .thisWeek: "You’re both free Wednesday at 4:00 PM."
            ],
            idea: "grab a coffee?"
        ),
        TodayNudge(
            contact: KithContact(
                name: "Manitej Boorgu",
                face: .photo(Portrait(asset: "FriendAvatar", width: 2.5919, height: 1.7318, x: 0.1038, y: -0.0007))
            ),
            seen: "You saw them at Eleventh House on Monday.",
            free: [
                .today: "You’re both free at 7:30 PM.",
                .tomorrow: "You’re both free at 6:00 PM.",
                .thisWeek: "You’re both free Friday evening."
            ],
            idea: "split a plate of fries?"
        ),
        TodayNudge(
            contact: KithContact(
                name: "Ishan Goyal",
                face: .photo(Portrait(asset: "AvatarIshan", width: 1.0751, height: 1.2933, x: -0.0173, y: -0.09))
            ),
            seen: "You haven’t seen them in three weeks.",
            free: [
                .tomorrow: "You’re both free at noon.",
                .thisWeek: "You’re both free Thursday afternoon."
            ],
            idea: "go for a walk?"
        ),
        TodayNudge(
            contact: KithContact(
                name: "Ray Arayilikath",
                face: .photo(Portrait(asset: "AvatarRay", width: 1.2465, height: 1.5581, y: 0.164))
            ),
            seen: "You saw them Sunday. They’re around campus today.",
            free: [
                .today: "You’re both free at 6:00 PM.",
                .thisWeek: "You’re both free Saturday morning."
            ],
            idea: "cook something?"
        ),
        TodayNudge(
            contact: KithContact(
                name: "Michelle Xuan",
                face: .photo(Portrait(asset: "AvatarMichelle", height: 2))
            ),
            seen: "You saw them at Vienna Cafe two weeks ago.",
            free: [
                .tomorrow: "You’re both free at 3:00 PM.",
                .thisWeek: "You’re both free Sunday at 2:00 PM."
            ],
            idea: "study together?"
        )
    ]
}

extension RecentHangout {
    /// The comps' hangouts first — the newest is Home's — then enough more that
    /// each friend's recap count adds up to real entries.
    static let sample: [RecentHangout] = {
        if DemoCast.isJudge { return DemoCast.hangouts }
        let manitej = KithContact(
            name: "Manitej Boorgu",
            face: .photo(Portrait(asset: "FriendAvatar", width: 2.4184, height: 1.6158, x: 0.0634, y: -0.0342))
        )
        let ray = KithContact(
            name: "Ray Arayilikath",
            face: .photo(Portrait(asset: "AvatarRay", width: 1.2465, height: 1.5581, y: 0.164))
        )
        let ishan = KithContact(
            name: "Ishan Goyal",
            face: .photo(Portrait(asset: "AvatarIshan", width: 1.0751, height: 1.2933, x: -0.0173, y: -0.09))
        )
        let jadden = KithContact(name: "Jadden Picardal", face: .photo(Portrait(asset: "AvatarJadden", width: 1.54, height: 1.54)))
        let michelle = KithContact(name: "Michelle Xuan", face: .photo(Portrait(asset: "RecapMichelle")))
        let friend = { (key: String) in recapFriends[key]! }

        // The comp's photos (69:869). A demo, so every hangout borrows from the
        // same roll rather than opening on an empty grid.
        var hangouts = [
            RecentHangout(
                contact: manitej,
                title: "Coffee with Manitej",
                detail: "Monday · 2 hours · Eleventh House",
                startTime: "9 AM",
                place: "Eleventh House, Lafayette",
                visitsThisMonth: 3,
                photos: Self.compPhotos,
                highlightIn: [.month]
            ),
            RecentHangout(
                contact: manitej,
                title: "Studying with Manitej",
                detail: "Monday · 2 hours · Eleventh House",
                startTime: "1 PM",
                place: "Eleventh House, Lafayette",
                photos: Self.compPhotos,
                feelings: [.connected, .energized],
                reflection: "we joked around a lot at the beginning and hes always a fun guy to hang out with!\n\ngot coffee and studied pretty hard, glad that i decided to meet up with him even thought i really didn’t want to go outside today",
                highlightIn: [.week]
            ),
            RecentHangout(
                contact: ray,
                title: "Dinner with Ray",
                detail: "Sunday · 1 hr 20 min · Home",
                startTime: "7 PM",
                place: "Home",
                photos: Self.photos(at: "Home", seed: 3),
                feelings: [.atEase],
                highlightIn: [.week, .month]
            )
        ]

        // Enough more that each bubble's week count is real entries: Manitej 5,
        // Ishan 4, Michelle 4, Ray 3, Dev 3, Theo 2, Amara 1, Jadden 1.
        let more: [(KithContact, Int)] = [
            (manitej, 3), (ishan, 4), (michelle, 4), (ray, 2),
            (friend("Dev"), 3), (friend("Theo"), 2), (friend("Amara"), 1), (jadden, 1)
        ]
        let plans = [
            ("Lunch", "12 PM", "1 hour", "Purdue Memorial Union"),
            ("Walk", "5 PM", "45 min", "Celery Bog"),
            ("Study session", "3 PM", "2 hours", "Hicks Library"),
            ("Coffee", "10 AM", "1 hr 10 min", "Vienna Cafe"),
            ("Dinner", "7 PM", "1 hr 30 min", "Lafayette Brewing"),
            ("Bouldering", "6 PM", "1 hr 30 min", "Climbing gym"),
            ("Farmers market", "9 AM", "1 hour", "Lafayette Farmers Market"),
            ("Walk", "4 PM", "1 hour", "Wabash Riverfront"),
            ("Hang", "2 PM", "45 min", "Purdue Mall")
        ]
        let days = ["Saturday", "Friday", "Thursday", "Wednesday", "Tuesday"]
        var step = 0
        // A few of them already answered, so Home has more than one friend to show.
        let answered: [String: Set<Feeling>] = ["Ishan": [.energized], "Michelle": [.connected, .atEase]]
        for (contact, count) in more {
            for round in 0..<count {
                let plan = plans[step % plans.count]
                hangouts.append(RecentHangout(
                    contact: contact,
                    title: "\(plan.0) with \(contact.firstName)",
                    detail: "\(days[step % days.count]) · \(plan.2) · \(plan.3)",
                    startTime: plan.1,
                    place: "\(plan.3), Lafayette",
                    photos: Self.photos(at: plan.3, seed: step),
                    feelings: round == 0 ? answered[contact.firstName] ?? [] : []
                ))
                step += 1
            }
        }
        return hangouts
    }()

    /// The comp's own four (69:869), kept for the entry it draws in full.
    static let compPhotos: [MeetupPhoto] = [
        .asset("MeetupPhotoPlant"),
        .asset("MeetupPhotoDrink"),
        .asset("MeetupPhotoCafe"),
        .asset("MeetupPhotoLatte")
    ]

    /// Real photos of each place (Wikimedia Commons, see PHOTO-CREDITS.md), so
    /// a walk at Celery Bog shows the bog and lunch at the Union shows the Union.
    private static let spotPhotos: [(match: [String], assets: [String])] = [
        (["Memorial Union"], ["SpotMemorialUnion1", "SpotMemorialUnion2", "SpotMemorialUnion3"]),
        (["Celery Bog"], ["SpotCeleryBog1", "SpotCeleryBog2", "SpotCeleryBog3"]),
        (["Library"], ["SpotLibrary1", "SpotLibrary2", "SpotLibrary3"]),
        (["Lafayette Brewing", "Main Street"], ["SpotDowntownLafayette1", "SpotDowntownLafayette2", "SpotDowntownLafayette3"]),
        (["Climbing"], ["SpotClimbingGym1", "SpotClimbingGym2", "SpotClimbingGym3"]),
        (["Farmers Market"], ["SpotFarmersMarket1", "SpotFarmersMarket2", "SpotFarmersMarket3"]),
        (["Wabash", "Riverfront"], ["SpotWabashRiver1", "SpotWabashRiver2", "SpotWabashRiver3"]),
        (["Purdue Mall", "Bell Tower"], ["SpotPurdueCampus1", "SpotPurdueCampus2", "SpotPurdueCampus3", "SpotPurdueCampus4"]),
        (["Home"], ["SpotCafe3", "SpotCafe1"])
    ]
    /// Cafés and anywhere unlisted.
    private static let cafePhotos = ["SpotCafe1", "SpotCafe2", "SpotCafe3"]

    /// Two to four photos of the place, starting at a different one per
    /// entry so two visits to the same spot don't look identical.
    static func photos(at place: String, seed: Int) -> [MeetupPhoto] {
        let pool = spotPhotos.first { spot in spot.match.contains { place.localizedCaseInsensitiveContains($0) } }?.assets ?? cafePhotos
        let count = min(pool.count, 2 + abs(seed) % 3)
        return (0..<count).map { .asset(pool[(abs(seed) + $0) % pool.count]) }
    }
}

#Preview {
    TodayView()
        .environment(HangoutStore())
}
