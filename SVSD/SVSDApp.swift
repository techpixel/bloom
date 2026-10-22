import SwiftUI
import UIKit
import UserNotifications

@main
struct SVSDApp: App {
    @UIApplicationDelegateAdaptor(DemoNotificationDelegate.self) private var notificationDelegate

    init() {
        KithType.registerFonts()
        #if JUDGE_DEMO
        // Every judging session starts with Bloom on, whatever an earlier run
        // on the same Mac left the switch at.
        UserDefaults.standard.removeObject(forKey: "settings.onBreak")
        #endif
        // Before any of the sample people are made.
        Recast.prepare()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .kithTypeScaling()
                #if targetEnvironment(macCatalyst)
                .onAppear(perform: MacWindow.fitToPhone)
                #endif
                #if DEBUG
                .onAppear { FeedbackKit.install() }
                #endif
        }
    }
}

#if targetEnvironment(macCatalyst)
/// On a Mac, Bloom runs in a window the size of an iPhone 16, so every screen
/// is laid out exactly as it is on the phone, with no title in the bar.
enum MacWindow {
    static let size = CGSize(width: 393, height: 852)
    /// An iPhone 16's safe area: the Dynamic Island's band at the top and the
    /// home indicator's at the bottom. Giving the window the same insets makes
    /// every screen sit exactly where it does on the phone.
    static let phoneInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)

    static func fitToPhone() {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.sizeRestrictions?.minimumSize = size
            windowScene.sizeRestrictions?.maximumSize = size
            windowScene.titlebar?.titleVisibility = .hidden
            windowScene.titlebar?.toolbar = nil
        }
        // Once the window has its own insets (the title bar's), top them up
        // to the phone's rather than adding on top.
        DispatchQueue.main.async {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows {
                    guard let root = window.rootViewController else { continue }
                    let own = window.safeAreaInsets
                    let added = root.additionalSafeAreaInsets
                    root.additionalSafeAreaInsets = UIEdgeInsets(
                        top: max(0, phoneInsets.top - (own.top - added.top)),
                        left: 0,
                        bottom: max(0, phoneInsets.bottom - (own.bottom - added.bottom)),
                        right: 0
                    )
                }
            }
        }
    }
}
#endif

private final class DemoNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        DemoRemote.shared.start()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// Onboarding hands off to the main tabs once it finishes. Scheduling opens
/// from a friend on the Friends tab.
struct RootView: View {
    #if DEBUG
    @State private var onboarded = ["-ShowSchedule", "-ShowFriends", "-ShowRecaps", "-ShowToday", "-ShowProfile"]
        .contains(where: ProcessInfo.processInfo.arguments.contains)
    @StateObject private var dev = DevRouter()
    #else
    // Celeste's build (Release, on an iPhone) opens straight on Home, already
    // set up; Log Out still replays onboarding. The judge's and the Mac's
    // start at the beginning.
    #if JUDGE_DEMO || targetEnvironment(macCatalyst)
    @State private var onboarded = false
    #else
    @State private var onboarded = true
    #endif
    #endif

    var body: some View {
        content
        #if DEBUG
            // Rebuilt on each jump, so every screen starts clean.
            .id(dev.destination)
            // Beside the feedback pin, top left, so the top-right corner stays
            // free for the screens' own buttons (Profile's Edit).
            // Measured from the screen's edge, like the pin's own window, so
            // the two line up instead of the wrench dropping below the notch.
            .overlay {
                DevMenuButton(router: dev)
                    .padding(.top, 15)
                    .padding(.leading, 64)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea()
            }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        #if DEBUG
        switch dev.destination {
        case .onboarding(let step):
            OnboardingView(onComplete: { dev.destination = .tab(.today) }, start: step)
        case .onboardingCode:
            OnboardingView(
                onComplete: { dev.destination = .tab(.today) },
                start: .phone,
                startOnCode: true
            )
        case .tab(let tab):
            MainTabView(initialTab: tab, onLogOut: { dev.destination = .onboarding(.welcome) })
        case .plan(let range):
            PlanFlowView(initialRange: range)
        case .planWeekDay:
            PlanFlowView(initialRange: .thisWeek, openDay: true)
        case .messageThread:
            MessageThreadView(
                contact: KithContact(
                    name: "Jadden Picardal",
                    face: .photo(Portrait(asset: "AvatarJadden", width: 1.54, height: 1.54))
                )
            )
        case nil:
            defaultContent
        }
        #else
        defaultContent
        #endif
    }

    @ViewBuilder
    private var defaultContent: some View {
        if onboarded && !contactsResolved {
            // Onboarding, which would ask, is skipped on Celeste, so iOS asks
            // here, before Home is built from the real people.
            KithTheme.canvas(false)
                .ignoresSafeArea()
                .task {
                    _ = await DeviceContacts.requestAccess()
                    Recast.prepare()
                    contactsResolved = true
                }
        } else if onboarded {
            MainTabView(onLogOut: { onboarded = false })
        } else {
            OnboardingView(onComplete: { onboarded = true })
                .overlay {
                    if DemoCast.isJudge && !demoNoticeRead {
                        DemoNotice { withAnimation(.easeInOut(duration: 0.35)) { demoNoticeRead = true } }
                            .transition(.opacity)
                    }
                }
        }
    }

    /// The judge's build opens on a note about what's simulated, once.
    @AppStorage("demo.noticeRead") private var demoNoticeRead = false
    @State private var contactsResolved = !DeviceContacts.needsAsking
}

/// What's real and what isn't, before the judge's build starts: shown once,
/// over the welcome screen.
private struct DemoNotice: View {
    var onStart: () -> Void

    private let points: [(title: String, detail: String)] = [
        ("Everything here is a demo.", "Bloom is a working prototype. Nothing you type or choose leaves this Mac."),
        ("Your friends are made up.", "Nora and Leo, and your time with them, are sample data so there’s something to look at."),
        ("Location, calendars and contacts are simulated.", "The permission prompts are stand-ins: allowing them doesn’t share anything, and hangouts aren’t really being tracked."),
        ("Texts stay in the app.", "“Send a text” opens a look-alike Messages thread instead of sending anything.")
    ]

    var body: some View {
        ZStack {
            KithTheme.canvas(false).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Before You Start")
                        .font(.kithHeading)
                        .foregroundStyle(KithTheme.ink(false))
                    Text("A few things about this demo.")
                        .font(.kithCaption)
                        .foregroundStyle(KithTheme.secondary(false))
                }

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(points, id: \.title) { point in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title)
                                .font(.kithCardTitle)
                                .foregroundStyle(KithTheme.ink(false))
                            Text(point.detail)
                                .font(.kithCaption)
                                .foregroundStyle(KithTheme.secondary(false))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                KithPillButton(title: "Start the Demo", action: onStart)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)
        }
        .accessibilityElement(children: .contain)
    }
}

enum AppTab: Hashable {
    case friends
    case today
    case recaps
    case profile
}

/// The floating bottom nav from the comps. On iOS 26 the system tab bar is
/// already the floating glass capsule they draw, so it stays a plain TabView.
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab
    /// One set of hangouts for Home, Recaps and every entry page.
    @State private var hangouts = HangoutStore()

    var onLogOut: (() -> Void)?

    init(initialTab: AppTab? = nil, onLogOut: (() -> Void)? = nil) {
        self.onLogOut = onLogOut
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        // Home first, after onboarding and on every launch. The flags pick
        // another tab for a debug launch; scheduling opens from Friends.
        let fallback: AppTab
        if arguments.contains("-ShowRecaps") {
            fallback = .recaps
        } else if arguments.contains("-ShowToday") {
            fallback = .today
        } else if arguments.contains("-ShowProfile") {
            fallback = .profile
        } else if arguments.contains("-ShowFriends") || arguments.contains("-ShowSchedule") {
            fallback = .friends
        } else {
            fallback = .today
        }
        #else
        let fallback = AppTab.today
        #endif
        _tab = State(initialValue: initialTab ?? fallback)
    }

    var body: some View {
        TabView(selection: $tab) {
            FriendsView()
                .tabItem { navLabel("Friends", icon: "NavFriends", tab: .friends) }
                .tag(AppTab.friends)
                .phoneTabBarOnMac()

            TodayView()
                .tabItem { navLabel("Home", icon: "NavToday", tab: .today) }
                .tag(AppTab.today)
                .phoneTabBarOnMac()

            RecapsView(onOpenProfile: { tab = .profile })
                .tabItem { navLabel("Recaps", icon: "NavRecaps", tab: .recaps) }
                .tag(AppTab.recaps)
                .phoneTabBarOnMac()

            ProfileView(onLogOut: onLogOut)
                .tabItem { navLabel("Profile", icon: "NavProfile", tab: .profile) }
                .tag(AppTab.profile)
                .phoneTabBarOnMac()
        }
        .tint(KithTheme.navActive)
        // The demo remote: a Mac on the same Wi-Fi asks for a prompt, it lands
        // in Home's Recent, and Home comes forward to show it.
        .onAppear {
            let store = hangouts
            DemoRemote.shared.handler = { request in
                var problem: String?
                withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                    problem = store.apply(remote: request)
                    // Naming lands on the entry you're on; the rest show on Home.
                    if problem == nil, request["kind"] as? String != "name" { tab = .today }
                }
                return problem
            }
            DemoRemote.shared.friends = { store.remoteFriends }
        }
        .onDisappear {
            DemoRemote.shared.handler = nil
            DemoRemote.shared.friends = nil
        }
        // Coming back the next day lets go of anything left unanswered.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { hangouts.dropExpired() }
        }
        #if targetEnvironment(macCatalyst)
        // A Mac puts tabs along the top; Bloom keeps the phone's floating bar.
        .overlay(alignment: .bottom) {
            PhoneTabBar(selection: $tab)
                .padding(.horizontal, 25)
                .padding(.bottom, 10)
        }
        #endif
        .environment(hangouts)
    }

    /// Flowbite icons: the solid one for the tab you're on, the outline for
    /// the rest, the way iOS tab bars mark the selection.
    private func navLabel(_ title: String, icon: String, tab: AppTab) -> some View {
        Label(title, image: self.tab == tab ? icon + "Fill" : icon)
    }
}

// MARK: - The phone's tab bar, on a Mac

private extension View {
    /// Hides the system tab bar on a Mac, where it would sit along the top.
    @ViewBuilder
    func phoneTabBarOnMac() -> some View {
        #if targetEnvironment(macCatalyst)
        toolbar(.hidden, for: .tabBar)
        #else
        self
        #endif
    }
}

#if targetEnvironment(macCatalyst)
/// iOS 26's floating tab bar, drawn by hand for the Mac: a glass capsule of
/// four icons with labels, the current one on a soft pill in the nav colour.
private struct PhoneTabBar: View {
    @Binding var selection: AppTab
    @Namespace private var pill

    private let items: [(tab: AppTab, title: String, icon: String)] = [
        (.friends, "Friends", "NavFriends"),
        (.today, "Home", "NavToday"),
        (.recaps, "Recaps", "NavRecaps"),
        (.profile, "Profile", "NavProfile")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.title) { item in
                let chosen = selection == item.tab
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { selection = item.tab }
                } label: {
                    VStack(spacing: 3) {
                        Image(chosen ? item.icon + "Fill" : item.icon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                        Text(item.title)
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(chosen ? KithTheme.navActive : KithTheme.ink(false))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if chosen {
                            Capsule()
                                .fill(Color.black.opacity(0.06))
                                .matchedGeometryEffect(id: "pill", in: pill)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.6), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
#endif
