import SwiftUI

// Connecting a calendar, simulated like the onboarding permissions: the flows
// look and feel real, but nothing reads or leaves the device. Bloom would only
// ever need free/busy times from a calendar, so that's all the copy promises.

/// Where your busy times could come from.
enum CalendarSource: String, CaseIterable, Identifiable {
    case google
    case apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .google: return "Google Calendar"
        case .apple: return "Apple Calendar"
        }
    }

    /// The row's subtitle before connecting.
    var pitch: String {
        switch self {
        case .google: return "Find times from your Google account"
        case .apple: return "Find times from calendars on this iPhone"
        }
    }

    /// The row's subtitle once connected.
    func connectedDetail(calendars: Int) -> String {
        let count = calendars == 1 ? "1 calendar" : "\(calendars) calendars"
        switch self {
        case .google: return "\(GoogleCalendarConnectSheet.account) · \(count)"
        case .apple: return "All calendars on this iPhone"
        }
    }

    /// Where the connection is remembered.
    var storageKey: String { "calendar.\(rawValue)" }
}

extension SystemAlert {
    /// iOS 17's wording for full calendar access.
    static let calendar = SystemAlert(
        title: "“Bloom” Would Like Full Access to Your Calendar",
        message: "Bloom checks when you're busy so it can find times you and your friends are both free.",
        actions: [
            Action(title: "Allow Full Access", grants: true, isPreferred: true),
            Action(title: "Don’t Allow")
        ]
    )
}

/// Connecting Google Calendar: pick the account, pick which calendars count
/// toward "busy", connect. Drawn in Bloom's own style rather than Google's.
struct GoogleCalendarConnectSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    /// The sample account the demo connects.
    static let account = "amber.demo@gmail.com"

    private enum Stage { case account, calendars, connecting }

    @State private var stage = Stage.account
    @State private var chosen: Set<String> = ["Personal", "School"]

    var onConnect: (_ calendars: Int) -> Void

    private let calendars = [
        ("Personal", FriendBlob.sky.color),
        ("School", FriendBlob.butter.color),
        ("Work", FriendBlob.coral.color),
        ("Birthdays", FriendBlob.orchid.color)
    ]

    private var isDark: Bool { colorScheme == .dark }
    private var ink: Color { KithTheme.ink(isDark) }
    private var secondary: Color { KithTheme.secondary(isDark) }
    private var card: Color { KithTheme.suggestionCard(isDark) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                switch stage {
                case .account:
                    accountStep
                case .calendars:
                    calendarStep
                case .connecting:
                    connectingStep
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KithTheme.canvas(isDark))
            .animation(.easeInOut(duration: 0.25), value: stage)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(ink)
                        .disabled(stage == .connecting)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(stage == .connecting)
    }

    // MARK: - Steps

    private var accountStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            header(
                "Connect Google Calendar",
                "Bloom only sees when you're busy. Event names and details stay in Google Calendar."
            )

            Button { stage = .calendars } label: {
                HStack(spacing: 12) {
                    Text("A")
                        .font(.kithBodyStrong)
                        .foregroundStyle(ink)
                        .frame(width: 36, height: 36)
                        .background(FriendBlob.lavender.color, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Amber")
                            .font(.kithCardTitle)
                            .foregroundStyle(ink)
                        Text(Self.account)
                            .font(.kithCaption)
                            .foregroundStyle(secondary)
                    }
                    Spacer(minLength: 8)
                    Image("ChevronRightIcon")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(secondary)
                }
                .padding(12)
                .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Continue as \(Self.account)")
        }
    }

    private var calendarStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            header("Which calendars count?", "Time on these shows as busy when friends look for a time.")

            VStack(spacing: 0) {
                ForEach(calendars, id: \.0) { name, color in
                    Toggle(isOn: Binding(
                        get: { chosen.contains(name) },
                        set: { on in if on { chosen.insert(name) } else { chosen.remove(name) } }
                    )) {
                        HStack(spacing: 10) {
                            Circle().fill(color).frame(width: 12, height: 12)
                            Text(name)
                                .font(.kithCardTitle)
                                .foregroundStyle(ink)
                        }
                    }
                    .tint(KithTheme.overlap)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
            .background(card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            KithPillButton(title: "Connect", isEnabled: !chosen.isEmpty) { connect() }
                .frame(maxWidth: .infinity)
        }
    }

    private var connectingStep: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(ink)
            Text("Connecting to Google Calendar…")
                .font(.kithSecondary)
                .foregroundStyle(secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func header(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.kithHeading)
                .foregroundStyle(ink)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(.kithCaption)
                .foregroundStyle(secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A short, believable wait, then done.
    private func connect() {
        stage = .connecting
        let count = chosen.count
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            onConnect(count)
            dismiss()
        }
    }
}
