import PhotosUI
import SwiftUI
import UIKit

/// Profile: who you are on Kith, then the settings that decide what it nudges
/// you about and what it shares. Like the onboarding permission pages, the
/// toggles here record your choice without touching device data.
struct ProfileView: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("profile.name") private var name = DemoCast.placeholderName
    @AppStorage("settings.push") private var pushNotifications = true
    @AppStorage("settings.reminders") private var reminders = true
    @AppStorage("settings.nearby") private var friendsNearby = true
    @AppStorage("settings.recaps") private var weeklyRecaps = true
    /// One switch for everything Bloom shares. Home goes quiet while it's on.
    @AppStorage("settings.onBreak") private var onBreak = false

    @State private var editingProfile = false
    @State private var choosingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    /// The photo you chose, if any; the comp's photo otherwise.
    @State private var customPhoto: UIImage? = ProfilePhotoStore.load()
    @State private var draftName = ""
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
                HStack {
                    Spacer(minLength: 0)
                    editButton
                }
                .padding(.horizontal, gutter)
                .padding(.top, 10 * scale)

                portrait
                    .padding(.top, 14 * scale)

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
                            title: "Log Out",
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
        .sheet(isPresented: $editingProfile) { profileEditor }
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
            Text("Bloom will stop using its busy times to find when you’re free.")
        }
        .sensoryFeedback(.success, trigger: googleCalendars) { old, new in old == 0 && new > 0 }
        .sensoryFeedback(.success, trigger: appleCalendarConnected) { _, new in new }
        .confirmationDialog("Log out of Bloom?", isPresented: $confirmingLogOut, titleVisibility: .visible) {
            Button("Log Out", role: .destructive) { onLogOut?() }
        }
    }

    // MARK: - Header

    private var portrait: some View {
        photoFace
            .accessibilityLabel("Profile photo")
    }

    private var photoFace: some View {
        Group {
            if let customPhoto {
                Image(uiImage: customPhoto)
                    .resizable()
                    .scaledToFill()
                    .frame(width: photoSize, height: photoSize)
                    .clipShape(Circle())
            } else if ProfilePhotoStore.removed {
                ProfilePhotoStore.blank(diameter: photoSize, dark: isDark)
            } else if DemoCast.isJudge {
                // No stand-in face in the judge's build: your initials until you pick a photo.
                ContactAvatar(contact: KithContact(name: name, face: DemoCast.initials(name, .mint)), diameter: photoSize)
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

    private var nameRow: some View {
        Text(name)
            .font(.kithHeading)
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(minHeight: 44)
            .accessibilityAddTraits(.isHeader)
    }

    private var editButton: some View {
        Button(action: beginEditingProfile) {
            Text("Edit")
                .font(.kithCaptionStrong)
                .kithCapCentered(13, relativeTo: .footnote)
                .foregroundStyle(secondary)
                .padding(.horizontal, 18)
                .frame(height: 32)
                .background(KithTheme.uiFill(isDark), in: Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Edit profile")
    }

    /// Name and photo together, so neither needs a pencil of its own and the
    /// page doesn't reflow underneath you while you type.
    private var profileEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit profile")
                .font(.kithHeading)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.kithCaption)
                    .foregroundStyle(secondary)

                TextField("Your name", text: $draftName)
                    .font(.kithBody)
                    .foregroundStyle(ink)
                    .tint(ink)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .onSubmit(saveProfile)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .background(KithTheme.uiFill(isDark), in: Capsule())
                    .accessibilityLabel("Your name")
            }

            HStack(spacing: 10) {
                editorAction("Choose photo") { choosingPhoto = true }
                if customPhoto != nil {
                    editorAction("Remove Photo") { usePhoto(nil) }
                }
            }

            Button(action: saveProfile) {
                Text("Save")
                    .font(.kithBody)
                    .kithCapCentered(17, relativeTo: .body)
                    .foregroundStyle(KithTheme.canvas(isDark))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(ink, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 4)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KithTheme.canvas(isDark).ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .photosPicker(isPresented: $choosingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await usePhoto(item) }
        }
    }

    private func editorAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kithCaption)
                .kithCapCentered(13, relativeTo: .footnote)
                .foregroundStyle(secondary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(KithTheme.uiFill(isDark), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Settings

    private var notifications: some View {
        section("Notifications") {
            toggleRow(
                icon: "SettingsBell",
                title: "Push Notifications",
                detail: "Let Bloom reach you on this phone",
                isOn: $pushNotifications
            )
            separator
            toggleRow(
                icon: "SettingsClock",
                title: "Check-In Reminders",
                detail: "Gentle nudges when it’s been a while",
                isOn: $reminders,
                needsPush: true
            )
            separator
            toggleRow(
                icon: "TabFriends",
                title: "Friends Nearby",
                detail: "When someone you know is close by",
                isOn: $friendsNearby,
                needsPush: true
            )
            separator
            toggleRow(
                icon: "TabRecaps",
                title: "Weekly Recaps",
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
                title: "Take a Break",
                detail: onBreak
                    ? "You’re on a break. Location sharing is off, friends can’t see you or when you’re free, and Bloom won’t log hangouts or nudge you until you turn this off."
                    : "Turns off location sharing, so friends won’t see you or when you’re free. Bloom stops logging hangouts and nudging you until you’re back.",
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
            Text("Bloom · Gentle relationship awareness")
                .font(.kithCaption)
                .foregroundStyle(secondary)

            Button("Privacy & Terms") { /* TODO: privacy & terms page */ }
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
        // Removing it leaves the circle empty, not back on the sample photo.
        ProfilePhotoStore.removed = image == nil
    }

    private func beginEditingProfile() {
        draftName = name
        editingProfile = true
    }

    private func saveProfile() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { name = trimmed }
        editingProfile = false
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

    /// Set when you take your photo away, so the circle stays empty.
    static var removed: Bool {
        get { UserDefaults.standard.bool(forKey: "profile.photoRemoved") }
        set { UserDefaults.standard.set(newValue, forKey: "profile.photoRemoved") }
    }

    /// An empty circle with a quiet silhouette: no photo yet.
    static func blank(diameter: CGFloat, dark: Bool) -> some View {
        Circle()
            .fill(KithTheme.uiFill(dark))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.36))
                    .foregroundStyle(KithTheme.secondary(dark).opacity(0.5))
            )
            .frame(width: diameter, height: diameter)
            .accessibilityLabel("No photo")
    }

    static func save(_ image: UIImage?) {
        if image != nil { removed = false }
        if let data = image?.jpegData(compressionQuality: 0.85) {
            try? data.write(to: url, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
