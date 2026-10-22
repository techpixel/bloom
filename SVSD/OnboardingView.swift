import ContactsUI
import PhotosUI
import SwiftUI
import UIKit

/// Screen order follows the comps; code verification and the friend list use demo data.
enum OnboardingStep: Int, CaseIterable, Equatable {
    case welcome
    case phone
    case name
    case profilePhoto
    case celebrate
    case contacts
    case location
    case photos
    case calendar
    case friends

    var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
}

#if DEBUG
/// `-OnboardStep <n>` jumps straight to a screen, for screenshots.
enum DebugJump {
    static let step = Int(UserDefaults.standard.string(forKey: "OnboardStep") ?? "") ?? 0
    static let showCode = UserDefaults.standard.bool(forKey: "OnboardCode")
    /// Forces a fractional blob stage so a morph can be inspected mid-flight.
    static let blobStage = UserDefaults.standard.string(forKey: "OnboardBlobStage").flatMap(Double.init)
}
#endif

/// The number screen holds two prompts in the same spot. Asking for the code is
/// part of taking the number, not a new page, so it swaps in place.
private enum PhoneStage {
    case number
    case code
}

struct OnboardingView: View {
    /// Called once the flow is done, so the app can move on to scheduling.
    var onComplete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: OnboardingStep
    @State private var goingForward = true
    @State private var phoneStage: PhoneStage

    @State private var didStart = false
    @State private var name: String
    /// What the rest of the app calls you, once you've said it here.
    @AppStorage("profile.name") private var savedName = DemoCast.placeholderName
    @State private var phone: String
    @State private var code = ""
    @State private var search = ""
    @State private var addedFriends: Set<String> = []

    @State private var demoPermissions: Set<OnboardingStep> = []
    /// Permission pages whose prompt you've answered, either way. "Next"
    /// stays greyed until then.
    @State private var answeredPermissions: Set<OnboardingStep> = []
    /// Shared with Profile, so a calendar connected here shows there too.
    @AppStorage("calendar.google") private var googleCalendars = 0
    @AppStorage("calendar.apple") private var appleCalendarConnected = false
    /// Whether you've answered Apple's calendar prompt here, yes or no.
    @State private var appleCalendarAsked = false
    @State private var connectingGoogle = false
    /// The stand-in iOS alert, so the prompt shows on every run rather than
    /// only the first install.
    @State private var permissionAlert: SystemAlert?

    /// The intro: the seed sits beside "bloom", the word pulls away to the
    /// right, and the seed grows into the welcome logo.
    /// The photo you pick for your profile, saved where Profile reads it.
    @State private var profilePhoto: UIImage? = ProfilePhotoStore.load()
    @State private var pickedProfileItem: PhotosPickerItem?
    @State private var choosingProfilePhoto = false
    @State private var choosingContactCard = false

    @State private var logoSettled = false
    @State private var wordmarkOpacity = 1.0
    @State private var wordmarkOffset: CGFloat = 0
    @State private var wordmarkWidth: CGFloat = 104
    @State private var taglineVisible = false
    @State private var controlsVisible = false

    @FocusState private var fieldFocused: Bool

    /// `start` lets the dev menu drop straight onto a screen; the launch-argument
    /// defaults keep the screenshot flags working.
    init(onComplete: (() -> Void)? = nil, start: OnboardingStep? = nil, startOnCode: Bool = false) {
        self.onComplete = onComplete

        #if DEBUG
        let first = start ?? OnboardingStep(rawValue: DebugJump.step) ?? .welcome
        let onCode = startOnCode || DebugJump.showCode
        #else
        let first = start ?? .welcome
        let onCode = startOnCode
        #endif

        _step = State(initialValue: first)
        _phoneStage = State(initialValue: onCode ? .code : .number)
        // Later screens need something in these to look right.
        _name = State(initialValue: first.rawValue > OnboardingStep.name.rawValue ? "Amber" : "")
        _phone = State(
            initialValue: first.rawValue > OnboardingStep.phone.rawValue || onCode
                ? "(765) 555-0142" : ""
        )
    }
    @State private var keyboardHeight: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    /// The page sliding in beside the current one, during a drag or a turn.
    @State private var incoming: OnboardingStep?
    @State private var pageWidth: CGFloat = 393
    /// The blob trails a drag at a slower rate, so it reads as being behind the page.
    @State private var blobDrift: CGFloat = 0

    private let friends = Friend.sample

    private var isDark: Bool { colorScheme == .dark }
    private var surface: Color { KithTheme.canvas(isDark) }
    private var mark: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var hasName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasPhone: Bool { phone.filter(\.isNumber).count == PhoneEntry.digitLimit }
    private var hasCode: Bool { code.filter(\.isNumber).count == PhoneEntry.codeLength }

    // The comps are iPhone 16 frames: 393 x 852.
    private let designWidth: CGFloat = 393
    private let designHeight: CGFloat = 852

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let logoWidth = min(size.width * 0.382, 150)

            ZStack {
                surface

                // Page backdrops travel with their page when it turns.
                if step == .welcome || incoming == .welcome {
                    WatercolorBloom()
                        .frame(width: size.width, height: size.height)
                        .offset(x: pageOffset(for: .welcome, width: size.width))
                        // The paint comes in as the seed settles.
                        .opacity(logoSettled ? 1 : 0)
                        .animation(.easeOut(duration: 1.4), value: logoSettled)
                }

                if step == .friends || incoming == .friends {
                    decorativeBand(size: size)
                        .offset(x: pageOffset(for: .friends, width: size.width))
                }

                // Outside the page switch on purpose: the blob is one continuous
                // object that morphs as you move, not a picture per screen.
                blobLayer(size: size)

                pages(size: size, logoWidth: logoWidth)
                    .offset(y: -keyboardLift(in: size))

                if step != .welcome || controlsVisible {
                    pageControl(size: size)
                }

                if step != .welcome {
                    skipButton(size: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(pageDrag)
            .onAppear { pageWidth = size.width }
            .onChange(of: size.width) { _, width in pageWidth = width }
            .overlay {
                if let alert = permissionAlert {
                    SystemAlertView(alert: alert) { choice in
                        resolvePermission(granted: choice.grants)
                    }
                }
            }
            .animation(stepAnimation, value: step)
            .animation(stepAnimation, value: hasPhone)
            .animation(stepAnimation, value: hasName)
        }
        .background(surface)
        // The keyboard's area too: the page does its own (small) lift, so
        // iOS shrinking the layout as well sent everything to the top.
        .ignoresSafeArea(.all, edges: .all)
        .statusBarHidden(true)
        .onAppear(perform: beginEntrance)
        // The typing pages bring their keyboard up, since its "Next" key is
        // the way forward.
        .task(id: step) {
            guard step == .phone || step == .name else { return }
            try? await Task.sleep(for: .milliseconds(450))
            if step == .phone || step == .name { fieldFocused = true }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        ) { note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
                  let screen = UIApplication.shared.connectedScenes
                      .compactMap({ ($0 as? UIWindowScene)?.screen }).first
            else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = max(0, screen.bounds.height - frame.minY)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
        }
    }

    /// How far the page rises to keep the field you're typing in clear of the
    /// keyboard. The keyboard's "Next" key is how you move on from these
    /// pages, so there's no button to lift above it.
    private func keyboardLift(in size: CGSize) -> CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        let fieldBottom = size.height * 0.695 + 44
        return max(0, fieldBottom + 24 - (size.height - keyboardHeight))
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.86)
    }

    // MARK: - Swiping between pages

    /// Lower priority than the buttons and fields it sits under, so a tap still
    /// reaches them; only a real horizontal drag turns the page. The next page
    /// rides in beside the current one, the way a real page would.
    private var pageDrag: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let travel = value.translation.width
                fieldFocused = false
                if let target = travel < 0 ? forwardPage : backPage {
                    incoming = target
                    dragOffset = travel
                } else {
                    // Resist rather than refuse, so a blocked edge still feels alive.
                    incoming = nil
                    dragOffset = travel * 0.22
                }
                blobDrift = dragOffset * 0.45
            }
            .onEnded { value in
                let travel = value.translation.width
                let flung = value.predictedEndTranslation.width
                let horizontal = abs(travel) > abs(value.translation.height)

                if horizontal, let target = incoming, abs(travel) > 70 || abs(flung) > pageWidth / 2 {
                    turnPage(to: target)
                    return
                }

                withAnimation(stepAnimation) {
                    dragOffset = 0
                    blobDrift = 0
                } completion: {
                    incoming = nil
                }

                // The code prompt swaps in place on the same page, so it isn't a turn.
                guard horizontal, abs(travel) > 70, step == .phone else { return }
                if travel < 0, phoneStage == .number, hasPhone {
                    showCodePrompt()
                } else if travel > 0, phoneStage == .code {
                    goBack()
                }
            }
    }

    /// The page a forward swipe would turn to, if it's allowed.
    private var forwardPage: OnboardingStep? {
        guard canGoForward, !(step == .phone && phoneStage == .number) else { return nil }
        return step.next
    }

    /// The page a back swipe would turn to, if there is one.
    private var backPage: OnboardingStep? {
        guard canGoBack, !(step == .phone && phoneStage == .code) else { return nil }
        return OnboardingStep(rawValue: step.rawValue - 1)
    }

    /// Slides the current page off and `target` on, then makes it the page.
    /// Buttons go through here too, so every move between pages is a turn.
    private func turnPage(to target: OnboardingStep) {
        fieldFocused = false
        goingForward = target.rawValue > step.rawValue
        guard !reduceMotion, pageWidth > 0 else {
            step = target
            incoming = nil
            dragOffset = 0
            blobDrift = 0
            return
        }

        incoming = target
        withAnimation(.spring(response: 0.42, dampingFraction: 0.92)) {
            dragOffset = goingForward ? -pageWidth : pageWidth
        } completion: {
            // The incoming page is already where the current one sits, so the
            // swap itself doesn't move anything; the blob morphs on `step`.
            step = target
            incoming = nil
            dragOffset = 0
            withAnimation(stepAnimation) { blobDrift = 0 }
        }
    }

    private var canGoBack: Bool {
        step != .welcome
    }

    /// Forward by swipe is gated exactly as the button is, so a swipe can never
    /// skip something the button would not let you skip.
    private var canGoForward: Bool {
        switch step {
        case .welcome: return controlsVisible
        case .phone: return phoneStage == .number ? hasPhone : hasCode
        case .name: return hasName
        case .profilePhoto: return profilePhoto != nil
        case .celebrate: return true
        case .contacts, .location, .photos: return answeredPermissions.contains(step)
        case .calendar: return calendarAnswered
        case .friends: return addedFriends.count >= 2
        }
    }

    private func continueFromKeyboard() {
        guard canGoForward else { return }
        goForward()
    }


    private func goForward() {
        if step == .phone, phoneStage == .number {
            showCodePrompt()
        } else {
            advance()
        }
    }

    /// Mirrors the way forward works: the code prompt is a step back to the
    /// number, not a page back — which is also the only way to fix a wrong one.
    private func goBack() {
        if step == .phone, phoneStage == .code {
            fieldFocused = false
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                phoneStage = .number
            }
            return
        }
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        navigate(to: previous)
    }

    private func showCodePrompt() {
        fieldFocused = false
        // Same page: the prompt swaps, the page does not move.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
            phoneStage = .code
        }
        // The keyboard comes back for the code; its "Next" is the way on.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fieldFocused = true }
    }

    // MARK: - Pages

    /// The current page, plus the one turning in beside it. Keyed by step, so
    /// the incoming page is the same view once it becomes the current one.
    private func pages(size: CGSize, logoWidth: CGFloat) -> some View {
        let visible = [step] + (incoming.map { [$0] } ?? [])

        return ZStack {
            ForEach(visible, id: \.self) { candidate in
                page(candidate, size: size, logoWidth: logoWidth)
                    .offset(x: pageOffset(for: candidate, width: size.width))
                    .allowsHitTesting(candidate == step)
            }
        }
    }

    private func pageOffset(for candidate: OnboardingStep, width: CGFloat) -> CGFloat {
        guard candidate != step else { return dragOffset }
        return dragOffset + (candidate.rawValue > step.rawValue ? width : -width)
    }

    @ViewBuilder
    private func page(_ page: OnboardingStep, size: CGSize, logoWidth: CGFloat) -> some View {
        switch page {
        case .welcome:
            welcomeScreen(size: size, logoWidth: logoWidth)
        case .phone:
            phoneScreen(size: size)
        case .name:
            nameScreen(size: size)
        case .profilePhoto:
            profilePhotoScreen(size: size)
        case .celebrate:
            celebrateScreen(size: size)
        case .contacts, .location, .photos:
            permissionScreen(for: page, size: size)
        case .calendar:
            calendarScreen(size: size)
        case .friends:
            friendsScreen(size: size)
        }
    }

    // MARK: - The blob

    /// Stage, size and position all read off `step`, so one animation carries the
    /// blob from screen to screen.
    private func blobLayer(size: CGSize) -> some View {
        let scale = size.width / designWidth
        let onFriends = step == .friends
        // On the friends screen the blob lands exactly where the comp draws its
        // mint star: off to the left, smaller, and rotated.
        let side: CGFloat = onFriends ? 128.78 * scale : 218
        let centerX = onFriends ? 150.4 * scale : size.width / 2
        let centerY = size.height * (onFriends ? 138.5 / designHeight : 0.307)

        return KithBlob(
            stage: blobStage,
            fill: KithTheme.availability,
            stroke: mark,
            fillAmount: blobFillAmount,
            // Every character typed ripples the blob.
            pulse: phone.count + code.count + name.count
        )
        .frame(width: side, height: onFriends ? side : side * 221 / 218)
        .rotationEffect(.degrees(onFriends ? 48.48 : 0))
        .position(x: centerX, y: centerY)
        // Give way to the keyboard rather than collide with the risen prompt.
        .scaleEffect(keyboardHeight > 0 ? 0.68 : 1)
        // Travels with the page, just slower, so a swipe reads as turning a
        // page rather than sliding content past a pinned ornament. Leaving
        // the welcome screen it doesn't travel: the seed pops up where it sits.
        .offset(x: leavingWelcome ? 0 : blobDrift, y: -keyboardLift(in: size) * 0.45)
        .scaleEffect(step == .welcome ? 0.2 : 1)
        // The photo step has your face where the blob would be.
        .opacity(step == .welcome || step == .profilePhoto ? 0 : 1)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.62), value: step == .welcome)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.8), value: blobStage)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// Between the welcome screen and the first step, either way.
    private var leavingWelcome: Bool {
        step == .welcome || incoming == .welcome
    }

    /// Typing your number pulls the seed into the star — the shape answers you
    /// before the next screen does.
    private var blobStage: CGFloat {
        #if DEBUG
        if let forced = DebugJump.blobStage { return CGFloat(forced) }
        #endif
        // The page being turned to, so the shape leads the turn instead of
        // waiting for the swap at the end of it.
        switch incoming ?? step {
        case .welcome, .phone:
            return hasPhone || phoneStage == .code ? BlobStage.star.rawValue : BlobStage.circle.rawValue
        case .name, .profilePhoto:
            return BlobStage.star.rawValue
        case .celebrate:
            return BlobStage.starFilled.rawValue
        case .contacts:
            return BlobStage.person.rawValue
        case .location:
            return BlobStage.locationPin.rawValue
        case .photos:
            return BlobStage.photos.rawValue
        case .calendar:
            return BlobStage.calendar.rawValue
        case .friends:
            return BlobStage.starSmall.rawValue
        }
    }

    /// And entering your name is what fills it in.
    private var blobFillAmount: CGFloat {
        switch step {
        case .welcome, .phone:
            return 0
        case .name:
            return hasName ? 1 : 0
        default:
            return 1
        }
    }

    // MARK: - Welcome

    private var logoMark: some View {
        Image("BloomMark")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(mark)
    }

    private func welcomeScreen(size: CGSize, logoWidth: CGFloat) -> some View {
        let logoHeight = logoWidth * 280.535 / 317
        // In the lockup the seed is the word's height, just left of it.
        let lockupHeight: CGFloat = 44
        let lockupScale = lockupHeight / logoHeight
        let gap: CGFloat = 10
        let lockupWidth = logoWidth * lockupScale + gap + wordmarkWidth
        let lockupLeft = size.width / 2 - lockupWidth / 2

        return ZStack {
            logoMark
                .frame(width: logoWidth, height: logoHeight)
                .scaleEffect(logoSettled ? 1 : lockupScale)
                .position(
                    x: logoSettled ? size.width / 2 : lockupLeft + logoWidth * lockupScale / 2,
                    y: logoSettled ? size.height * 0.475 : size.height / 2
                )
                .accessibilityLabel("Bloom")

            Text("Nothing blooms by accident.")
                .font(.kithTagline)
                .foregroundStyle(mark)
                .position(x: size.width / 2, y: size.height * 0.585)
                .opacity(taglineVisible ? 1 : 0)
                .blur(radius: taglineVisible ? 0 : 4)
                .offset(y: taglineVisible ? 0 : 12)

            pillButton("Let’s Get Started", size: size) { advance() }
                .opacity(controlsVisible ? 1 : 0)
                .blur(radius: controlsVisible ? 0 : 4)
                .offset(y: controlsVisible ? 0 : 12)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)

            Text("bloom")
                .font(.bloomWordmark)
                .foregroundStyle(mark)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { wordmarkWidth = $0 }
                .blur(radius: wordmarkOpacity < 1 ? 3 : 0)
                .opacity(wordmarkOpacity)
                .offset(x: wordmarkOffset)
                .position(x: lockupLeft + logoWidth * lockupScale + gap + wordmarkWidth / 2, y: size.height / 2)
                .accessibilityHidden(true)

            #if DEBUG
            Button(action: replayEntrance) {
                Label("Replay", systemImage: "arrow.counterclockwise")
                    .font(.kithCaptionStrong)
                    .foregroundStyle(mark)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(surface.opacity(0.92), in: Capsule())
                    .overlay(Capsule().stroke(mark.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .position(x: size.width - 52, y: size.height * 0.065)
            .opacity(controlsVisible ? 1 : 0)
            .allowsHitTesting(controlsVisible)
            .accessibilityHidden(!controlsVisible)
            .accessibilityLabel("Replay intro animation")
            #endif
        }
    }

    // MARK: - Number, then the code

    private func phoneScreen(size: CGSize) -> some View {
        ZStack {
            ZStack {
                switch phoneStage {
                case .number:
                    promptField(
                        prompt: "We’ll need your number.",
                        text: $phone,
                        label: "Phone number",
                        placeholder: "(765) 555-0142",
                        keyboard: .phonePad,
                        contentType: .telephoneNumber
                    )
                    // Digits only, ten of them, formatted as you type.
                    .onChange(of: phone) { old, new in
                        let formatted = PhoneEntry.formatNumber(new, previous: old)
                        if formatted != new { phone = formatted }
                    }
                    .transition(.opacity)
                case .code:
                    promptField(
                        prompt: "Enter your code.",
                        text: $code,
                        label: "Verification code",
                        placeholder: "6-digit code",
                        keyboard: .numberPad,
                        contentType: .oneTimeCode,
                        caption: "Sent to \(phone)"
                    )
                    // Digits only, six of them.
                    .onChange(of: code) { _, new in
                        let digits = PhoneEntry.code(new)
                        if digits != new { code = digits }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: 269, alignment: .leading)
            .position(x: size.width / 2, y: size.height * 0.695)


        }
    }

    private func nameScreen(size: CGSize) -> some View {
        ZStack {
            promptField(
                prompt: "What’s your name?",
                text: $name,
                label: "Your name",
                keyboard: .default,
                contentType: .givenName
            )
            .frame(width: 269, alignment: .leading)
            .position(x: size.width / 2, y: size.height * 0.695)

        }
    }

    // MARK: - Your photo

    /// After your name, a face for it: friends see it on their dial and in
    /// their recaps. It sits where the blob would be, and becomes the photo
    /// Profile shows.
    private func profilePhotoScreen(size: CGSize) -> some View {
        let side: CGFloat = 190

        return ZStack {
            Button { choosingProfilePhoto = true } label: {
                Group {
                    if let profilePhoto {
                        Image(uiImage: profilePhoto)
                            .resizable()
                            .scaledToFill()
                            .frame(width: side, height: side)
                            .clipShape(Circle())
                            .transition(.scale(scale: 0.85).combined(with: .opacity))
                    } else {
                        Circle()
                            .fill(KithTheme.uiFill(isDark))
                            .overlay(
                                Circle().strokeBorder(secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 6]))
                            )
                            .overlay(
                                Image(systemName: "plus")
                                    .font(.system(size: 34, weight: .light))
                                    .foregroundStyle(mark)
                            )
                            .frame(width: side, height: side)
                    }
                }
                .background {
                    if profilePhoto != nil {
                        Image("ProfileGlow")
                            .resizable()
                            .frame(width: side * 1.37, height: side * 1.33)
                            .rotationEffect(.degrees(90.45))
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(PressableButtonStyle())
            .position(x: size.width / 2, y: size.height * 0.307)
            .accessibilityLabel(profilePhoto == nil ? "Add a Photo" : "Your photo")
            .accessibilityHint("Choose a photo of you")

            VStack(alignment: .leading, spacing: 8) {
                Text("Add a photo of you.")
                    .font(.kithPrompt)
                    .foregroundStyle(mark)
                Text("Friends see it on their dial and in their recaps.")
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // The photo iMessage already shows for you, from your own card.
                Button { choosingContactCard = true } label: {
                    Label("Use My Contact Card", systemImage: "person.crop.circle")
                        .font(.kithCaptionStrong)
                        .foregroundStyle(mark)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint("Pick yourself in Contacts to use that photo")
            }
            .frame(width: 269, alignment: .leading)
            .position(x: size.width / 2, y: size.height * 0.695)

            pillButton(
                profilePhoto == nil ? "Choose a Photo" : "Next",
                size: size,
                style: profilePhoto == nil ? .muted : .solid
            ) {
                if profilePhoto == nil { choosingProfilePhoto = true } else { advance() }
            }
        }
        .photosPicker(isPresented: $choosingProfilePhoto, selection: $pickedProfileItem, matching: .images)
        .sheet(isPresented: $choosingContactCard) {
            ContactCardPicker { image in
                choosingContactCard = false
                guard let image else { return }
                ProfilePhotoStore.save(image)
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
                    profilePhoto = image
                }
            }
            .ignoresSafeArea()
        }
        .onChange(of: pickedProfileItem) { _, item in
            guard let item else { return }
            Task {
                defer { pickedProfileItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                ProfilePhotoStore.save(image)
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
                    profilePhoto = image
                }
            }
        }
    }

    /// A prompt over a filled field — the comps' one input pattern.
    private func promptField(
        prompt: String,
        text: Binding<String>,
        label: String,
        placeholder: String = "",
        keyboard: UIKeyboardType,
        contentType: UITextContentType,
        caption: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prompt)
                .font(.kithPrompt)
                .foregroundStyle(mark)
                .fixedSize(horizontal: false, vertical: true)

            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(secondary))
                .font(.kithBody)
                .foregroundStyle(mark)
                .tint(mark)
                .textFieldStyle(.plain)
                // Number pads have no return key, so digits come on the
                // numbers-and-punctuation keyboard, whose return key is "Next".
                .keyboardType(keyboard == .default ? .default : .numbersAndPunctuation)
                .textContentType(contentType)
                .textInputAutocapitalization(keyboard == .default ? .words : .never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .submitLabel(.next)
                .onSubmit(continueFromKeyboard)
                .padding(.horizontal, 12)
                .frame(height: 38.317)
                .background(
                    KithTheme.uiFill(isDark),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .accessibilityLabel(label)

            if let caption {
                Text(caption)
                    .font(.kithCaption)
                    .foregroundStyle(secondary)
            }
        }
    }

    // MARK: - Celebrate

    private func celebrateScreen(size: CGSize) -> some View {
        ZStack {
            // The blob has just become theirs, so it carries their face.
            YourAvatar(diameter: 128)
                .position(x: size.width / 2, y: size.height * 0.355)
                .transition(.opacity.combined(with: .scale(scale: 0.86)))

            Text("Welcome, \(name.isEmpty ? "friend" : name)!")
                .font(.kithWelcome)
                .foregroundStyle(mark)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: size.width - 48)
                .position(x: size.width / 2, y: size.height * 0.754)

            pillButton("Let’s Go", size: size) { advance() }
        }
    }

    // MARK: - Permissions

    /// Takes its page rather than reading `page`, so the incoming page in a
    /// turn shows its own copy.
    private func permissionScreen(for page: OnboardingStep, size: CGSize) -> some View {
        let copy = permissionCopy(for: page)
        let answered = answeredPermissions.contains(page)

        return ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Allow Access")
                    .font(.kithHeading)
                    .foregroundStyle(mark)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.title)
                        .font(.kithBody)
                        .foregroundStyle(mark)
                    Text(copy.body)
                        .font(.kithCaption)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 293, alignment: .leading)
            }
            .frame(width: 325, alignment: .leading)
            .position(x: size.width / 2, y: size.height * 0.688)
            // The prompt comes up on its own once the page has settled, not
            // while it's still turning in.
            .task(id: step) {
                guard page == step, !answeredPermissions.contains(page), permissionAlert == nil else { return }
                try? await Task.sleep(for: .milliseconds(650))
                guard page == step, !answeredPermissions.contains(page), permissionAlert == nil else { return }
                permissionAlert = .permission(for: page)
            }

            // Greyed until you've answered the prompt.
            pillButton(
                "Next",
                size: size,
                enabled: answered,
                accessibilityHint: answered ? "" : "Answer the \(copy.title.lowercased()) prompt first"
            ) {
                advance()
            }
        }
    }

    /// Either answer unlocks "Next"; you move on yourself. On the calendar page
    /// a "Don’t Allow" still counts as an answer, and Google stays an option.
    private func resolvePermission(granted: Bool) {
        permissionAlert = nil
        if step == .calendar {
            appleCalendarConnected = granted
            appleCalendarAsked = true
            return
        }
        answeredPermissions.insert(step)
        if granted { demoPermissions.insert(step) }
    }

    /// The calendar page has two ways in, so it counts as answered once
    /// either is connected or you've said no to Apple's prompt.
    private var calendarAnswered: Bool {
        googleCalendars > 0 || appleCalendarConnected || appleCalendarAsked
    }

    // MARK: - Calendar

    /// The permission page's layout, with a choice of calendar under the copy.
    /// Either one connects; the pill reads "Skip" until one has.
    private func calendarScreen(size: CGSize) -> some View {
        let copy = permissionCopy(for: .calendar)

        return ZStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Allow Access")
                    .font(.kithHeading)
                    .foregroundStyle(mark)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.title)
                        .font(.kithBody)
                        .foregroundStyle(mark)
                    Text(copy.body)
                        .font(.kithCaption)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 293, alignment: .leading)

                VStack(spacing: 8) {
                    calendarChoice(.google)
                    calendarChoice(.apple)
                }
            }
            .frame(width: 325, alignment: .leading)
            // Higher than the other permission pages: the choices need the room.
            .position(x: size.width / 2, y: size.height * 0.622)

            pillButton(
                "Next",
                size: size,
                enabled: calendarAnswered,
                accessibilityHint: calendarAnswered ? "" : "Choose a calendar first"
            ) {
                advance()
            }
        }
        .sheet(isPresented: $connectingGoogle) {
            GoogleCalendarConnectSheet { count in
                googleCalendars = count
            }
        }
    }

    private func calendarChoice(_ source: CalendarSource) -> some View {
        let connected = source == .google ? googleCalendars > 0 : appleCalendarConnected

        return Button {
            switch source {
            case .google: connectingGoogle = true
            case .apple: permissionAlert = .calendar
            }
        } label: {
            HStack(spacing: 10) {
                Image("SettingsCalendar")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(mark)
                    .frame(width: 32, height: 32)
                    .background(surface, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.kithCardTitle)
                        .foregroundStyle(mark)
                    Text(connected ? source.connectedDetail(calendars: googleCalendars) : source.pitch)
                        .font(.kithCaption)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: connected ? "checkmark.circle.fill" : "chevron.forward")
                    .font(.system(size: connected ? 18 : 13, weight: .semibold))
                    .foregroundStyle(connected ? KithTheme.overlap : secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(KithTheme.uiFill(isDark), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(connected)
        .accessibilityLabel(connected ? "\(source.title), connected" : "Connect \(source.title)")
    }

    private func permissionCopy(for step: OnboardingStep) -> (title: String, body: String) {
        switch step {
        case .calendar:
            return (
                "Calendar",
                "Bloom checks when you’re busy so it can find times you and your friends are both free. This demo doesn’t read your calendar."
            )
        case .contacts:
            return (
                "Contacts",
                "Bloom uses sample contacts to find friends already on the app. This demo doesn’t read or upload your contacts."
            )
        case .location:
            return (
                "Background location",
                "Location updates are scripted for this demo. The app doesn’t collect or send your location."
            )
        default:
            return (
                "Photos",
                "Photos are simulated in this demo. The app doesn’t access your photo library."
            )
        }
    }

    // MARK: - Friends

    private func friendsScreen(size: CGSize) -> some View {
        let matches = friends.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
        let enough = addedFriends.count >= 2
        let scale = size.width / designWidth

        return ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Find your friends")
                        .font(.kithDisplay)
                        .foregroundStyle(mark)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                    Text("Add at least two friends to get started. Search for anyone you know.")
                        .font(.kithSecondary)
                        .foregroundStyle(secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 24) {
                    searchField

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 16) {
                            ForEach(matches) { friend in
                                friendRow(friend)
                            }
                            if matches.isEmpty {
                                Text("No one by that name yet.")
                                    .font(.kithSecondary)
                                    .foregroundStyle(secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(width: 349 * scale, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, size.height * (241.2 / designHeight))
            .padding(.bottom, size.height * (1 - 664 / designHeight))

            pillButton(
                enough ? "continue" : "add 2 friends",
                size: size,
                enabled: enough,
                accessibilityHint: enough ? nil : "Add at least two friends to continue"
            ) {
                finish()
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image("SearchIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(secondary)

            TextField("Search", text: $search)
                .font(.kithBody)
                .foregroundStyle(mark)
                .tint(mark)
                .autocorrectionDisabled()
                .accessibilityLabel("Search friends")
        }
        .padding(.horizontal, 16)
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(KithTheme.uiFill(isDark), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func friendRow(_ friend: Friend) -> some View {
        let added = addedFriends.contains(friend.name)

        return HStack(spacing: 8) {
            friendAvatar(friend)

            Text(friend.name)
                .font(.kithBody)
                .foregroundStyle(mark)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if added { addedFriends.remove(friend.name) } else { addedFriends.insert(friend.name) }
            } label: {
                ZStack {
                    if added {
                        Image(systemName: "checkmark")
                            .font(.kithBody)
                            .fontWeight(.semibold)
                            .foregroundStyle(surface)
                            .frame(width: 35, height: 35)
                            .background(mark, in: Circle())
                    } else {
                        Image("AddFriendIcon")
                            .resizable()
                            .frame(width: 35, height: 35)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(friend.name)
            .accessibilityValue(added ? "Added" : "Not added")
        }
        .frame(height: 50)
    }

    private func friendAvatar(_ friend: Friend) -> some View {
        avatarFace(friend)
            .frame(width: 50, height: 50)
            .overlay(alignment: .bottomTrailing) {
                // The comp badges everyone reachable over iMessage but not on Bloom
                // yet; everyone already on it gets the mark, badged the same way.
                if friend.isOnKith {
                    Image("BloomMark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 9)
                        .foregroundStyle(surface)
                        .frame(width: 15, height: 15)
                        .background(mark, in: Circle())
                        .overlay(Circle().strokeBorder(surface, lineWidth: 1))
                } else {
                    Image("MessagesBadge")
                        .resizable()
                        .frame(width: 15, height: 15)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1))
                }
            }
    }

    @ViewBuilder
    private func avatarFace(_ friend: Friend) -> some View {
        switch friend.face {
        case .photo(let name):
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: 50, height: 50)
                .clipShape(Circle())
        case .plate(let name):
            ZStack {
                Image(name)
                    .resizable()
                    .frame(width: 50, height: 50)
                Text(friend.initials)
                    .font(.kithInitials)
                    .foregroundStyle(mark)
            }
        case .tint(let color):
            ZStack {
                Circle().fill(color)
                Text(friend.initials)
                    .font(.kithInitials)
                    .foregroundStyle(mark)
            }
            .frame(width: 50, height: 50)
        }
    }

    /// The exported band from the comp. The travelling blob lands on top of it,
    /// where the comp puts its mint star.
    private func decorativeBand(size: CGSize) -> some View {
        let scale = size.width / designWidth

        return Image("FriendsBand")
            .resizable()
            .frame(width: 414.353 * scale, height: 118.771 * scale)
            .position(
                x: (-12.94 + 414.353 / 2) * scale,
                y: size.height * (78.2 / designHeight) + 118.771 * scale / 2
            )
            .accessibilityHidden(true)
    }

    // MARK: - Shared controls

    private func pillButton(
        _ title: String,
        size: CGSize,
        enabled: Bool = true,
        style: KithPillButton.Style = .solid,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        KithPillButton(
            title: title,
            accessibilityHint: accessibilityHint,
            isEnabled: enabled,
            style: style,
            action: action
        )
        .position(x: size.width / 2, y: size.height * (708 / designHeight))
    }

    /// Straight into the app, for anyone who doesn't want the tour. On the
    /// photo step it skips just the photo and carries on.
    private func skipButton(size: CGSize) -> some View {
        Button { step == .profilePhoto ? advance() : finish() } label: {
            Text("Skip")
                .font(.kithCaptionStrong)
                .foregroundStyle(KithTheme.secondary(isDark))
                .frame(minHeight: 44)
                .frame(maxWidth: 120)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .position(x: size.width / 2, y: size.height * (762 / designHeight))
        .accessibilityLabel("Skip")
        .accessibilityHint(step == .profilePhoto ? "Carries on without a photo" : "Goes straight into Bloom")
    }

    private func pageControl(size: CGSize) -> some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { page in
                Circle()
                    .fill(mark.opacity(page == step ? 1 : 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(height: 8)
        .position(x: size.width / 2, y: size.height * (810 / designHeight))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(OnboardingStep.allCases.count)")
    }

    // MARK: - Navigation

    /// Onboarding is the only place you say your name, so hand it over before
    /// leaving — otherwise Home and Profile keep greeting the stand-in.
    private func finish() {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { savedName = typed }
        onComplete?()
    }

    private func advance() {
        guard let next = step.next else {
            finish()
            return
        }
        navigate(to: next)
    }

    private func navigate(to destination: OnboardingStep) {
        guard destination != step else { return }
        turnPage(to: destination)
    }

    #if DEBUG
    private func replayEntrance() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            step = .welcome
            phoneStage = .number
            didStart = false
            name = ""
            phone = ""
            code = ""
            addedFriends = []
            answeredPermissions = []
            appleCalendarAsked = false
            search = ""
            logoSettled = false
            wordmarkOpacity = 1
            wordmarkOffset = 0
            taglineVisible = false
            controlsVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: beginEntrance)
    }
    #endif

    private func beginEntrance() {
        guard !didStart else { return }
        didStart = true

        guard step == .welcome else {
            logoSettled = true
            wordmarkOpacity = 0
            taglineVisible = true
            controlsVisible = true
            return
        }

        guard !reduceMotion else {
            logoSettled = true
            wordmarkOpacity = 0
            taglineVisible = true
            controlsVisible = true
            return
        }

        // The word pulls away to the right and is gone; the seed it leaves
        // behind grows into place.
        withAnimation(.easeIn(duration: 0.45).delay(1.0)) {
            wordmarkOpacity = 0
            wordmarkOffset = 70
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.82).delay(1.35)) { logoSettled = true }
        withAnimation(.easeOut(duration: 1.3).delay(2.2)) { taglineVisible = true }
        withAnimation(.easeOut(duration: 1.3).delay(2.5)) { controlsVisible = true }
    }
}

// MARK: - Demo permissions

// Permission screens only advance the prototype; they never read contacts, location, or photos.
#Preview {
    OnboardingView()
}


// MARK: - Friends

/// Someone you might add. Whether they are already on Kith decides how the row
/// reads: the Kith mark beside the name, or the iMessage badge saying you would
/// be reaching them over Messages.
struct Friend: Identifiable {
    enum Face {
        case photo(String)
        /// One of the comp's exported avatar plates.
        case plate(String)
        case tint(Color)
    }

    let name: String
    var face: Face
    var isOnKith = false

    var id: String { name }

    var initials: String {
        String(name.split(separator: " ").compactMap(\.first).prefix(2))
    }

    /// The four from the comp, then enough others to make the list feel real.
    static let sample: [Friend] = DemoCast.isJudge ? DemoCast.onboardingFriends : [
        Friend(name: "Manitej Boorgu", face: .photo("FriendAvatar"), isOnKith: true),
        Friend(name: "Michelle Xuan", face: .plate("AvatarPink")),
        Friend(name: "Ray Arayilikath", face: .plate("AvatarYellow")),
        Friend(name: "Jadden Picardal", face: .photo("AvatarJadden")),
        Friend(name: "Ishan Goyal", face: .tint(Color(red: 0.72, green: 0.85, blue: 0.98))),
        Friend(name: "Priya Raghunathan", face: .tint(Color(red: 0.76, green: 0.69, blue: 1.0)), isOnKith: true),
        Friend(name: "Dev Shah", face: .tint(Color(red: 0.55, green: 0.90, blue: 0.75))),
        Friend(name: "Nina Alvarez", face: .tint(Color(red: 1.0, green: 0.78, blue: 0.69))),
        Friend(name: "Theo Lindqvist", face: .tint(Color(red: 0.98, green: 0.88, blue: 0.56))),
        Friend(name: "Amara Okafor", face: .tint(Color(red: 0.85, green: 0.80, blue: 0.95)), isOnKith: true),
        Friend(name: "Kenji Watanabe", face: .tint(Color(red: 0.70, green: 0.92, blue: 0.92))),
        Friend(name: "Sofia Marchetti", face: .tint(Color(red: 1.0, green: 0.72, blue: 0.78)))
    ]
}

// Permission pages only advance the prototype; they never access device data.

/// What the number and code fields accept. Anything that isn't a digit —
/// letters from a hardware keyboard, a pasted "+1" — is dropped as it arrives.
enum PhoneEntry {
    /// A US number without the country code.
    static let digitLimit = 10
    static let codeLength = 6

    /// "(765) 555-0142", built up as you type. Backspacing over a bracket or
    /// dash takes the digit before it, so the formatting can't trap the cursor.
    static func formatNumber(_ text: String, previous: String) -> String {
        var digits = String(text.filter(\.isWholeNumber).prefix(digitLimit))
        let previousDigits = String(previous.filter(\.isWholeNumber))
        if text.count < previous.count, digits == previousDigits, !digits.isEmpty {
            digits.removeLast()
        }

        switch digits.count {
        case 0:
            return ""
        case 1...3:
            return "(\(digits)"
        case 4...6:
            return "(\(digits.prefix(3))) \(digits.dropFirst(3))"
        default:
            return "(\(digits.prefix(3))) \(digits.dropFirst(3).prefix(3))-\(digits.dropFirst(6))"
        }
    }

    static func code(_ text: String) -> String {
        String(text.filter(\.isWholeNumber).prefix(codeLength))
    }
}

/// The system contact picker, for taking your photo off your own card. It
/// runs out of process, so it needs no Contacts permission. Hands back the
/// card's photo, or nil if the card has none or you cancel.
private struct ContactCardPicker: UIViewControllerRepresentable {
    var onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactImageDataKey]
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            // Reading a key the picker didn't fetch throws, so check first.
            let fetched = contact.isKeyAvailable(CNContactImageDataAvailableKey) && contact.isKeyAvailable(CNContactImageDataKey)
            let data = fetched && contact.imageDataAvailable ? contact.imageData : nil
            onPick(data.flatMap(UIImage.init(data:)))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            onPick(nil)
        }
    }
}
