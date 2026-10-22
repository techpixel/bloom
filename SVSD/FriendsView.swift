import SwiftUI

// MARK: - Models

/// A photo cropped into a circle the way the comp frames it. Size and offset
/// are fractions of the circle's diameter, so one framing holds at any size.
struct Portrait {
    let asset: String
    var width: CGFloat = 1
    var height: CGFloat = 1
    var x: CGFloat = 0
    var y: CGFloat = 0
}

/// Someone on the Friends screen: in your circle, asking to join it, or suggested.
struct KithContact: Identifiable {
    enum Face {
        case photo(Portrait)
        /// Initials on a colour plate, for people without a photo.
        case initials(String, background: Color, ink: Color)
    }

    let name: String
    var face: Face
    /// People who aren't on Kith yet get the iMessage badge — adding them sends an invite.
    var isOnKith = true
    /// The line you've written about them, under their name on their own page.
    var note: String?

    var id: String { name }

    var firstName: String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

/// How you know someone you haven't added yet.
enum Connection {
    /// "Friends with **Ishan**", optionally followed by "and others".
    case friendsWith(String, andOthers: Bool = false)
    case note(String)
}

struct FriendRequest: Identifiable {
    let contact: KithContact
    var connection: Connection?
    var received: Date

    var id: String { contact.id }
}

struct FriendSuggestion: Identifiable {
    let contact: KithContact
    var connection: Connection?

    var id: String { contact.id }
}

// MARK: - Screen

/// "Your Friends": the people in your circle up top, then requests and suggestions.
/// Your circle sits on a dial: the friend at the top is the one you're looking
/// at — tap them again to find a time together.
struct FriendsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var search = ""
    @State private var circle = KithContact.circleSample
    @State private var requests = FriendRequest.sample
    @State private var suggestions = FriendSuggestion.sample
    /// People you've sent a friend request to, or invited over Messages.
    @State private var requested: Set<String> = []
    @State private var inviting: MessageDraft?
    /// Counts accepted requests, to fire the success haptic.
    @State private var accepted = 0
    /// The dial slot at the top. Slots repeat your circle so the dial turns
    /// forever; `slot % count` is the friend.
    @State private var centeredSlot: Int?
    /// Who the dial is on, kept apart from the slot because a re-centre clears
    /// the slot for a beat. Starts on Ishan, as in the comp.
    @State private var dialFriendID: String? = KithContact.circleSample[1].id
    @State private var screenWidth = Self.designWidth
    #if DEBUG
    @State private var planning: KithContact? =
        ProcessInfo.processInfo.arguments.contains("-ShowSchedule") ? KithContact.circleSample[1] : nil
    #else
    @State private var planning: KithContact?
    #endif
    @State private var requestArrived = false
    @State private var requestPing = 0

    /// The friend whose overview is open, from tapping them on the dial.
    @State private var overview: KithContact?
    @Environment(HangoutStore.self) private var store

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var card: Color { KithTheme.suggestionCard(isDark) }

    // Measured off the comp, an iPhone 16 frame (393 × 852), then scaled by the
    // screen's width so the proportions hold on every phone. Type is left to
    // Dynamic Type; only the geometry scales.
    private static let designWidth: CGFloat = 393
    private var scale: CGFloat { screenWidth / Self.designWidth }
    private var gutter: CGFloat { 20 * scale }
    private var portraitSize: CGFloat { 100 * scale }
    private var nameGap: CGFloat { 12 * scale }

    // The dial. In the comp the middle friend's circle is centred at (195, 256)
    // and the next ones out at (±118, +14.8) from it — three points that sit on a
    // circle of radius 478. Every friend sits on that circle at the same angle
    // apart; angles don't change with screen size, so only the radius scales.
    private var dialRadius: CGFloat { 478 * scale }
    private static let dialStep = asin(118.0 / 478.0)
    /// Distance between neighbours measured around the rim, which is how far
    /// the strip scrolls to bring the next friend to the top.
    private var dialArc: CGFloat { dialRadius * Self.dialStep }
    /// How far the first friend out drops below the top of the dial.
    private var dialDrop: CGFloat { dialRadius * (1 - cos(Self.dialStep)) }

    private var visibleCircle: [KithContact] { circle.filter(matchesSearch) }

    /// Copies of your circle laid end to end. Odd, so the dial can start in the
    /// true middle with as many turns available either way.
    private static let dialLaps = 101

    /// The dial loops only with enough friends to fill it; two or three would
    /// show the same face twice at once.
    private var loops: Bool { visibleCircle.count > 3 }

    private var dialSlots: [Int] {
        loops ? Array(0..<(visibleCircle.count * Self.dialLaps)) : Array(visibleCircle.indices)
    }

    /// The slot holding `index` in the middle lap.
    private func middleSlot(for index: Int) -> Int {
        loops ? visibleCircle.count * (Self.dialLaps / 2) + index : index
    }

    private var centeredFriend: KithContact? {
        guard let slot = centeredSlot, !visibleCircle.isEmpty else { return nil }
        return visibleCircle[slot % visibleCircle.count]
    }
    /// Requests arrive a second after you land here, as if one just came in,
    /// so a demo on someone else's phone gets to see it happen.
    private var visibleRequests: [FriendRequest] {
        requestArrived ? requests.filter { matchesSearch($0.contact) } : []
    }
    private var visibleSuggestions: [FriendSuggestion] { suggestions.filter { matchesSearch($0.contact) } }

    var body: some View {
        // The title, search and your circle stay put; only the lists under
        // them scroll.
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, gutter)
                .padding(.top, 24 * scale)

            if !visibleCircle.isEmpty {
                dial
                    .padding(.top, 27 * scale)
            }

            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !visibleRequests.isEmpty {
                    section("Friend Requests") {
                        VStack(spacing: 16) {
                            ForEach(visibleRequests) { requestRow($0) }
                        }
                        .padding(12)
                        .background(card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.top, 40 * scale)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92, anchor: .top).combined(with: .opacity),
                        removal: .opacity
                    ))
                }

                if !visibleSuggestions.isEmpty {
                    section("People You Might Know") {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleSuggestions) { suggestion in
                                suggestionRow(suggestion)
                                    .onAppear { loadMoreIfLast(suggestion) }
                            }
                        }
                        .padding(12)
                        .background(card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        // Rows stop at the box edge instead of painting past it.
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .padding(.top, (visibleRequests.isEmpty ? 40 : 18) * scale)
                }

                if visibleCircle.isEmpty && visibleRequests.isEmpty && visibleSuggestions.isEmpty {
                    Text("No one by that name yet.")
                        .font(.kithSecondary)
                        .foregroundStyle(secondary)
                        .padding(.horizontal, gutter)
                        .padding(.top, 24)
                }
            }
            // Clear the floating tab bar, so the last row isn't under its glass.
            .padding(.bottom, 96)
            }
            // A soft edge where the lists slide under your circle.
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 14)
                    Rectangle()
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .scrollDismissesKeyboard(.immediately)
        .sensoryFeedback(.success, trigger: accepted)
        .messageSheet($inviting)
        .background(KithTheme.canvas(isDark))
        .statusBarHidden(true)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: centeredSlot)
        .fullScreenCover(item: $planning) { _ in
            PlanFlowView(onBack: { planning = nil })
        }
        .task {
            guard !requestArrived else { return }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.72)) {
                requestArrived = true
            }
            requestPing += 1
        }
        .sensoryFeedback(.impact(weight: .light), trigger: requestPing)
        .drawer(item: $overview) { friend in
            FriendRecapView(contact: friend, onBack: { overview = nil })
                .environment(store)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("Your Friends")
                    .font(.kithTitle)
                    .tracking(-1.28)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                HStack(spacing: 9.5) {
                    // The real iOS share sheet, with an invite to add you.
                    ShareLink(
                        item: URL(string: "https://bloom.app/add/\(Self.inviteHandle)")!,
                        subject: Text("Add me on Bloom"),
                        message: Text("I’m on Bloom, an app for spending more real time with friends. Add me:")
                    ) {
                        roundIcon("ShareIcon")
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Share your profile")
                    roundIconButton("QRCodeIcon", label: "Show your QR code") { /* TODO: QR code */ }
                }
            }

            HStack(spacing: 10) {
                Image("SearchIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(secondary)
                    .accessibilityHidden(true)

                TextField("Search", text: $search, prompt: Text("Search").foregroundStyle(secondary))
                    .font(.kithBody)
                    .foregroundStyle(ink)
                    .tint(ink)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search friends")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func roundIconButton(_ asset: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            roundIcon(asset)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    private func roundIcon(_ asset: String) -> some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .frame(width: 19, height: 19)
            .foregroundStyle(secondary)
            .frame(width: 38, height: 38)
            .background(card, in: Circle())
    }

    /// Your handle in the invite link: your first name, lowercased.
    private static var inviteHandle: String {
        (UserDefaults.standard.string(forKey: "profile.name") ?? "amber").lowercased()
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "amber"
    }

    // MARK: - Your circle

    /// A native horizontal scroll supplies the snapping and momentum; each friend
    /// is then bent from its place on the straight strip onto the dial's rim.
    private var dial: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: dialArc - portraitSize) {
                ForEach(dialSlots, id: \.self) { slot in
                    dialItem(visibleCircle[slot % visibleCircle.count], slot: slot)
                }
            }
            .scrollTargetLayout()
            // A horizontal scroll view centres shorter content vertically; the
            // dial's top has to sit at the top of the strip.
            .frame(height: dialHeight, alignment: .top)
        }
        // Inset by half a screen so the first and last friend can reach the top.
        .safeAreaPadding(.horizontal, max(0, (screenWidth - portraitSize) / 2))
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centeredSlot, anchor: .center)
        // A tick each time a friend settles at the top, not when the dial parks.
        .sensoryFeedback(.selection, trigger: centeredSlot) { old, new in old != nil && new != nil }
        // Friends further round the rim hang below the strip's frame.
        .scrollClipDisabled()
        .onChange(of: centeredSlot) {
            if let friend = centeredFriend { dialFriendID = friend.id }
        }
        .onAppear { recenter() }
        // The strip's insets follow the width, which lands after the first pass
        // and leaves the strip parked on the first friend.
        .onChange(of: screenWidth) { recenter() }
        // Accepting a request or searching changes who's on the dial; stay on
        // the same friend if they're still there.
        .onChange(of: visibleCircle.map(\.id)) { recenter() }
        .frame(height: dialHeight)
    }

    private var dialHeight: CGFloat { portraitSize + dialDrop + nameGap + 24 }

    /// Puts the dial's friend (or the first one) at the top in the middle lap,
    /// a beat later so the strip has laid out.
    private func recenter() {
        let index = visibleCircle.firstIndex { $0.id == dialFriendID } ?? 0
        let slot = middleSlot(for: index)
        centeredSlot = nil
        DispatchQueue.main.async { centeredSlot = slot }
    }

    /// How far a view sits from the middle of the screen, along the strip. The
    /// dial runs edge to edge, so the screen's middle is the dial's top.
    private static func distanceFromMiddle(_ proxy: GeometryProxy, screenWidth: CGFloat) -> CGFloat {
        proxy.frame(in: .global).midX - screenWidth / 2
    }

    private func dialItem(_ friend: KithContact, slot: Int) -> some View {
        let isCentered = slot == centeredSlot
        let radius = dialRadius
        let arc = dialArc
        let width = screenWidth

        return Button {
            if isCentered {
                overview = friend
            } else {
                centeredSlot = slot
            }
        } label: {
            VStack(spacing: nameGap) {
                ContactAvatar(contact: friend, diameter: portraitSize, initialsFont: .kithDisplay)

                Text(friend.firstName)
                    .font(isCentered ? .kithBodyStrong : .kithSecondary)
                    .foregroundStyle(isCentered ? ink : secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // Names fade out past the first friend either side, as in the comp.
                    .visualEffect { content, proxy in
                        let along = abs(Self.distanceFromMiddle(proxy, screenWidth: width))
                        return content.opacity(min(1, max(0, 2 - along / arc)))
                    }
            }
            .frame(width: portraitSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .visualEffect { content, proxy in
            // Distance along the strip becomes distance around the rim.
            let along = Self.distanceFromMiddle(proxy, screenWidth: width)
            let angle = along / radius
            // Only the front half of the dial exists. Past a quarter turn a
            // friend would wrap round onto the ones in front, so they stay on
            // the straight strip, which is already well off screen there.
            let onDial = abs(angle) < .pi / 2
            return content
                .offset(
                    x: onDial ? radius * sin(angle) - along : 0,
                    y: onDial ? radius * (1 - cos(angle)) : 0
                )
                .opacity(onDial ? 1 : 0)
        }
        .accessibilityLabel(friend.name)
        .accessibilityAddTraits(isCentered ? .isSelected : [])
        .accessibilityHint(isCentered ? "Opens your time with \(friend.firstName)" : "Brings \(friend.firstName) to the middle")
    }

    // MARK: - Requests

    private func requestRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 3.5) {
            HStack(alignment: .top, spacing: 15) {
                ContactAvatar(contact: request.contact, diameter: 40, badgeRing: card)

                nameStack(request.contact, connection: request.connection)
                    .padding(.vertical, 3)

                Spacer(minLength: 8)

                Text(Self.shortAge(since: request.received))
                    .font(.kithFootnote)
                    .foregroundStyle(secondary)
                    .accessibilityLabel(request.received.formatted(.relative(presentation: .named)))
            }

            HStack(spacing: 10) {
                Button { respond(to: request, accept: false) } label: {
                    Text("Decline")
                        .font(.kithCaption)
                        .kithCapCentered(13, relativeTo: .footnote)
                        .foregroundStyle(KithTheme.canvas(isDark))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 31)
                        .background(ink, in: Capsule())
                }
                .accessibilityLabel("Decline \(request.contact.firstName)")

                Button { respond(to: request, accept: true) } label: {
                    Text("Accept")
                        .font(.kithCaption)
                        .kithCapCentered(13, relativeTo: .footnote)
                        .foregroundStyle(KithTheme.secondaryOnFill(isDark))
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, minHeight: 31)
                        .overlay(Capsule().strokeBorder(secondary, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .accessibilityLabel("Accept \(request.contact.firstName)")
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.leading, 40 + 15)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Suggestions

    private func suggestionRow(_ suggestion: FriendSuggestion) -> some View {
        let contact = suggestion.contact

        return HStack(spacing: 10) {
            ContactAvatar(contact: contact, diameter: 40, badgeRing: card)

            nameStack(contact, connection: suggestion.connection)
                .frame(maxWidth: .infinity, alignment: .leading)

            requestButton(for: contact)
        }
        .frame(minHeight: 44)
    }

    /// Says what it does: people on Bloom get a friend request they have to
    /// accept, and people who aren't get an invite over Messages. Once sent it
    /// reads "Requested" or "Invited"; tapping a request again withdraws it.
    private func requestButton(for contact: KithContact) -> some View {
        let sent = requested.contains(contact.id)
        let title = contact.isOnKith ? (sent ? "Requested" : "Request") : (sent ? "Invited" : "Invite")

        return Button {
            if sent {
                if contact.isOnKith { requested.remove(contact.id) }
            } else {
                requested.insert(contact.id)
                if !contact.isOnKith {
                    inviting = MessageDraft(contact: contact)
                }
            }
        } label: {
            Text(title)
                .font(.kithCaption)
                .kithCapCentered(13, relativeTo: .footnote)
                .foregroundStyle(sent ? KithTheme.secondaryOnFill(isDark) : KithTheme.canvas(isDark))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 86)
                .frame(height: 30)
                .background {
                    if sent {
                        Capsule().strokeBorder(secondary, lineWidth: 1)
                    } else {
                        Capsule().fill(ink)
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        // An invite has gone out over Messages; there's nothing to take back.
        .disabled(sent && !contact.isOnKith)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: sent)
        .sensoryFeedback(.impact(weight: .light), trigger: sent)
        .accessibilityLabel(
            contact.isOnKith
                ? (sent ? "Friend request sent to \(contact.firstName)" : "Send \(contact.firstName) a friend request")
                : (sent ? "Invited \(contact.firstName)" : "Invite \(contact.firstName) to Bloom over Messages")
        )
        .accessibilityHint(sent && contact.isOnKith ? "Withdraws the request" : "")
    }

    // MARK: - Shared pieces

    private func nameStack(_ contact: KithContact, connection: Connection?) -> some View {
        // The comp's name and subtitle sit 16.5pt apart, baseline to baseline.
        VStack(alignment: .leading, spacing: 4.5) {
            Text(contact.name)
                .font(.kithCardTitle)
                .foregroundStyle(ink)
                .lineLimit(1)

            if let connection {
                connectionText(connection)
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
            }
        }
    }

    private func connectionText(_ connection: Connection) -> Text {
        switch connection {
        case let .friendsWith(name, andOthers):
            let mutual = Text(name).font(.kithCaptionHeavy)
            return andOthers
                ? Text("Friends with \(mutual) and others")
                : Text("Friends with \(mutual)")
        case let .note(note):
            return Text(note)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.horizontal, gutter)
    }

    // MARK: - Actions

    private func respond(to request: FriendRequest, accept: Bool) {
        let change = {
            requests.removeAll { $0.id == request.id }
            if accept {
                circle.append(request.contact)
                accepted += 1
            }
        }
        if reduceMotion { change() } else { withAnimation(.spring(response: 0.32, dampingFraction: 0.85), change) }
    }

    /// Suggestions keep coming as you scroll, the way a real contact book would.
    private func loadMoreIfLast(_ suggestion: FriendSuggestion) {
        guard search.isEmpty, suggestion.id == suggestions.last?.id else { return }
        suggestions += FriendSuggestion.page(after: suggestions.count)
    }

    private func matchesSearch(_ contact: KithContact) -> Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty || contact.name.localizedCaseInsensitiveContains(query)
    }

    /// The comp's compact age: "5m", "5h", "5d".
    static func shortAge(since date: Date, now: Date = .now) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 60 * 24 { return "\(minutes / 60)h" }
        return "\(minutes / (60 * 24))d"
    }
}

// MARK: - Avatar

/// A contact's photo or initials, with the iMessage badge for people not on Kith yet.
struct ContactAvatar: View {
    let contact: KithContact
    let diameter: CGFloat
    var initialsFont: Font = .kithInitialsSmall
    /// The badge's outline matches whatever the avatar sits on.
    var badgeRing: Color = .clear

    var body: some View {
        face
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                if !contact.isOnKith {
                    Image("MessageBubbleIcon")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 8, height: 8)
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(KithTheme.messagesGreen, in: Circle())
                        .overlay(Circle().strokeBorder(badgeRing, lineWidth: 1.5))
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var face: some View {
        switch contact.face {
        case let .photo(portrait) where UIImage(named: portrait.asset) != nil:
            // Fill, never stretch: a framing with the wrong aspect crops the
            // photo instead of squashing the face.
            Image(portrait.asset)
                .resizable()
                .scaledToFill()
                .frame(width: diameter * portrait.width, height: diameter * portrait.height)
                .offset(x: diameter * portrait.x, y: diameter * portrait.y)
        case .photo:
            // A photo that isn't in the app yet: their initials on their colour.
            Text(String(contact.name.split(separator: " ").compactMap(\.first).prefix(2)))
                .font(initialsFont)
                .kithCapCentered(diameter * 0.26, relativeTo: .title3)
                .foregroundStyle(KithTheme.ink(false))
                .frame(width: diameter, height: diameter)
                .background(contact.blob.color)
        case let .initials(letters, background, ink):
            Text(letters)
                .font(initialsFont)
                .kithCapCentered(diameter * 0.26, relativeTo: .title3)
                .foregroundStyle(ink)
                .frame(width: diameter, height: diameter)
                .background(background)
        }
    }
}

// MARK: - Sample data

extension KithContact {
    /// Your circle, framed the way the comp crops each photo.
    static let circleSample: [KithContact] = DemoCast.isJudge ? DemoCast.circle : [
        KithContact(
            name: "Manitej Boorgu",
            face: .photo(Portrait(asset: "FriendAvatar", width: 2.5919, height: 1.7318, x: 0.1038, y: -0.0007)),
            note: "best study buddy ever!!!"
        ),
        KithContact(
            name: "Ishan Goyal",
            face: .photo(Portrait(asset: "AvatarIshan", width: 1.0751, height: 1.2933, x: -0.0173, y: -0.09))
        ),
        KithContact(
            name: "Ray Arayilikath",
            face: .photo(Portrait(asset: "AvatarRay", width: 1.2465, height: 1.5581, y: 0.164))
        )
    ]
    // Everyone else from the recaps is a friend too, after the comp's own
    // three. (Jadden and Michelle stay a suggestion and a request, as drawn.)
    + ["Dev", "Theo", "Amara", "Nina", "Kenji", "Sofia", "Priya", "Sam"].compactMap { RecentHangout.recapFriends[$0] }
}

/// Stand-in people so the lists feel like a real contact book. They're
/// generated rather than random, so the same names come back every launch.
enum SamplePeople {
    private static let first = [
        "Aanya", "Ben", "Camila", "Dev", "Elena", "Felix", "Grace", "Hiro", "Isla", "Jonah",
        "Kavya", "Liam", "Maya", "Nico", "Olivia", "Priya", "Quinn", "Rosa", "Sam", "Tara",
        "Umar", "Vera", "Wes", "Ximena", "Yusuf", "Zoe", "Arjun", "Bella", "Caleb", "Dana",
        "Eli", "Farah", "Gus", "Hana", "Ivan", "June", "Kai", "Lena", "Marco", "Nadia"
    ]
    private static let last = [
        "Abbott", "Bose", "Castro", "Diaz", "Eriksen", "Fong", "Garcia", "Hughes", "Iyer",
        "Jensen", "Kim", "Lopez", "Mehta", "Nguyen", "Okafor", "Park", "Quintero", "Reyes",
        "Shah", "Tanaka", "Usman", "Vega", "Walsh", "Xu", "Yamada", "Zhang", "Alvarez",
        "Brooks", "Chen", "Dubois", "Evans", "Ferreira", "Gupta", "Haddad", "Ito", "Jones", "Kowalski"
    ]

    /// How many different people there are: every first name with every last.
    static var count: Int { first.count * last.count }

    /// The `index`th made-up person. First names cycle fastest; each lap steps
    /// the last name by one more than the first-name count, and because that
    /// step shares no factor with the last-name count, every pair turns up once.
    static func name(_ index: Int) -> String {
        let wrapped = index % count
        let lap = wrapped / first.count
        let firstIndex = wrapped % first.count
        let lastIndex = (lap * (first.count + 1) + firstIndex) % last.count
        return "\(first[firstIndex]) \(last[lastIndex])"
    }

    /// Initials on the person's own blob colour.
    static func contact(_ index: Int, isOnKith: Bool) -> KithContact {
        let name = name(index)
        let letters = String(name.split(separator: " ").compactMap(\.first))
        return KithContact(
            name: name,
            face: .initials(letters, background: FriendBlob.forName(name).color, ink: KithTheme.ink(false)),
            isOnKith: isOnKith
        )
    }
}

extension FriendRequest {
    static let sample = DemoCast.isJudge ? DemoCast.requests : [
        FriendRequest(
            contact: KithContact(name: "Michelle Xuan", face: .photo(Portrait(asset: "AvatarMichelle", height: 2))),
            connection: .friendsWith("Ishan", andOthers: true),
            received: .now.addingTimeInterval(-60)
        )
    ]
}

extension FriendSuggestion {
    private static let violet = Color(red: 0.451, green: 0.271, blue: 1.0)   // #7345FF
    private static let coral = Color(red: 0.898, green: 0.376, blue: 0.376)  // #E56060
    private static let slate = Color(red: 0.580, green: 0.580, blue: 0.580)  // #949494
    private static let nearBlack = Color(red: 0.067, green: 0.067, blue: 0.067) // #111111

    /// The judge's build leaves out the comps' real people and the second Leo.
    static let sample = comps.filter { !DemoCast.isJudge || !["Jadden Picardal", "Leo Chen"].contains($0.contact.name) }

    private static let comps = [
        FriendSuggestion(
            contact: KithContact(name: "Jadden Picardal", face: .photo(Portrait(asset: "AvatarJadden"))),
            connection: .friendsWith("Ishan")
        ),
        FriendSuggestion(
            contact: KithContact(name: "Alicia Zhou", face: .initials("AZ", background: violet, ink: KithTheme.canvas(false)), isOnKith: false)
        ),
        FriendSuggestion(
            contact: KithContact(
                name: "Gabriel",
                face: .initials("GL", background: KithTheme.availability, ink: nearBlack),
                isOnKith: false
            ),
            connection: .note("3 friends on Bloom")
        ),
        FriendSuggestion(
            contact: KithContact(name: "Leo Chen", face: .initials("LC", background: coral, ink: KithTheme.canvas(false)), isOnKith: false)
        ),
        FriendSuggestion(
            contact: KithContact(name: "Mia Singh", face: .initials("MS", background: slate, ink: KithTheme.canvas(false)), isOnKith: false),
            connection: .note("Mutual: 2 friends")
        ),
        FriendSuggestion(
            contact: KithContact(name: "Jordan Tan", face: .initials("JT", background: violet, ink: KithTheme.canvas(false)), isOnKith: false),
            connection: .note("Mutual: 1 friend")
        )
    ]

    /// The next `size` suggestions after the first `count`. The comp's six come
    /// first, then the made-up people, until they run out.
    static func page(after count: Int, size: Int = 20) -> [FriendSuggestion] {
        let start = max(0, count - sample.count)
        let end = min(start + size, SamplePeople.count)
        guard start < end else { return [] }

        let mutuals = DemoCast.isJudge ? DemoCast.mutuals : ["Ishan", "Manitej", "Ray"]
        return (start..<end).map { index in
            let connection: Connection?
            switch index % 4 {
            case 0: connection = .friendsWith(mutuals[index % mutuals.count])
            case 1: connection = .note("Mutual: \(2 + index % 6) friends")
            case 2: connection = nil
            default: connection = .note("\(1 + index % 9) friends on Bloom")
            }
            return FriendSuggestion(contact: SamplePeople.contact(index, isOnKith: index % 3 == 0), connection: connection)
        }
    }
}

#Preview {
    MainTabView()
}
