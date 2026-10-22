import SwiftUI
import UserNotifications

/// The range tabs are shared chrome across the planning comps, so the tab bar
/// lives above both screens and swaps the one underneath it.
struct PlanFlowView: View {
    @State private var showingDemo = false

    @State private var range: ScheduleRange

    var onBack: (() -> Void)?
    /// Opens the week screen with a day already chosen.
    var openDay = false

    init(onBack: (() -> Void)? = nil, initialRange: ScheduleRange? = nil, openDay: Bool = false) {
        self.onBack = onBack
        self.openDay = openDay
        #if DEBUG
        let fallback: ScheduleRange =
            ProcessInfo.processInfo.arguments.contains("-ShowWeek") ? .thisWeek : .today
        #else
        let fallback = ScheduleRange.today
        #endif
        _range = State(initialValue: initialRange ?? fallback)
    }

    var body: some View {
        Group {
            switch range {
            case .today, .tomorrow:
                ScheduleView(range: $range, onBack: onBack)
            case .thisWeek:
                WeekScheduleView(range: $range, onBack: onBack, openFirstDay: openDay)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { showingDemo = true } label: {
                Label("Demo", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(KithTheme.ink(false))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(KithTheme.canvas(false).opacity(0.95), in: Capsule())
                    .overlay(Capsule().stroke(KithTheme.ink(false).opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 56)
            .padding(.trailing, 16)
            .accessibilityHint("Open the scripted demo controls")
        }
        .sheet(isPresented: $showingDemo) { DemoModeView() }
    }
}

private struct DemoModeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var routeIndex = 0
    @State private var isRunning = false
    @State private var notificationStatus = "Notifications are off"

    private let route = [
        ("At home", "Starting point", "house.fill"),
        ("On campus", "Location updated just now", "building.2.fill"),
        ("Chauncey Village", "Manitej is nearby", "mappin.and.ellipse")
    ]
    private let demoContacts = Friend.sample.map(\.name)

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Demo mode")
                        .font(.system(size: 24))
                        .foregroundStyle(KithTheme.ink(isDark))
                    Text("Scripted route · seeded contacts · no live tracking")
                        .font(.system(size: 13))
                        .foregroundStyle(KithTheme.secondary(isDark))
                }
                Spacer()
                Button("Done") { dismiss() }
                    .foregroundStyle(KithTheme.ink(isDark))
            }

            VStack(alignment: .leading, spacing: 10) {
                Label(route[routeIndex].0, systemImage: route[routeIndex].2)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(KithTheme.ink(isDark))
                Text(isRunning ? route[routeIndex].1 : "Start the route to simulate location updates.")
                    .font(.system(size: 14))
                    .foregroundStyle(KithTheme.secondary(isDark))
                HStack(spacing: 7) {
                    ForEach(route.indices, id: \.self) { index in
                        Capsule()
                            .fill(index <= routeIndex && isRunning ? KithTheme.availability : KithTheme.uiFill(isDark))
                            .frame(height: 5)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(KithTheme.suggestionCard(isDark), in: RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 8) {
                Text("Demo contacts")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KithTheme.ink(isDark))
                Text(demoContacts.joined(separator: " · "))
                    .font(.system(size: 13))
                    .foregroundStyle(KithTheme.secondary(isDark))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(notificationStatus)
                .font(.system(size: 13))
                .foregroundStyle(KithTheme.secondary(isDark))

            HStack(spacing: 12) {
                Button(isRunning ? "Restart demo" : "Run demo") { startDemo() }
                    .buttonStyle(DemoPillStyle(isDark: isDark, prominent: true))
                Button("Reset") { resetDemo() }
                    .buttonStyle(DemoPillStyle(isDark: isDark, prominent: false))
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(KithTheme.canvas(isDark))
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: isRunning) {
            guard isRunning else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                routeIndex = (routeIndex + 1) % route.count
            }
        }
    }

    private func startDemo() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            do {
                let allowed = try await center.requestAuthorization(options: [.alert, .sound])
                notificationStatus = allowed ? "Demo alerts are scheduled" : "Notifications are disabled in Settings"
                routeIndex = 0
                isRunning = true
                center.removePendingNotificationRequests(withIdentifiers: ["demo-nearby", "demo-plan"])
                center.removeDeliveredNotifications(withIdentifiers: ["demo-nearby", "demo-plan"])
                guard allowed else { return }
                try await schedule("demo-nearby", title: "Manitej is nearby", body: "You’re both near Chauncey Village.", after: 8)
                try await schedule("demo-plan", title: "A good time to meet", body: "You and Michelle are free this afternoon.", after: 18)
            } catch {
                notificationStatus = "Couldn’t schedule demo alerts"
            }
        }
    }

    private func schedule(_ id: String, title: String, body: String, after seconds: TimeInterval) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try await UNUserNotificationCenter.current().add(request)
    }

    private func resetDemo() {
        isRunning = false
        routeIndex = 0
        notificationStatus = "Notifications are off"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["demo-nearby", "demo-plan"])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["demo-nearby", "demo-plan"])
    }
}

private struct DemoPillStyle: ButtonStyle {
    let isDark: Bool
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(prominent ? KithTheme.canvas(isDark) : KithTheme.ink(isDark))
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(
                prominent ? KithTheme.ink(isDark) : KithTheme.uiFill(isDark),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}
