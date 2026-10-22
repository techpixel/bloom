import MessageUI
import SwiftUI

/// A stand-in for the Messages thread, built to match what iOS actually draws:
/// tailed bubbles at 17pt, the stacked avatar-and-name title, and the plus
/// button beside the rounded composer. It's what the simulator shows, because
/// the simulator can't send texts; a phone gets the real Messages composer
/// (`messageSheet`). Like the real one it starts empty: Bloom never writes the
/// message for you, and nothing answers back.
struct MessageThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var composerFocused: Bool

    let contact: KithContact

    @State private var text = ""
    @State private var thread: [ChatBubble] = []
    @State private var delivered = false

    private let blue = Color(red: 0.0, green: 0.478, blue: 1.0)
    private let incoming = Color(red: 0.898, green: 0.898, blue: 0.914)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Divider()
                conversation
                composer
            }
            .background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { backButton }
                ToolbarItem(placement: .principal) { title }
            }
        }
    }

    // MARK: - Chrome

    private var backButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.backward")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(blue)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Back to Messages")
    }

    private var title: some View {
        VStack(spacing: 2) {
            ContactAvatar(contact: contact, diameter: 34, badgeRing: .clear)

            HStack(spacing: 2) {
                Text(contact.firstName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Conversation with \(contact.firstName)")
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    dateHeader

                    Text("Simulator preview · on iPhone this opens Messages")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 2)

                    ForEach(Array(thread.enumerated()), id: \.element.id) { index, bubble in
                        row(bubble, isLastOfRun: isLastOfRun(index))
                            .padding(.top, startsNewRun(index) ? 8 : 0)
                    }

                    if delivered {
                        Text("Delivered")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.top, 2)
                            .padding(.trailing, 4)
                    }

                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread.count) { scrollToBottom(proxy) }
        }
    }

    private var dateHeader: some View {
        Text("Today ").font(.system(size: 12, weight: .semibold))
            + Text(Date().formatted(date: .omitted, time: .shortened))
            .font(.system(size: 12))
    }

    private func row(_ bubble: ChatBubble, isLastOfRun: Bool) -> some View {
        HStack {
            if bubble.isMine { Spacer(minLength: 60) }

            Text(bubble.text)
                .font(.system(size: 17))
                .foregroundStyle(bubble.isMine ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // Only the last bubble of a run gets the tail, as in Messages.
                .background(
                    BubbleShape(isMine: bubble.isMine, hasTail: isLastOfRun)
                        .fill(bubble.isMine ? blue : incoming)
                )

            if !bubble.isMine { Spacer(minLength: 60) }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.7, anchor: bubble.isMine ? .bottomTrailing : .bottomLeading)
                .combined(with: .opacity),
            removal: .opacity
        ))
    }

    /// Messages groups consecutive bubbles from the same sender.
    private func startsNewRun(_ index: Int) -> Bool {
        index > 0 && thread[index - 1].isMine != thread[index].isMine
    }

    private func isLastOfRun(_ index: Int) -> Bool {
        index == thread.count - 1 || thread[index + 1].isMine != thread[index].isMine
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color(uiColor: .secondarySystemFill), in: Circle())
                .accessibilityHidden(true)

            HStack(alignment: .bottom, spacing: 4) {
                TextField("iMessage", text: $text, axis: .vertical)
                    .font(.system(size: 17))
                    .lineLimit(1...5)
                    .focused($composerFocused)
                    .padding(.leading, 12)
                    .padding(.vertical, 6)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(text.isEmpty ? Color(uiColor: .tertiaryLabel) : blue)
                }
                .buttonStyle(.plain)
                .disabled(text.isEmpty)
                .padding(.trailing, 2)
                .padding(.bottom, 1)
                .accessibilityLabel("Send")
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func send() {
        let outgoing = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outgoing.isEmpty else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            thread.append(ChatBubble(text: outgoing, isMine: true))
            text = ""
            delivered = true
        }
        composerFocused = false
    }
}

// MARK: - Pieces

struct ChatBubble: Identifiable {
    let id = UUID()
    let text: String
    let isMine: Bool
}

/// A Messages bubble. The body keeps three rounded corners and squares off the
/// one the tail attaches to, then the tail bulges out and hooks back under —
/// that curl is what makes it read as iMessage rather than a generic chat app.
struct BubbleShape: Shape {
    let isMine: Bool
    var hasTail = true

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailWidth: CGFloat = 6.5
        let body = CGRect(
            x: isMine ? rect.minX : rect.minX + tailWidth,
            y: rect.minY,
            width: rect.width - tailWidth,
            height: rect.height
        )

        guard hasTail else {
            return Path(
                UIBezierPath(roundedRect: body, cornerRadius: radius).cgPath
            )
        }

        // Every corner but the tail's stays fully round.
        let rounded: UIRectCorner = isMine
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]
        var path = Path(
            UIBezierPath(
                roundedRect: body,
                byRoundingCorners: rounded,
                cornerRadii: CGSize(width: radius, height: radius)
            ).cgPath
        )

        let edge = isMine ? body.maxX : body.minX
        let out: CGFloat = isMine ? 1 : -1
        var tail = Path()
        tail.move(to: CGPoint(x: edge, y: body.maxY - 18))
        // Bulges out and down to the tip at the very bottom corner...
        tail.addCurve(
            to: CGPoint(x: edge + out * 7, y: body.maxY),
            control1: CGPoint(x: edge, y: body.maxY - 7),
            control2: CGPoint(x: edge + out * 2, y: body.maxY)
        )
        // ...then hooks back underneath, which is the curl that reads as iMessage.
        tail.addCurve(
            to: CGPoint(x: edge - out * 11, y: body.maxY),
            control1: CGPoint(x: edge + out * 1.5, y: body.maxY - 1.5),
            control2: CGPoint(x: edge - out * 3, y: body.maxY - 5)
        )
        tail.closeSubpath()
        path.addPath(tail)
        return path
    }
}

// MARK: - The real composer

/// Someone you're about to text. Bloom only opens the conversation; what to say
/// is yours to write.
struct MessageDraft: Identifiable {
    let contact: KithContact
    /// Prefilled for an invite; empty for a normal message.
    var body: String = ""

    var id: String { contact.id }
}

extension View {
    /// Opens the real Messages composer when this device can send texts, and
    /// the look-alike thread otherwise (the simulator, an iPad without SMS).
    ///
    /// Addressed to their number when they're a real person from the phone's
    /// contacts, and by name otherwise: looking a made-up friend up in
    /// Contacts would fire the system permission prompt mid-demo.
    func messageSheet(_ draft: Binding<MessageDraft?>) -> some View {
        #if targetEnvironment(macCatalyst)
        // A Mac can't send texts; the look-alike rises in Bloom's own drawer.
        drawer(item: draft) { draft in
            MessageThreadView(contact: draft.contact)
        }
        #else
        sheet(item: draft) { draft in
            if MFMessageComposeViewController.canSendText() {
                MessageComposeSheet(recipients: [draft.contact.phone ?? draft.contact.name], body: draft.body)
                    .ignoresSafeArea()
            } else {
                MessageThreadView(contact: draft.contact)
            }
        }
        #endif
    }
}

/// `MFMessageComposeViewController`, addressed to whoever it's given.
struct MessageComposeSheet: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss

    var recipients: [String] = []
    var body: String = ""

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.recipients = recipients
        if !body.isEmpty { composer.body = body }
        composer.messageComposeDelegate = context.coordinator
        return composer
    }

    func updateUIViewController(_ controller: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: { dismiss() })
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let dismiss: () -> Void

        init(dismiss: @escaping () -> Void) {
            self.dismiss = dismiss
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            dismiss()
        }
    }
}

#Preview {
    MessageThreadView(
        contact: KithContact(
            name: "Jadden Picardal",
            face: .photo(Portrait(asset: "AvatarJadden", width: 1.54, height: 1.54))
        )
    )
}
