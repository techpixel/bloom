import SwiftUI
import UIKit
import UserNotifications

@main
struct SVSDApp: App {
    @UIApplicationDelegateAdaptor(DemoNotificationDelegate.self) private var notificationDelegate

    init() {
        KithType.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .kithTypeScaling()
                #if DEBUG
                .onAppear { FeedbackKit.install() }
                #endif
        }
    }
}

private final class DemoNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
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
    @State private var onboarded = false
    #endif

    var body: some View {
        content
        #if DEBUG
            // Rebuilt on each jump, so every screen starts clean.
            .id(dev.destination)
            .overlay(alignment: .topTrailing) {
                DevMenuButton(router: dev)
                    .padding(.top, 8)
                    .padding(.trailing, 12)
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
        if onboarded {
            MainTabView(onLogOut: { onboarded = false })
        } else {
            OnboardingView(onComplete: { onboarded = true })
        }
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

            TodayView()
                .tabItem { navLabel("Home", icon: "NavToday", tab: .today) }
                .tag(AppTab.today)

            RecapsView(onOpenProfile: { tab = .profile })
                .tabItem { navLabel("Recaps", icon: "NavRecaps", tab: .recaps) }
                .tag(AppTab.recaps)

            ProfileView(onLogOut: onLogOut)
                .tabItem { navLabel("Profile", icon: "NavProfile", tab: .profile) }
                .tag(AppTab.profile)
        }
        .tint(KithTheme.navActive)
        .environment(hangouts)
    }

    /// Flowbite icons: the solid one for the tab you're on, the outline for
    /// the rest, the way iOS tab bars mark the selection.
    private func navLabel(_ title: String, icon: String, tab: AppTab) -> some View {
        Label(title, image: self.tab == tab ? icon + "Fill" : icon)
    }
}
