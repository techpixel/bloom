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
    /// The editor's working copy of the photo; nothing changes until Save.
    @State private var draftPhoto: UIImage?
    @State private var draftRemoved = false
    @State private var confirmingDiscard = false
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
    private var card: Color { KithTheme.uiFill(isDark) }

    // Measured off the comp, an iPhone 16 frame (393 × 852), and scaled by the
    // screen's width like the Friends tab. Type is left to Dynamic Type.
    private static let designWidth: CGFloat = 393
    private var scale: CGFloat { screenWidth / Self.designWidth }
    private var gutter: CGFloat { 20 * scale }
    private var photoSize: CGFloat { 192 * scale }


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

                VStack(alignment: .leading, spacing: 32 * scale) {
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
        .progressiveTopBlur()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .scrollDismissesKeyboard(.immediately)
        .background(KithTheme.canvas(isDark))
        .statusBarHidden(true)
        .drawer(isPresented: $editingProfile) { profileEditor }
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
            } else {
                // No photo yet: an empty contact silhouette, never a stand-in face.
                ProfilePhotoStore.blank(diameter: photoSize, dark: isDark)
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
                .kithCapCentered(15, relativeTo: .footnote)
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

    /// Name and photo together, as a draft: a preview at the top shows what
    /// you'll get, Save applies it, Cancel (or swiping down with nothing
    /// changed) leaves your profile exactly as it was.
    private var profileEditor: some View {
        NavigationStack {
            VStack(spacing: 20) {
                draftPreview
                    .padding(.top, 4)

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
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(KithTheme.uiFill(isDark), in: Capsule())
                        .accessibilityLabel("Your name")
                }

                HStack(spacing: 10) {
                    editorAction(draftHasPhoto ? "Change Photo" : "Choose Photo") { choosingPhoto = true }
                    if draftHasPhoto {
                        editorAction("Remove Photo") {
                            withAnimation(.easeOut(duration: 0.2)) {
                                draftPhoto = nil
                                draftRemoved = true
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KithTheme.canvas(isDark).ignoresSafeArea())
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancelEditing)
                        .foregroundStyle(ink)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: saveProfile)
                        .fontWeight(.semibold)
                        .foregroundStyle(ink)
                        .disabled(!draftChanged || draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        // With changes in the draft, a swipe down asks first instead of
        // silently throwing them away.
        .interactiveDismissDisabled(draftChanged)
        .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { editingProfile = false }
            Button("Keep Editing", role: .cancel) {}
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await loadDraftPhoto(item) }
        }
    }

    /// The photo and name as they'll look once saved.
    private var draftPreview: some View {
        let side: CGFloat = 120
        return VStack(spacing: 10) {
            Group {
                if let draftPhoto {
                    Image(uiImage: draftPhoto)
                        .resizable()
                        .scaledToFill()
                        .frame(width: side, height: side)
                        .clipShape(Circle())
                } else {
                    ProfilePhotoStore.blank(diameter: side, dark: isDark)
                }
            }
            .transition(.opacity)

            Text(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? " " : draftName)
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview")
    }

    private var draftHasPhoto: Bool { draftPhoto != nil }

    private var draftChanged: Bool {
        draftName.trimmingCharacters(in: .whitespacesAndNewlines) != name
            || draftPhoto !== customPhoto
            || draftRemoved
    }

    private func editorAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.kithCaption)
                .kithCapCentered(15, relativeTo: .footnote)
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
                    .kithCapCentered(15, relativeTo: .footnote)
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
        VStack(alignment: .leading, spacing: 14) {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(minHeight: 68)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(minHeight: 68)
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

    private func usePhoto(_ image: UIImage?) {
        customPhoto = image
        ProfilePhotoStore.save(image)
        // Removing it leaves the circle empty, not back on the sample photo.
        ProfilePhotoStore.removed = image == nil
    }

    private func beginEditingProfile() {
        draftName = name
        draftPhoto = customPhoto
        draftRemoved = false
        editingProfile = true
    }

    private func loadDraftPhoto(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            draftPhoto = image
            draftRemoved = false
        }
    }

    private func cancelEditing() {
        if draftChanged { confirmingDiscard = true } else { editingProfile = false }
    }

    private func saveProfile() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { name = trimmed }
        if draftPhoto !== customPhoto || draftRemoved {
            usePhoto(draftRemoved && draftPhoto == nil ? nil : draftPhoto)
        }
        editingProfile = false
    }
}

#Preview {
    ProfileView()
}

/// Your chosen profile photo, kept in the app's own Documents folder. The system
/// picker hands over only the photo you pick, so no library access is needed.
enum ProfilePhotoStore {
    /// Application Support, not Documents. On iOS both sit inside the app's
    /// container, but the Mac build is unsandboxed, where `.documentDirectory`
    /// is the user's real ~/Documents — so saving a profile photo there made
    /// macOS ask for access to their documents at launch. This is app-owned
    /// data, so it belongs here and asks for nothing.
    private static var url: URL {
        let manager = FileManager.default
        let base = (try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Bloom", isDirectory: true)
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("profile-photo.jpg")
    }

    static func load() -> UIImage? {
        UIImage(contentsOfFile: url.path)
    }

    /// Set when you take your photo away, so the circle stays empty.
    static var removed: Bool {
        get { UserDefaults.standard.bool(forKey: "profile.photoRemoved") }
        set { UserDefaults.standard.set(newValue, forKey: "profile.photoRemoved") }
    }

    /// No photo yet: the contact silhouette, secondary on UI fill, as iOS
    /// draws a contact without a picture.
    static func blank(diameter: CGFloat, dark: Bool) -> some View {
        Circle()
            .fill(KithTheme.uiFill(dark))
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.42))
                    .foregroundStyle(KithTheme.secondary(dark))
                    .offset(y: diameter * 0.04)
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
