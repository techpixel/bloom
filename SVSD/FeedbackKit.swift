#if DEBUG
import SwiftUI
import UIKit

// Design feedback, inside the app. Turn on feedback mode with the floating pin
// (or shake: ⌃⌘Z in the simulator), tap anything, say what should change. Each
// note lands in the project's `feedback/` folder as Markdown plus a screenshot
// with the pin drawn on it, so whoever picks up the work can find the spot.
//
// It runs in its own window above the app, so it sits over sheets and
// full-screen covers too, and it never shows up in its own screenshots.
// Debug builds only.

enum FeedbackKit {
    @MainActor static let model = FeedbackModel()
    @MainActor private static var window: FeedbackWindow?

    /// Safe to call more than once; only the first call installs the window.
    @MainActor static func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        window = FeedbackWindow(windowScene: scene, model: model)
    }

    /// The app's own window — what gets screenshotted and searched for labels.
    @MainActor static var appWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { !($0 is FeedbackWindow) && $0.windowLevel == .normal }
    }
}

// MARK: - Model

struct FeedbackDraft: Identifiable {
    let id = UUID()
    let point: CGPoint
    let screenSize: CGSize
    let screenshot: UIImage
    let screen: String
    let nearby: [String]
}

struct FeedbackPin: Identifiable {
    let id = UUID()
    let number: Int
    let point: CGPoint
}

@MainActor
final class FeedbackModel: ObservableObject {
    @Published var isActive = false
    @Published var draft: FeedbackDraft?
    @Published var showingList = false
    @Published private(set) var pins: [FeedbackPin] = []
    @Published private(set) var toast: String?

    /// Where the floating buttons are, so the window lets every other touch
    /// fall through to the app.
    var interactiveFrames: [CGRect] = []

    var capturesTouches: Bool { isActive || draft != nil || showingList }

    init() {
        NotificationCenter.default.addObserver(forName: .feedbackShake, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.isActive.toggle() }
        }
    }

    func mark(at point: CGPoint) {
        guard let window = FeedbackKit.appWindow else { return }
        draft = FeedbackDraft(
            point: point,
            screenSize: window.bounds.size,
            screenshot: FeedbackCapture.screenshot(of: window),
            screen: FeedbackCapture.screenName(in: window),
            nearby: FeedbackCapture.labels(at: point, in: window)
        )
    }

    func save(_ draft: FeedbackDraft, comment: String, tags: [String]) {
        let number = FeedbackStore.openCount() + 1
        do {
            let id = try FeedbackStore.save(draft, number: number, comment: comment, tags: tags)
            pins.append(FeedbackPin(number: number, point: draft.point))
            show("Saved #\(number) · \(id)")
        } catch {
            show("Couldn't save: \(error.localizedDescription)")
        }
        close()
    }

    func close() {
        draft = nil
        // The composer's text field made this window key; hand typing back.
        FeedbackKit.appWindow?.makeKey()
    }

    private func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == message { toast = nil }
        }
    }
}

extension Notification.Name {
    static let feedbackShake = Notification.Name("FeedbackKit.shake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .feedbackShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

// MARK: - Window

private final class FeedbackWindow: UIWindow {
    private let model: FeedbackModel

    init(windowScene: UIWindowScene, model: FeedbackModel) {
        self.model = model
        super.init(windowScene: windowScene)
        windowLevel = .normal + 1
        backgroundColor = .clear
        let host = FeedbackHostingController(rootView: FeedbackOverlay(model: model))
        host.view.backgroundColor = .clear
        rootViewController = host
        isHidden = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        model.capturesTouches || model.interactiveFrames.contains { $0.contains(point) }
    }
}

/// A window this high decides the status bar. The comps are all drawn without
/// one and the app hides it, so the overlay keeps it hidden too.
private final class FeedbackHostingController: UIHostingController<FeedbackOverlay> {
    override var prefersStatusBarHidden: Bool { true }
}

// MARK: - Capturing context

enum FeedbackCapture {
    @MainActor static func screenshot(of window: UIWindow) -> UIImage {
        UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    /// The selected tab, plus whether a sheet or cover is up over it.
    @MainActor static func screenName(in window: UIWindow) -> String {
        guard let root = window.rootViewController else { return "Unknown" }
        var parts: [String] = []
        if let tabs = find(UITabBarController.self, in: root), let title = tabs.tabBar.selectedItem?.title {
            parts.append("\(title) tab")
        }
        var presented = root.presentedViewController
        while let controller = presented {
            parts.append(controller.modalPresentationStyle == .fullScreen ? "full-screen cover" : "sheet")
            presented = controller.presentedViewController
        }
        return parts.isEmpty ? "Root (no tab bar)" : parts.joined(separator: " › ")
    }

    private static func find<T: UIViewController>(_ type: T.Type, in controller: UIViewController) -> T? {
        if let match = controller as? T { return match }
        for child in controller.children {
            if let match = find(type, in: child) { return match }
        }
        return nil
    }

    /// Accessibility labels of the elements under the point, smallest first —
    /// usually the exact control, then the card or row around it.
    @MainActor static func labels(at point: CGPoint, in window: UIWindow) -> [String] {
        var hits: [(area: CGFloat, label: String)] = []
        var visited = 0

        func visit(_ node: NSObject) {
            visited += 1
            guard visited < 5000 else { return }

            let frame = node.accessibilityFrame
            if node.isAccessibilityElement, frame.contains(point),
               let label = node.accessibilityLabel, !label.isEmpty {
                hits.append((frame.width * frame.height, label))
            }

            if let view = node as? UIView {
                guard !view.isHidden, view.alpha > 0.01 else { return }
                view.subviews.forEach(visit)
            }
            if let children = node.accessibilityElements {
                children.compactMap { $0 as? NSObject }.forEach(visit)
            } else {
                let count = node.accessibilityElementCount()
                if count > 0, count != NSNotFound {
                    for index in 0..<count {
                        if let child = node.accessibilityElement(at: index) as? NSObject { visit(child) }
                    }
                }
            }
        }

        visit(window)
        var seen = Set<String>()
        return hits
            .sorted { $0.area < $1.area }
            .map(\.label)
            .filter { seen.insert($0).inserted }
            .prefix(4)
            .map { $0 }
    }
}

// MARK: - Storage

enum FeedbackStore {
    /// In the simulator the app can write straight into the project, which is
    /// where the fixes happen. On a phone it falls back to the app's Documents.
    static let directory: URL = {
        #if targetEnvironment(simulator)
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: project.appendingPathComponent("SVSD.xcodeproj").path) {
            return project.appendingPathComponent("feedback", isDirectory: true)
        }
        #endif
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("feedback", isDirectory: true)
    }()

    struct Entry: Identifiable {
        let id: String
        let status: String
        let summary: String
        let screenshot: URL
    }

    @MainActor static func save(_ draft: FeedbackDraft, number: Int, comment: String, tags: [String]) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let id = formatter.string(from: .now)

        let marked = pinned(draft.screenshot, at: draft.point, number: number)
        try marked.pngData()?.write(to: directory.appendingPathComponent("\(id).png"))

        let size = draft.screenSize
        let across = Int((draft.point.x / max(size.width, 1) * 100).rounded())
        let down = Int((draft.point.y / max(size.height, 1) * 100).rounded())
        let near = draft.nearby.map { "\"\($0)\"" }.joined(separator: " · ")
        let markdown = """
        ---
        status: open
        number: \(number)
        created: \(id)
        screen: \(draft.screen)
        tap: (\(Int(draft.point.x)), \(Int(draft.point.y))) pt of \(Int(size.width)) × \(Int(size.height)) — \(across)% across, \(down)% down
        near: \(near.isEmpty ? "—" : near)
        tags: \(tags.isEmpty ? "—" : tags.joined(separator: ", "))
        ---

        \(comment.isEmpty ? "(no comment — see tags)" : comment)

        ![#\(number)](\(id).png)

        """
        try markdown.write(to: directory.appendingPathComponent("\(id).md"), atomically: true, encoding: .utf8)
        return id
    }

    static func entries() -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "md" && $0.lastPathComponent != "README.md" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let lines = text.components(separatedBy: "\n")
                let status = lines.first { $0.hasPrefix("status:") }?
                    .dropFirst("status:".count).trimmingCharacters(in: .whitespaces) ?? "open"
                let body = text.components(separatedBy: "---\n").dropFirst(2).joined()
                let summary = body.split(separator: "\n").first { !$0.hasPrefix("![") }.map(String.init) ?? ""
                let id = url.deletingPathExtension().lastPathComponent
                return Entry(id: id, status: status, summary: summary, screenshot: directory.appendingPathComponent("\(id).png"))
            }
    }

    static func openCount() -> Int {
        entries().filter { $0.status == "open" }.count
    }

    static func delete(_ entry: Entry) {
        for ext in ["md", "png"] {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(entry.id).\(ext)"))
        }
    }

    /// The screenshot with the numbered pin drawn where you tapped.
    @MainActor private static func pinned(_ image: UIImage, at point: CGPoint, number: Int) -> UIImage {
        UIGraphicsImageRenderer(size: image.size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            return format
        }()).image { _ in
            image.draw(at: .zero)
            let radius: CGFloat = 14
            let circle = UIBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            UIColor(KithTheme.navActive).setFill()
            circle.fill()
            UIColor.white.setStroke()
            circle.lineWidth = 2.5
            circle.stroke()
            let label = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let textSize = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2), withAttributes: attributes)
        }
    }
}

// MARK: - Overlay

private struct FeedbackOverlay: View {
    @ObservedObject var model: FeedbackModel
    /// Starts beside the Dynamic Island, a strip every screen leaves empty.
    @State private var dock = CGPoint(x: 44, y: 32)
    @GestureState private var drag = CGSize.zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.isActive {
                // Catches the tap that places a pin.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .global) { model.mark(at: $0) }
                    .overlay {
                        Rectangle().strokeBorder(KithTheme.navActive, lineWidth: 3)
                    }
                    .overlay(alignment: .top) {
                        Text("Tap anything to leave a note")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(KithTheme.navActive, in: Capsule())
                            .padding(.top, 56)
                            .allowsHitTesting(false)
                    }

                ForEach(model.pins) { pin in
                    Text("\(pin.number)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(KithTheme.navActive, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(pin.point)
                        .allowsHitTesting(false)
                }
            }

            dockButtons
                .position(x: dock.x + drag.width, y: dock.y + drag.height)

            if let toast = model.toast {
                Text(toast)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.8), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 120)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .sheet(item: $model.draft) { draft in
            FeedbackComposer(
                draft: draft,
                number: FeedbackStore.openCount() + 1,
                onSave: { model.save(draft, comment: $0, tags: $1) },
                onCancel: { model.close() }
            )
        }
        .sheet(isPresented: $model.showingList, onDismiss: { FeedbackKit.appWindow?.makeKey() }) {
            FeedbackList()
        }
    }

    /// Drag it anywhere that's out of the way.
    private var dockButtons: some View {
        HStack(spacing: 8) {
            dockButton(model.isActive ? "xmark" : "mappin.and.ellipse", label: model.isActive ? "Stop marking" : "Leave feedback") {
                model.isActive.toggle()
            }
            if model.isActive {
                dockButton("tray.full", label: "All feedback") { model.showingList = true }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.interactiveFrames = [$0] }
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    dock.x += value.translation.width
                    dock.y += value.translation.height
                }
        )
    }

    private func dockButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(model.isActive ? KithTheme.navActive : Color.black.opacity(0.55), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Composer

private struct FeedbackComposer: View {
    let draft: FeedbackDraft
    let number: Int
    var onSave: (String, [String]) -> Void
    var onCancel: () -> Void

    @State private var comment = ""
    @State private var tags: Set<String> = []
    @FocusState private var focused: Bool

    /// Quick intents, like Budge's nudges — combined with the comment.
    private static let quickTags = ["Bigger", "Smaller", "More space", "Less space", "Color", "Alignment", "Copy", "Broken"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(uiImage: draft.screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 140)
                            .overlay {
                                GeometryReader { proxy in
                                    Circle()
                                        .fill(KithTheme.navActive)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                                        .frame(width: 12, height: 12)
                                        .position(
                                            x: draft.point.x / draft.screenSize.width * proxy.size.width,
                                            y: draft.point.y / draft.screenSize.height * proxy.size.height
                                        )
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.screen).font(.subheadline.weight(.semibold))
                            Text(draft.nearby.isEmpty ? "No label under the pin" : draft.nearby.joined(separator: "\n"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    TextField("What should change?", text: $comment, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Self.quickTags, id: \.self) { tag in
                            let on = tags.contains(tag)
                            Button {
                                if on { tags.remove(tag) } else { tags.insert(tag) }
                            } label: {
                                Text(tag)
                                    .font(.footnote.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(on ? .white : .primary)
                                    .background(on ? KithTheme.navActive : Color(.secondarySystemBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Feedback #\(number)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(comment.trimmingCharacters(in: .whitespacesAndNewlines), Self.quickTags.filter(tags.contains))
                    }
                    .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && tags.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }
}

// MARK: - List

private struct FeedbackList: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries = FeedbackStore.entries()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty {
                    Text("Nothing yet. Tap the pin, then tap anything in the app.")
                        .foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        AsyncImage(url: entry.screenshot) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            Color(.secondarySystemBackground)
                        }
                        .frame(width: 44, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.summary).lineLimit(2)
                            Text(entry.status == "open" ? "Open" : entry.status.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(entry.status == "open" ? KithTheme.navActive : .secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { entries[$0] }.forEach(FeedbackStore.delete)
                    entries.remove(atOffsets: offsets)
                }

                Section {
                    Text(FeedbackStore.directory.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Saved to")
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
