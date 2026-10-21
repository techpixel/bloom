import PhotosUI
import SwiftUI
import UIKit

/// Profile: who you are on Kith, then the settings that decide what it nudges
/// you about and what it shares. Like the onboarding permission pages, the
/// toggles here record your choice without touching device data.
struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("profile.name") private var name = "Amber"
    @AppStorage("settings.push") private var pushNotifications = true
    @AppStorage("settings.reminders") private var reminders = true
    @AppStorage("settings.nearby") private var friendsNearby = true
    @AppStorage("settings.recaps") private var weeklyRecaps = true
    /// One switch for everything Bloom shares. Home goes quiet while it's on.
    @AppStorage("settings.onBreak") private var onBreak = false

    @State private var editingName = false
    @State private var choosingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    /// The photo you chose, if any; the comp's photo otherwise.
    @State private var customPhoto: UIImage? = ProfilePhotoStore.load()
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @State private var confirmingLogOut = false
    /// How many Google calendars are connected; 0 is not connected.
    @AppStorage("calendar.google") private var googleCalendars = 0
    @AppStorage("calendar.apple") private var appleCalendarConnected = false
    @State private var connectingGoogle = false
    @State private var askingForCalendar = false
    @State private var disconnecting: CalendarSource?
    @State private var screenWidth = Self.designWidth

    var onLogOut: (() -> Void)?

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var card: Color { KithTheme.suggestionCard(isDark) }

    // Measured off the comp, an iPhone 16 frame (393 × 852), and scaled by the
    // screen's width like the Friends tab. Type is left to Dynamic Type.
    private static let designWidth: CGFloat = 393
    private var scale: CGFloat { screenWidth / Self.designWidth }
    private var gutter: CGFloat { 20 * scale }
    private var photoSize: CGFloat { 192 * scale }

    /// Where the comp crops the photo inside its circle.
    private static let photo = Portrait(asset: "ProfilePhoto", width: 1.0105, height: 1.3474, x: 0.0053, y: 0.1737)

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                portrait
                    .padding(.top, 50 * scale)

                // The glow reaches past the photo's edge; the name clears it.
                nameRow
                    .padding(.top, 36 * scale)

                VStack(alignment: .leading, spacing: 24 * scale) {
                    notifications
                    sharing
                    calendars

                    section("Account") {
                        linkRow(
                            icon: "SettingsLogOut",
                            title: "Log out",
                            detail: "Sign out of your account",
                            showsChevron: false,
                            tint: KithTheme.logOut
                        ) {
                            confirmingLogOut = true
                        }
                    }

                    footer
                }
                .padding(.horizontal, gutter)
                .padding(.top, 28 * scale)
            }
            .padding(.bottom, 24)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .scrollDismissesKeyboard(.immediately)
        .background(KithTheme.canvas(isDark))
        .statusBarHidden(true)
        .photosPicker(isPresented: $choosingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
        .sheet(isPresented: $connectingGoogle) {
            GoogleCalendarConnectSheet { googleCalendars = $0 }
        }
        // The replica system alert has to cover the tab bar too, and appears
        // without the cover's slide, like the real one.
        .fullScreenCover(isPresented: $askingForCalendar) {
            SystemAlertView(alert: .calendar) { choice in
                appleCalendarConnected = choice.grants
                withoutAnimation { askingForCalendar = false }
            }
            .presentationBackground(.clear)
        }
        .confirmationDialog(
            Text(disconnecting.map { "Disconnect \($0.title)?" } ?? ""),
            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
            titleVisibility: .visible,
            presenting: disconnecting
        ) { source in
            Button("Disconnect", role: .destructive) { disconnect(source) }
        } message: { _ in
            Text("Bloom will stop using its busy times to find when you're free.")
        }
        .sensoryFeedback(.success, trigger: googleCalendars) { old, new in old == 0 && new > 0 }
        .sensoryFeedback(.success, trigger: appleCalendarConnected) { _, new in new }
        .confirmationDialog("Log out of Bloom?", isPresented: $confirmingLogOut, titleVisibility: .visible) {
            Button("Log out", role: .destructive) { onLogOut?() }
        }
    }

    // MARK: - Header

    private var portrait: some View {
        Button { choosingPhoto = true } label: {
            photoFace
                .overlay(alignment: .bottomTrailing) { photoPencil }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Profile photo")
        .accessibilityHint("Choose a new photo")
    }

    private var photoFace: some View {
        Group {
            if let customPhoto {
                Image(uiImage: customPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: photoSize, height: photoSize)
                    .clipShape(Circle())
            } else {
                ContactAvatar(contact: KithContact(name: name, face: .photo(Self.photo)), diameter: photoSize)
            }
        }
        .background {
            // The comp's mint glow, rasterised because its grain and blur are
            // SVG filters the asset catalog can't draw.
            Image("ProfileGlow")
                .resizable()
                .frame(width: 262.69 * scale, height: 254.62 * scale)
                .rotationEffect(.degrees(90.45))
                .offset(x: 2.44 * scale, y: -2.13 * scale)
                .accessibilityHidden(true)
        }
    }

    /// A pencil on the photo's lower right, on the circle's edge, so it reads
    /// as "change this".
    private var photoPencil: some View {
        Image("PencilIcon")
            .renderingMode(.template)
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundStyle(ink)
            .frame(width: 36, height: 36)
            .background(KithTheme.canvas(isDark), in: Circle())
            .overlay(Circle().strokeBorder(KithTheme.uiFill(isDark), lineWidth: 1.5))
            // On the circle's edge at about 4:30.
            .offset(x: -photoSize * 0.146 + 18, y: -photoSize * 0.146 + 18)
            .accessibilityHidden(true)
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            if editingName {
                TextField("Your name", text: $draftName)
                    .font(.kithHeading)
                    .foregroundStyle(ink)
                    .tint(ink)
                    .multilineTextAlignment(.center)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .focused($nameFocused)
                    .onSubmit(saveName)
                    .frame(maxWidth: 260 * scale)
            } else {
                Text(name)
                    .font(.kithHeading)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityAddTraits(.isHeader)

                Menu {
                    Button("Choose photo…", systemImage: "photo") { choosingPhoto = true }
                    Button("Edit name", systemImage: "character.cursor.ibeam", action: startEditingName)
                    if customPhoto != nil {
                        Button("Remove photo", systemImage: "trash", role: .destructive) { usePhoto(nil) }
                    }
                } label: {
                    Image("PencilIcon")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(ink)
                        // A 44pt target without moving the pencil off the name.
                        .padding(14)
                        .contentShape(Rectangle())
                        .padding(-14)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Edit profile")
            }
        }
        .onChange(of: nameFocused) { _, focused in
            if !focused { saveName() }
        }
    }

    // MARK: - Settings

    private var notifications: some View {
        section("Notifications") {
            toggleRow(
                icon: "SettingsBell",
                title: "Push notifications",
                detail: "Let Bloom reach you on this phone",
                isOn: $pushNotifications
            )
            separator
            toggleRow(
                icon: "SettingsClock",
                title: "Check-in reminders",
                detail: "Gentle nudges when it's been a while",
                isOn: $reminders,
                needsPush: true
            )
            separator
            toggleRow(
                icon: "TabFriends",
                title: "Friends nearby",
                detail: "When someone you know is close by",
                isOn: $friendsNearby,
                needsPush: true
            )
            separator
            toggleRow(
                icon: "TabRecaps",
                title: "Weekly recaps",
                detail: "Summarize your time together",
                isOn: $weeklyRecaps,
                needsPush: true
            )
        }
    }

    /// Instead of a toggle per thing Bloom shares, one: take a break, and it
    /// all stops until you're back.
    private var sharing: some View {
        section("Sharing") {
            toggleRow(
                icon: "SettingsPin",
                title: "Take a break",
                detail: onBreak
                    ? "You're on a break. Location sharing is off, friends can't see you or when you're free, and Bloom won't log hangouts or nudge you until you turn this off."
                    : "Turns off location sharing, so friends won't see you or when you're free. Bloom stops logging hangouts and nudging you until you're back.",
                isOn: $onBreak.animation(.easeInOut(duration: 0.25))
            )
        }
    }

    private var calendars: some View {
        section("Calendars") {
            calendarRow(.google)
            separator
            calendarRow(.apple)
        }
    }

    /// Connect or, once connected, show what's connected; tapping "Connected"
    /// offers to disconnect.
    private func calendarRow(_ source: CalendarSource) -> some View {
        let connected = isConnected(source)

        return HStack(spacing: 10) {
            rowLabel(
                icon: "SettingsCalendar",
                title: source.title,
                detail: connected ? source.connectedDetail(calendars: googleCalendars) : source.pitch
            )

            Spacer(minLength: 8)

            Button {
                if connected { disconnecting = source } else { connect(source) }
            } label: {
                Text(connected ? "Connected" : "Connect")
                    .font(.kithCaption)
                    .kithCapCentered(13, relativeTo: .footnote)
                    .foregroundStyle(connected ? KithTheme.secondaryOnFill(isDark) : KithTheme.canvas(isDark))
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background {
                        if connected {
                            Capsule().strokeBorder(secondary, lineWidth: 1)
                        } else {
                            Capsule().fill(ink)
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(connected ? "\(source.title) connected" : "Connect \(source.title)")
            .accessibilityHint(connected ? "Offers to disconnect it" : "")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func isConnected(_ source: CalendarSource) -> Bool {
        switch source {
        case .google: return googleCalendars > 0
        case .apple: return appleCalendarConnected
        }
    }

    private func connect(_ source: CalendarSource) {
        switch source {
        case .google: connectingGoogle = true
        case .apple: withoutAnimation { askingForCalendar = true }
        }
    }

    private func disconnect(_ source: CalendarSource) {
        switch source {
        case .google: googleCalendars = 0
        case .apple: appleCalendarConnected = false
        }
    }

    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                rows()
            }
            .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    /// Notification kinds switch off with push itself, so they read as part of it.
    private func toggleRow(
        icon: String,
        title: String,
        detail: String,
        isOn: Binding<Bool>,
        needsPush: Bool = false
    ) -> some View {
        let blocked = needsPush && !pushNotifications

        return Toggle(isOn: isOn) {
            rowLabel(icon: icon, title: title, detail: detail)
        }
        .tint(KithTheme.overlap)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .disabled(blocked)
        .opacity(blocked ? 0.45 : 1)
        .accessibilityHint(blocked ? "Turn on push notifications first" : "")
    }

    private func linkRow(
        icon: String,
        title: String,
        detail: String,
        showsChevron: Bool = true,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                rowLabel(icon: icon, title: title, detail: detail, tint: tint)
                Spacer(minLength: 8)
                if showsChevron {
                    Image("ChevronRightIcon")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(icon: String, title: String, detail: String, tint: Color? = nil) -> some View {
        HStack(spacing: 10) {
            Image(icon)
                .renderingMode(.template)
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(tint ?? ink)
                .frame(width: 32, height: 32)
                .background(KithTheme.canvas(isDark), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.kithCardTitle)
                    .foregroundStyle(tint ?? ink)
                Text(detail)
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A hairline that starts under the text, past the icon, as iOS lists do.
    private var separator: some View {
        Rectangle()
            .fill(ink.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 12 + 32 + 10)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text("bloom · gentle relationship awareness")
                .font(.kithCaption)
                .foregroundStyle(secondary)

            Button("Privacy & terms") { /* TODO: privacy & terms page */ }
                .font(.kithCaption)
                .foregroundStyle(KithTheme.navActive)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func usePhoto(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        usePhoto(image)
    }

    private func usePhoto(_ image: UIImage?) {
        customPhoto = image
        ProfilePhotoStore.save(image)
    }

    private func startEditingName() {
        draftName = name
        editingName = true
        nameFocused = true
    }

    private func saveName() {
        guard editingName else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { name = trimmed }
        editingName = false
        nameFocused = false
    }
}

#Preview {
    ProfileView()
}

/// Your chosen profile photo, kept in the app's own Documents folder. The system
/// picker hands over only the photo you pick, so no library access is needed.
enum ProfilePhotoStore {
    private static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile-photo.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    static func save(_ image: UIImage?) {
        if let data = image?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
