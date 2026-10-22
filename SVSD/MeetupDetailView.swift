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
    @FocusState private var nameFocused: Bool

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var fill: Color { KithTheme.uiFill(isDark) }
    private var scale: CGFloat { screenWidth / 393 }

    /// Ways people tag a place they keep returning to.
    private static let tagIdeas = ["study", "outside", "coffee", "cozy"]

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

                    if offersToName && namingArrived {
                        namingCard
                            .padding(.top, 13)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)).combined(with: .offset(y: 6)))
                    }

                    VStack(alignment: .leading, spacing: 15) {
                        photosSection
                        Rectangle()
                            .fill(KithTheme.suggestionCard(isDark))
                            .frame(height: 2)
                        reflectionSection
                    }
                    .padding(.top, 26 * scale)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)

            KithBackButton(action: onBack)
                .padding(.leading, 12.25)
                .padding(.top, 29 * scale)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: offersToName)
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: naming)
        .sheet(isPresented: $editingDetails) { detailsEditor }
        .photosPicker(isPresented: $choosingPhoto, selection: $pickedPhoto, matching: .images)
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await addPhoto(item) }
        }
        .sensoryFeedback(.success, trigger: savedPlace)
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
                .frame(width: 16, height: 16)
                .foregroundStyle(secondary)
                .accessibilityHidden(true)

            // Nudged onto the pin's centre: AUTHENTIC Sans sits its letters high.
            if let name = hangout.placeName {
                Text(name)
                    .font(.kithCaptionStrong)
                    .foregroundStyle(ink)
                    .kithCapCentered(13, relativeTo: .footnote)
                Text("· \(hangout.place)")
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
                    .kithCapCentered(13, relativeTo: .footnote)
            } else {
                Text(hangout.place)
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
                    .kithCapCentered(13, relativeTo: .footnote)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .accessibilityElement(children: .combine)
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
            VStack(spacing: 2) {
                Text("You’ve been here \(hangout.visitsThisMonth) times in the last month.")
                    .font(.kithCaption)
                Text("Name this new location?")
                    .font(.kithCaptionStrong)
            }
            .foregroundStyle(secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                promptButton("PromptDismiss", label: "Not now") {
                    hangout.namingDismissed = true
                }
                promptButton("PromptConfirm", label: "Name this place") {
                    draftName = ""
                    draftTags = []
                    naming = true
                    nameFocused = true
                }
            }
            // The 44pt targets overhang the 30pt marks; keep them out of the card's padding.
            .padding(.vertical, -7)
        }
    }

    /// A 30pt mark from the comp with a 44pt target around it.
    private func promptButton(_ asset: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(asset)
                .resizable()
                .frame(width: 30, height: 30)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.horizontal, -7)
        .accessibilityLabel(label)
    }

    private var nameEditor: some View {
        Group {
            HStack(spacing: 6) {
                TextField("Name", text: $draftName)
                    .font(.kithFine)
                    .foregroundStyle(ink)
                    .tint(ink)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit(savePlace)
                    .accessibilityLabel("Place name")
                Image("PencilIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .foregroundStyle(ink)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(width: 200, height: 30)
            .background(KithTheme.thumbnail(isDark), in: Capsule())

            FlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(Self.tagIdeas, id: \.self) { tag in
                    let on = draftTags.contains(tag)
                    Button {
                        if on { draftTags.removeAll { $0 == tag } } else { draftTags.append(tag) }
                    } label: {
                        Text(on ? "✓ \(tag)" : "+ \(tag)")
                            .font(.kithFine)
                            .foregroundStyle(on ? ink : KithTheme.recentMeta)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(on ? KithTheme.feelingSelected : KithTheme.canvas(isDark), in: Capsule())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Tag \(tag)")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .frame(maxWidth: 260)

            Button(action: savePlace) {
                Text("Save")
                    .font(.kithCaption)
                    .kithCapCentered(13, relativeTo: .footnote)
                    .foregroundStyle(fill)
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .background(ink, in: Capsule())
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(draftName.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(draftName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
            .padding(.vertical, -8)
        }
    }

    // MARK: - Photos

    /// The comp's bento: a tall photo, a square beside it, and under that a
    /// small one next to the add tile. Anything past three runs on in rows.
    private var photosSection: some View {
        let width = screenWidth - 40
        let unit = (width - 8) / 2
        let small = (unit - 8) / 2
        let photos = hangout.photos

        return VStack(alignment: .leading, spacing: 12) {
            Text("Photos")
                .font(.kithBodyStrong)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    photoTile(at: 0, width: unit, height: unit + 8 + small)
                    VStack(spacing: 8) {
                        photoTile(at: 1, width: unit, height: unit)
                        HStack(spacing: 8) {
                            photoTile(at: 2, width: small, height: small)
                            // The bento holds four for now. The plus closes it
                            // until the fourth photo arrives and takes its slot.
                            if photos.count > 3 {
                                photoTile(at: 3, width: small, height: small)
                            } else {
                                addTile(side: small)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func photoTile(at index: Int, width: CGFloat, height: CGFloat) -> some View {
        if hangout.photos.indices.contains(index) {
            photoImage(hangout.photos[index])
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityLabel("Photo \(index + 1)")
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
                .frame(width: width, height: height)
                .accessibilityHidden(true)
        }
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
                .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Add Photos")
    }

    // MARK: - Reflection

    /// Comp 69:869: how it felt as tags you can change here, then your notes.
    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Reflection")
                    .font(KithType.font(.w130, 14, .subheadline))
                    .foregroundStyle(ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Only you can see this.")
                    .font(.kithFine)
                    .foregroundStyle(secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Our time together felt:")
                    .font(.kithFine)
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
                                fill: on ? KithTheme.feelingSelected : KithTheme.uiFill(isDark),
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
                .sensoryFeedback(.selection, trigger: hangout.feelings)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Notes")
                    .font(.kithFine)
                    .foregroundStyle(secondary)

                ReflectionField(text: $hangout.reflection, minHeight: 94, fill: KithTheme.suggestionCard(isDark), cornerRadius: 6)
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
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KithTheme.canvas(isDark).ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
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

    private func savePlace() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        nameFocused = false
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

/// Photos full size, one at a time: swipe across for the next, swipe down or
/// tap the cross to put them away.
struct PhotoCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let photos: [MeetupPhoto]
    @State var index: Int
    var onClose: () -> Void

    @State private var drop: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .opacity(1 - min(0.6, abs(drop) / 400))
                .ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.offset) { offset, photo in
                    photo.image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 12)
                        .tag(offset)
                        .accessibilityLabel("Photo \(offset + 1) of \(photos.count)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
            .offset(y: drop)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        drop = value.translation.height
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 120 || abs(value.predictedEndTranslation.height) > 300 {
                            onClose()
                        } else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) { drop = 0 }
                        }
                    }
            )

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
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .opacity(1 - min(1, abs(drop) / 160))
        }
        .statusBarHidden(true)
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
                        .kithCapCentered(13, relativeTo: .footnote)
                        .foregroundStyle(KithTheme.ink(isDark))
                        .padding(.horizontal, 11.7)
                        .padding(.vertical, 7.8)
                        .background(on ? KithTheme.feelingSelected : KithTheme.canvas(isDark), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(on ? .isSelected : [])
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
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
            placeholderColor: UIColor(KithTheme.recentMeta),
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
    private static var font: UIFont {
        let base = UIFont(name: KithType.Weight.w90.rawValue, size: 13) ?? .systemFont(ofSize: 13)
        return UIFontMetrics(forTextStyle: .footnote).scaledFont(for: base)
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
