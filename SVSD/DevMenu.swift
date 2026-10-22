#if DEBUG
import SwiftUI

/// Every screen and sub-state in the app, so a demo can start anywhere without
/// tapping through the flow first. DEBUG only — the whole file compiles out of
/// a release build.
enum DevDestination: Hashable, Identifiable, CaseIterable {
    case onboarding(OnboardingStep)
    /// The number screen's second prompt, which is a state rather than a page.
    case onboardingCode
    case tab(AppTab)
    case plan(ScheduleRange)
    /// The week screen after a day has been picked.
    case planWeekDay
    case messageThread

    var id: Self { self }

    static var allCases: [DevDestination] {
        OnboardingStep.allCases.map(DevDestination.onboarding)
            + [.onboardingCode]
            + [AppTab.friends, .today, .recaps, .profile].map(DevDestination.tab)
            + [ScheduleRange.today, .tomorrow, .thisWeek].map(DevDestination.plan)
            + [.planWeekDay, .messageThread]
    }

    var group: String {
        switch self {
        case .onboarding, .onboardingCode: return "Onboarding"
        case .tab: return "Tabs"
        case .plan, .planWeekDay: return "Planning"
        case .messageThread: return "Props"
        }
    }

    var title: String {
        switch self {
        case .onboarding(let step): return step.devTitle
        case .onboardingCode: return "Enter your code"
        case .tab(let tab): return tab.devTitle
        case .plan(let range): return "Schedule · \(range.title)"
        case .planWeekDay: return "Week · day picked"
        case .messageThread: return "Messages thread"
        }
    }

    var symbol: String {
        switch self {
        case .onboarding, .onboardingCode: return "figure.walk"
        case .tab: return "square.grid.2x2"
        case .plan, .planWeekDay: return "calendar"
        case .messageThread: return "message"
        }
    }
}

extension OnboardingStep {
    var devTitle: String {
        switch self {
        case .welcome: return "Welcome"
        case .phone: return "We’ll need your number"
        case .name: return "What’s your name?"
        case .profilePhoto: return "Add a photo of you"
        case .celebrate: return "Welcome, <name>!"
        case .contacts: return "Permission · Contacts"
        case .location: return "Permission · Location"
        case .photos: return "Permission · Photos"
        case .calendar: return "Permission · Calendar"
        case .friends: return "Find your friends"
        }
    }
}

extension AppTab {
    var devTitle: String {
        switch self {
        case .friends: return "Friends"
        case .today: return "Home"
        case .recaps: return "Recaps"
        case .profile: return "Profile"
        }
    }
}

/// Holds whichever screen the dev menu last jumped to.
@MainActor
final class DevRouter: ObservableObject {
    @Published var destination: DevDestination?

    init() {
        // Launch straight onto a screen, for screenshots and recordings.
        if ProcessInfo.processInfo.arguments.contains("-ShowThread") {
            destination = .messageThread
        }
    }
}

/// A small floating control that opens the jump list. Long-press it for the
/// same list as a context menu, which is quicker mid-demo.
struct DevMenuButton: View {
    @ObservedObject var router: DevRouter
    @State private var showingList = false

    var body: some View {
        Button { showingList = true } label: {
            Image(systemName: "wrench.adjustable.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu { menuItems }
        .sheet(isPresented: $showingList) {
            DevMenuList(router: router)
        }
        .accessibilityLabel("Developer menu")
    }

    @ViewBuilder
    private var menuItems: some View {
        ForEach(groups, id: \.name) { group in
            Menu(group.name) {
                ForEach(group.items) { item in
                    Button(item.title) { router.destination = item }
                }
            }
        }
        Button("Back to the start", role: .destructive) { router.destination = nil }
    }

    private var groups: [(name: String, items: [DevDestination])] {
        DevMenuList.groups
    }
}

private struct DevMenuList: View {
    @ObservedObject var router: DevRouter
    @Environment(\.dismiss) private var dismiss

    static var groups: [(name: String, items: [DevDestination])] {
        var order: [String] = []
        var byGroup: [String: [DevDestination]] = [:]
        for item in DevDestination.allCases {
            if byGroup[item.group] == nil { order.append(item.group) }
            byGroup[item.group, default: []].append(item)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        router.destination = nil
                        dismiss()
                    } label: {
                        Label("Back to the start", systemImage: "arrow.counterclockwise")
                    }
                }

                ForEach(Self.groups, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.items) { item in
                            Button {
                                router.destination = item
                                dismiss()
                            } label: {
                                HStack {
                                    Label(item.title, systemImage: item.symbol)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if router.destination == item {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Jump to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#endif
