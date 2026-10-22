import SwiftUI

/// A stand-in for a UIKit permission alert.
///
/// The real one only ever appears once per install, which makes it useless for
/// a demo you shoot more than once — so this is a replica that fires every time
/// and looks the same in every take. Metrics are UIAlertController's: 270pt
/// wide, 14pt corners, 17pt semibold title, 13pt message, 44pt buttons split by
/// hairline separators.
struct SystemAlert: Identifiable, Equatable {
    struct Action: Identifiable, Equatable {
        let title: String
        var grants = false
        /// iOS bolds the affirmative choice.
        var isPreferred = false

        var id: String { title }
    }

    let id = UUID()
    var title: String
    var message: String
    /// Permission alerts stack their options rather than sitting them side by side.
    var actions: [Action]

    static func == (lhs: SystemAlert, rhs: SystemAlert) -> Bool { lhs.id == rhs.id }
}

struct SystemAlertView: View {
    let alert: SystemAlert
    var onChoice: (SystemAlert.Action) -> Void

    @State private var shown = false

    private let hairline = 1.0 / UIScreen.main.scale
    private let systemBlue = Color(red: 0.0, green: 0.478, blue: 1.0)

    var body: some View {
        ZStack {
            Color.black.opacity(shown ? 0.18 : 0)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 2) {
                    // Text styles, not fixed sizes, so the stand-in grows with
                    // the phone's text size the way the real alert does.
                    Text(alert.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(alert.message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 19)
                .padding(.bottom, 18)

                ForEach(alert.actions) { action in
                    Rectangle()
                        .fill(Color(uiColor: .separator))
                        .frame(height: hairline)

                    Button { onChoice(action) } label: {
                        Text(action.title)
                            .font(.body.weight(action.isPreferred ? .semibold : .regular))
                            .foregroundStyle(systemBlue)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 290)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(shown ? 1 : 1.18)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) { shown = true }
        }
        .accessibilityAddTraits(.isModal)
    }
}

extension SystemAlert {
    /// Apple's own wording and button order for each prompt: the affirmative
    /// option on top, "Don’t Allow" at the bottom.
    static func permission(for step: OnboardingStep) -> SystemAlert? {
        switch step {
        case .contacts:
            return SystemAlert(
                title: "“Bloom” Would Like to Access Your Contacts",
                message: "Bloom uses your contacts to find friends already on the app.",
                actions: [
                    Action(title: "Allow Full Access", grants: true, isPreferred: true),
                    Action(title: "Select Contacts…", grants: true),
                    Action(title: "Don’t Allow")
                ]
            )
        case .location:
            return SystemAlert(
                title: "Allow “Bloom” to use your location?",
                message: "Bloom notices where you spend time so hangouts log themselves.",
                actions: [
                    Action(title: "Allow While Using App", grants: true, isPreferred: true),
                    Action(title: "Allow Once", grants: true),
                    Action(title: "Don’t Allow")
                ]
            )
        case .photos:
            return SystemAlert(
                title: "“Bloom” Would Like to Access Your Photos",
                message: "Bloom arranges the photos from time you spend with friends.",
                actions: [
                    Action(title: "Allow Full Access", grants: true, isPreferred: true),
                    Action(title: "Limit Access…", grants: true),
                    Action(title: "Don’t Allow")
                ]
            )
        default:
            return nil
        }
    }
}

#Preview {
    ZStack {
        Color.orange.opacity(0.2).ignoresSafeArea()
        SystemAlertView(alert: .permission(for: .contacts)!, onChoice: { _ in })
    }
}
