import PhotosUI
import SwiftUI

// MARK: - Models

/// How a hangout felt, as Home asks it. More than one can be true.
enum Feeling: String, CaseIterable, Identifiable {
    case connected = "Connected"
    case energized = "Energized"
    case atEase = "At Ease"
    case distant = "Distant"
    case draining = "Draining"
    case somethingElse = "Something Else"

    var id: String { rawValue }
}

/// A photo from a hangout: one of the comp's, or one you added.
enum MeetupPhoto: Identifiable {
    case asset(String)
    case picked(UUID, UIImage)

    var id: String {
        switch self {
        case let .asset(name): return name
        case let .picked(id, _): return id.uuidString
        }
    }
}

extension MeetupPhoto {
    /// The photo, filling whatever frame it's given.
    var image: Image {
        switch self {
        case let .asset(name): return Image(name)
        case let .picked(_, picked): return Image(uiImage: picked)
        }
    }
}

// MARK: - Screen

/// One hangout in detail (comps 69:869, 283:2222, 289:2276): who and where, the
/// photos from it, and your private reflection. When Bloom notices you keep
/// coming back to a place, it offers to let you name it.
struct MeetupDetailView: View {
    @Environment(HangoutStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @Binding var hangout: RecentHangout
    var onBack: () -> Void

    @State private var naming = false
    @State private var editingDetails = false
    @State private var draftActivity = ""
    @State private var draftTime = ""
    @State private var draftPlace = ""
    @State private var draftName = ""
    @State private var draftTags: [String] = []
    @State private var choosingPhoto = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var savedPlace = 0
    /// The offer to name the place waits a beat, then pops in.
    @State private var namingArrived = false
    @State private var screenWidth: CGFloat = 393
    @State private var viewingPhoto: Int?
    @FocusState private var nameFocused: Bool
    @State private var addingTag = false
    @State private var draftTag = ""
    @FocusState private var tagFocused: Bool
    @Namespace private var tagMorph

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var fill: Color { KithTheme.uiFill(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    /// How a place you keep returning to feels.
    private static let tagIdeas = ["casual", "studying", "dinner", "movie"]
    /// Between tags side by side, between rows of tags, and around them.
    private static let tagGap: CGFloat = 6
    private static let tagRowGap: CGFloat = 8
    private static let rowGap: CGFloat = 10

    private var offersToName: Bool {
        hangout.visitsThisMonth >= 3 && hangout.placeName == nil && !hangout.namingDismissed
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            KithTheme.canvas(isDark)
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 74.65 * scale)

                    HStack(spacing: 8) {
                        Text("\(hangout.startTime) with \(hangout.contact.firstName)")
                            .font(.kithHeading)
                            .foregroundStyle(ink)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)

                        Button(action: beginEditingDetails) {
                            Image("PencilIcon")
                                .renderingMode(.template)
                                .resizable()
                                .frame(width: 16, height: 16)
                                .foregroundStyle(secondary)
                                // A 44pt target without pushing the pencil off the title.
                                .padding(14)
                                .contentShape(Rectangle())
                                .padding(-14)
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("Edit Details")
                    }
                    // Clear of the glow, which reaches past the photo.
                    .padding(.top, 26 * scale)

                    placeRow
                        .padding(.top, 6)

                    // Bloom's offer, or you renaming a place you named before.
                    if (offersToName && namingArrived) || (naming && hangout.placeName != nil) {
                        namingCard
                            .padding(.top, 13)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)).combined(with: .offset(y: 6)))
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        photosSection
                        Rectangle()
                            .fill(KithTheme.uiFill(isDark))
                            .frame(height: 2)
                        reflectionSection
                    }
                    .padding(.top, 26 * scale)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .progressiveTopBlur()
            .scrollDismissesKeyboard(.interactively)

        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: offersToName)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: naming)
        .drawer(isPresented: $editingDetails) { detailsEditor }
        .fullScreenCover(isPresented: Binding(get: { viewingPhoto != nil }, set: { if !$0 { viewingPhoto = nil } })) {
            PhotoCarousel(photos: hangout.photos, index: viewingPhoto ?? 0) { viewingPhoto = nil }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
        .sensoryFeedback(.success, trigger: savedPlace)
        // The offer can also arrive while you're here, from the demo remote.
        .sensoryFeedback(trigger: offersToName) { _, offered in offered ? .impact(weight: .light) : nil }
        .onAppear { store.openEntry = hangout.id }
        .onDisappear { if store.openEntry == hangout.id { store.openEntry = nil } }
        .task {
            guard !namingArrived else { return }
            guard !reduceMotion else {
                namingArrived = true
                return
            }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { namingArrived = true }
        }
    }

    // MARK: - Header

    /// The friend's photo over the comp's soft lavender glow.
    /// Comp 69:869: a 145pt photo, its glow scaled to match.
    private var header: some View {
        ContactAvatar(contact: hangout.contact, diameter: 144.886 * scale)
            .background {
                // Rasterised from the comp's vector; its grain and blur are SVG
                // filters the asset catalog can't draw.
                Image("MeetupGlow")
                    .resizable()
                    .frame(width: 209.5 * scale, height: 204.9 * scale)
                    .rotationEffect(.degrees(-28.12))
                    .offset(x: -18.6 * scale, y: 4.7 * scale)
                    .accessibilityHidden(true)
            }
    }

    private var placeRow: some View {
        HStack(spacing: 4) {
            Image("SettingsPin")
                .renderingMode(.template)
                .resizable()
                .frame(width: 18, height: 18)
                .foregroundStyle(secondary)
                .accessibilityHidden(true)

            // Nudged onto the pin's centre: AUTHENTIC Sans sits its letters high.
            // Once you've named it, your name is the place, and tapping it
            // lets you change the name or its tags.
            if let name = hangout.placeName {
                Button(action: beginRenaming) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.kithCardTitle)
                            .foregroundStyle(ink)
                            .kithCapCentered(15, relativeTo: .subheadline)
                        Image("PencilIcon")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.vertical, -10)
                .accessibilityLabel("Rename \(name)")
                .disabled(naming)
            } else {
                Text(hangout.place)
                    .font(.kithSecondary)
                    .foregroundStyle(secondary)
                    .kithCapCentered(15, relativeTo: .subheadline)
            }
        }
        .lineLimit(1)
        // Read as one line, unless the name is a button of its own.
        .accessibilityElement(children: hangout.placeName == nil ? .combine : .contain)
    }

    // MARK: - Naming a place

    /// First a question, then — if you say yes — a name field with quick tags.
    private var namingCard: some View {
        VStack(spacing: 8) {
            if naming {
                nameEditor
            } else {
                namePrompt
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: 317)
        .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var namePrompt: some View {
        Group {
            VStack(spacing: 4) {
                Text("You’ve been here \(hangout.visitsThisMonth) times in the last month.")
                    .font(.kithSecondary)
                Text("Name this new location?")
                    .font(.kithCardTitle)
            }
            .foregroundStyle(secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                promptButton("PromptDismiss", label: "Not now") {
                    hangout.namingDismissed = true
                }
                promptButton("PromptConfirm", label: "Name this place") {
                    draftName = ""
                    draftTags = []
                    addingTag = false
                    naming = true
                    nameFocused = true
                }
            }
            // The 58pt targets overhang the 42pt marks; keep that out of the card's padding.
            .padding(.vertical, -8)
        }
    }

    /// A 30pt mark from the comp with a 44pt target around it.
    private func promptButton(_ asset: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .frame(width: 42, height: 42)
                .frame(width: 58, height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, -8)
        .accessibilityLabel(label)
    }

    private var nameEditor: some View {
        // The name, the tags and Save sit a row gap apart; the tags
        // themselves sit closer.
        VStack(spacing: Self.rowGap) {
            TextField("Name", text: $draftName)
                .font(.kithSecondary)
                .foregroundStyle(ink)
                .tint(ink)
                .focused($nameFocused)
                .submitLabel(.done)
                // Done puts the keyboard away and nothing else: saving from
                // here would skip the tags before you'd picked any.
                .onSubmit { nameFocused = false }
                .accessibilityLabel("Place name")
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(KithTheme.thumbnail(isDark), in: Capsule())

            tagGrid

            HStack(spacing: 10) {
                // Renaming can be called off; Bloom's first offer has Not Now.
                if hangout.placeName != nil {
                    Button(action: cancelNaming) {
                        Text("Cancel")
                            .font(.kithCardTitle)
                            .kithCapCentered(15, relativeTo: .subheadline)
                            .foregroundStyle(ink)
                            .padding(.horizontal, 20)
                            .frame(height: 36)
                            .overlay(Capsule().strokeBorder(secondary, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                Button(action: savePlace) {
                    Text("Save")
                        .font(.kithCardTitle)
                        .kithCapCentered(15, relativeTo: .subheadline)
                        .foregroundStyle(fill)
                        .padding(.horizontal, 20)
                        .frame(height: 36)
                        .background(ink, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draftName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            }
            // The 44pt target overhangs the 36pt pill by 4pt each way; take
            // that back so the gap above is the row gap, and keep it out of
            // the card's padding below.
            .padding(.top, -4)
            .padding(.bottom, -8)
        }
    }

    /// The tags in three even columns, edge to edge with the name above,
    /// then a + that opens into a field for a tag of your own. Tags you make
    /// stay on offer for every place after.
    private var tagGrid: some View {
        let tags = Self.tagIdeas + store.customPlaceTags.filter { !Self.tagIdeas.contains($0) }

        return VStack(spacing: Self.tagRowGap) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.tagGap), count: 3), spacing: Self.tagRowGap) {
                ForEach(tags, id: \.self) { tag in
                    tagPill(tag)
                }
                if !addingTag {
                    Button(action: beginNewTag) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(KithTheme.canvas(isDark), in: Capsule())
                            .matchedGeometryEffect(id: "newTag", in: tagMorph)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .padding(.vertical, -5)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("New Tag")
                }
            }

            if addingTag {
                TextField("New tag", text: $draftTag)
                    .font(.kithSecondary)
                    .foregroundStyle(ink)
                    .tint(ink)
                    .focused($tagFocused)
                    .submitLabel(.done)
                    .onSubmit(addTag)
                    .accessibilityLabel("New tag")
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(KithTheme.canvas(isDark), in: Capsule())
                    .matchedGeometryEffect(id: "newTag", in: tagMorph)
            }
        }
        .onChange(of: tagFocused) { _, focused in
            // Tapping away keeps what you typed, or folds back to the +.
            if !focused, addingTag { addTag() }
        }
    }

    private func tagPill(_ tag: String) -> some View {
        let on = draftTags.contains(tag)
        return Button {
            if on { draftTags.removeAll { $0 == tag } } else { draftTags.append(tag) }
        } label: {
            Text(tag)
                .font(.kithSecondary)
                .kithCapCentered(15, relativeTo: .subheadline)
                .foregroundStyle(on ? ink : secondary)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(on ? KithTheme.feelingSelected : KithTheme.canvas(isDark), in: Capsule())
                // A 44pt target without spreading the rows apart.
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .padding(.vertical, -5)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Tag \(tag)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func beginNewTag() {
        draftTag = ""
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) { addingTag = true }
        tagFocused = true
    }

    /// Your own tag joins the list, already picked, and the field folds back
    /// into the +.
    private func addTag() {
        let tag = String(draftTag.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        if !tag.isEmpty {
            if !Self.tagIdeas.contains(tag), !store.customPlaceTags.contains(tag) {
                store.customPlaceTags.append(tag)
            }
            if !draftTags.contains(tag) { draftTags.append(tag) }
        }
        draftTag = ""
        tagFocused = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82)) { addingTag = false }
    }

    // MARK: - Photos

    /// The comp's bento: a tall photo, a square beside it, and under that a
    /// small one next to the add tile. Anything past three runs on in rows.
    /// The same grid the friend's page uses, so a hangout's photos and the
    /// whole set read as one thing. Adding closes the grid.
    private var photosSection: some View {
        let side = (screenWidth - 40 - 20) / 3

        return VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: 10), count: 3), spacing: 10) {
                ForEach(Array(hangout.photos.enumerated()), id: \.offset) { offset, photo in
                    Button { viewingPhoto = offset } label: {
                        photoImage(photo)
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Photo \(offset + 1) of \(hangout.photos.count)")
                    .accessibilityHint("Opens it full size")
                }

                addTile(side: side)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func photoImage(_ photo: MeetupPhoto) -> some View {
        switch photo {
        case let .asset(name):
            Image(name).resizable().scaledToFill()
        case let .picked(_, image):
            Image(uiImage: image).resizable().scaledToFill()
        }
    }

    private func addTile(side: CGFloat) -> some View {
        Button { choosingPhoto = true } label: {
            Text("+")
                .font(KithType.font(.w90, 33, .title))
                .foregroundStyle(ink)
                .frame(width: side, height: side)
                .background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Add Photos")
    }

    // MARK: - Reflection

    /// Comp 69:869: how it felt as tags you can change here, then your notes.
    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            (Text("Reflection").font(.kithSectionTitle).foregroundStyle(ink)
                + Text(" (only you can see this)").font(.kithRowDetail).foregroundStyle(secondary))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 5) {
                Text("Our time together felt:")
                    .font(.kithRowDetail)
                    .foregroundStyle(secondary)

                FlowLayout(spacing: 6, lineSpacing: -4) {
                    ForEach(Feeling.allCases) { feeling in
                        let on = hangout.feelings.contains(feeling)
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                                if on { hangout.feelings.remove(feeling) } else { hangout.feelings.insert(feeling) }
                            }
                        } label: {
                            FeelingTag(
                                feeling.rawValue,
                                fill: on ? feeling.pillFill : KithTheme.uiFill(isDark),
                                text: on ? nil : secondary,
                                large: true
                            )
                            // 34pt pills with the row gap, so each target reaches 44pt.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(.leading, -3)
                .sensoryFeedback(.selection, trigger: hangout.feelings)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Notes")
                    .font(.kithRowDetail)
                    .foregroundStyle(secondary)

                ReflectionField(text: $hangout.reflection, minHeight: 94, fill: KithTheme.uiFill(isDark), cornerRadius: 6)
            }
        }
    }

    // MARK: - Details

    /// What the event was, when, and where. The comp doesn't draw an editor, so
    /// this borrows the page's own idioms: capsule fields and the ink pill.
    private var detailsEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Details")
                .font(.kithHeading)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            detailField("Activity", text: $draftActivity, prompt: "Coffee")
            detailField("Time", text: $draftTime, prompt: "9 AM")
            detailField("Place", text: $draftPlace, prompt: "Eleventh House, Lafayette")

            Button(action: saveDetails) {
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
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        // Clear of the drawer handle, so the title doesn't sit right under it.
        .padding(.top, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KithTheme.canvas(isDark).ignoresSafeArea())
    }

    private func detailField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.kithCaption)
                .foregroundStyle(secondary)

            TextField(prompt, text: text)
                .font(.kithBody)
                .foregroundStyle(ink)
                .tint(ink)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(fill, in: Capsule())
                .accessibilityLabel(label)
        }
    }

    /// "Coffee with Manitej" -> "Coffee". The name is rebuilt on save, so only
    /// the activity is yours to type.
    private var activity: String {
        hangout.title.components(separatedBy: " with ").first ?? hangout.title
    }

    private func beginEditingDetails() {
        draftActivity = activity
        draftTime = hangout.startTime
        draftPlace = hangout.place
        editingDetails = true
    }

    private func saveDetails() {
        let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let newActivity = trimmed(draftActivity)
        let newTime = trimmed(draftTime)
        let newPlace = trimmed(draftPlace)

        if !newActivity.isEmpty {
            hangout.title = "\(newActivity) with \(hangout.contact.firstName)"
        }
        if !newTime.isEmpty { hangout.startTime = newTime }
        if !newPlace.isEmpty {
            hangout.place = newPlace
            // `detail` reads "Monday · 2 hours · Eleventh House": its last
            // segment is the place's short name, so keep the two in step.
            var parts = hangout.detail.components(separatedBy: " · ")
            if !parts.isEmpty {
                parts[parts.count - 1] = newPlace.components(separatedBy: ",").first.map(trimmed) ?? newPlace
                hangout.detail = parts.joined(separator: " · ")
            }
        }
        editingDetails = false
    }

    // MARK: - Actions

    /// Opens the naming card on the name you gave the place, tags and all.
    private func beginRenaming() {
        draftName = hangout.placeName ?? ""
        draftTags = hangout.placeTags
        addingTag = false
        naming = true
        nameFocused = true
    }

    private func cancelNaming() {
        nameFocused = false
        tagFocused = false
        addingTag = false
        naming = false
    }

    private func savePlace() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if addingTag { addTag() }
        nameFocused = false
        store.name(place: hangout.place, as: name, tags: draftTags)
        hangout.placeName = name
        hangout.placeTags = draftTags
        naming = false
        savedPlace += 1
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        defer { pickedPhoto = nil }
        // Four is all the bento holds for now.
        guard hangout.photos.count < 4 else { return }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else { return }
        hangout.photos.append(.picked(UUID(), image))
    }
}

// MARK: - Shared pieces

/// Photos full size, one at a time: swipe across for the next; tap anywhere
/// outside the photo, or the cross, to put them away. No swipe-to-close, so a
/// swipe across that drifts downward never throws the carousel away.
struct PhotoCarousel: View {
    let photos: [MeetupPhoto]
    @State var index: Int
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                    ZStack {
                        // The empty space around the photo closes it.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onClose)

                        photo.image
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 12)
                            // Taps on the photo itself do nothing.
                            .onTapGesture {}
                            .accessibilityLabel("Photo \(offset + 1) of \(photos.count)")
                    }
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))

            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(.white.opacity(0.16), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Close")

                Spacer()

                Text("\(index + 1) of \(photos.count)")
                    .font(.kithCaption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
        }
        .statusBarHidden(true)
        .accessibilityAction(.escape, onClose)
    }
}

/// The feelings as chips you can pick any number of; green when picked.
struct FeelingChips: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selected: Set<Feeling>
    /// Once something's picked, the other feelings step aside; unpick it and
    /// they come back.
    var showsOnlySelected = false

    private var shown: [Feeling] {
        guard showsOnlySelected, !selected.isEmpty else { return Feeling.allCases }
        return Feeling.allCases.filter(selected.contains)
    }

    var body: some View {
        let isDark = colorScheme == .dark

        FlowLayout(spacing: 5, lineSpacing: 5) {
            ForEach(shown) { feeling in
                let on = selected.contains(feeling)
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85)) {
                        if on { selected.remove(feeling) } else { selected.insert(feeling) }
                    }
                } label: {
                    Text(feeling.rawValue)
                        .font(.kithCaptionStrong)
                        .kithCapCentered(15, relativeTo: .footnote)
                        // Quiet until it's picked: an unchosen feeling is an
                        // option, not an answer. Picked, it goes back to ink so
                        // it still reads on its colour.
                        .foregroundStyle(on ? KithTheme.ink(isDark) : KithTheme.secondary(isDark))
                        .padding(.horizontal, 11.7)
                        .padding(.vertical, 7.8)
                        .background(on ? feeling.pillFill : KithTheme.canvas(isDark), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        // A capsule's round end reads as inset, so the row hangs 3pt past the
        // text edge above it to look lined up.
        .padding(.leading, -3)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// A few lines of your own words, with the comp's prompt as a placeholder.
struct ReflectionField: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var minHeight: CGFloat
    var fill: Color
    var cornerRadius: CGFloat = 12

    var body: some View {
        let isDark = colorScheme == .dark

        KithTextArea(
            text: $text,
            placeholder: "Add a few words about what stood out…",
            textColor: UIColor(KithTheme.ink(isDark)),
            placeholderColor: UIColor(KithTheme.secondary(isDark)),
            minHeight: minHeight - 24
        )
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel("Reflection")
    }
}

/// A growing multi-line text field in AUTHENTIC Sans. SwiftUI's own draws its
/// placeholder a little off from where typing starts, and the font's tall line
/// box drops the cursor below the letters; this draws the placeholder at the
/// typing position and trims the cursor to cap height.
struct KithTextArea: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var textColor: UIColor
    var placeholderColor: UIColor
    var minHeight: CGFloat

    func makeUIView(context: Context) -> CapCaretTextView {
        let view = CapCaretTextView()
        view.font = Self.font
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.delegate = context.coordinator
        view.placeholder.text = placeholder
        view.placeholder.font = Self.font
        view.placeholder.adjustsFontForContentSizeCategory = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: CapCaretTextView, context: Context) {
        if view.text != text { view.text = text }
        view.textColor = textColor
        view.tintColor = textColor
        view.placeholder.textColor = placeholderColor
        view.placeholder.isHidden = !text.isEmpty
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CapCaretTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(fitted.height, minHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// Kith/Typography/Caption, scaled with Dynamic Type like the rest of the app.
    /// The same size as the "Notes" label above it: 15, Subheadline.
    private static var font: UIFont {
        let base = UIFont(name: KithType.Weight.w90.rawValue, size: 15) ?? .systemFont(ofSize: 15)
        return UIFontMetrics(forTextStyle: .subheadline).scaledFont(for: base)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) { _text = text }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            (textView as? CapCaretTextView)?.placeholder.isHidden = !textView.text.isEmpty
        }
    }
}

final class CapCaretTextView: UITextView {
    let placeholder = UILabel()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholder.numberOfLines = 0
        addSubview(placeholder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Exactly where the first typed character goes.
        let inset = textContainerInset
        let width = bounds.width - inset.left - inset.right
        let height = placeholder.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        placeholder.frame = CGRect(x: inset.left, y: inset.top, width: width, height: height)
    }

    /// From just above the capitals to a little below the baseline, the span
    /// the letters actually cover, instead of the font's whole line box.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        guard let font else { return rect }
        let baseline = rect.minY + font.ascender
        let top = baseline - font.capHeight - font.pointSize * 0.08
        let bottom = baseline - font.descender * 0.45
        rect.origin.y = top
        rect.size.height = bottom - top
        return rect
    }
}

/// Lays chips out left to right, wrapping onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row(y: row.y + row.height + lineSpacing)
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
