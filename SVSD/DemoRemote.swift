import Foundation
import Network
import UserNotifications

/// Lets a Mac on the same Wi-Fi drive a live demo: it can make Home ask
/// "Did you meet with…?" or "How did your time with… feel?" on cue, as if
/// Bloom had just noticed. Bloom listens while it's open, advertised over
/// Bonjour as `_bloom-demo._tcp`; `scripts/bloom-remote.py` sends the
/// commands. Left out of the judge's build and the Mac.
///
/// A command is a small HTTP POST with a JSON body:
///     {"kind": "sighting", "friend": "Ishan", "place": "Vienna Cafe, Lafayette", "when": "Just now"}
///     {"kind": "reflect", "friend": "Manitej", "activity": "Lunch", "place": "Purdue Memorial Union"}
///     {"kind": "name", "visits": 3}   offers to name the place on the open entry
///     {"kind": "friends"}   answers with the friends' names, one a line
///     {"kind": "notify", "title": "Ishan is nearby", "body": "You’re both near Hicks Library.", "delay": 10}
final class DemoRemote: @unchecked Sendable {
    static let shared = DemoRemote()
    static let serviceType = "_bloom-demo._tcp"
    static let port: NWEndpoint.Port = 7777

    /// Set by the main tabs while they're on screen: applies a command and
    /// says what went wrong, if anything. Nil during onboarding.
    @MainActor var handler: (([String: Any]) -> String?)?
    /// Also set by the main tabs: everyone a command can name.
    @MainActor var friends: (() -> [String])?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "bloom.demo-remote")

    func start() {
        #if !JUDGE_DEMO && !targetEnvironment(macCatalyst)
        guard listener == nil else { return }
        // The remote can post notifications, so iOS asks now rather than
        // mid-demo. After the first time, this does nothing.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        do {
            let listener = try NWListener(using: .tcp, on: Self.port)
            // The simulator gets its own name, so the remote finds the phone.
            #if targetEnvironment(simulator)
            let name = "Bloom Simulator"
            #else
            let name = "Bloom"
            #endif
            listener.service = NWListener.Service(name: name, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            // If the network drops out from under it, start over a moment later.
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.listener?.cancel()
                    self?.listener = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self?.start() }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            // No listener means no remote; the app itself is unaffected.
        }
        #endif
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Reads until the whole request (headers plus Content-Length) is in.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = Self.parse(buffer) {
                let (ok, body) = self.dispatch(request)
                self.reply(on: connection, ok: ok, body: body)
            } else if done || error != nil || buffer.count > 65_536 {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    /// The JSON body of a complete HTTP request, or nil if more is coming.
    private static func parse(_ data: Data) -> [String: Any]? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<split.lowerBound], as: UTF8.self)
        let length = head.split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        let json = (try? JSONSerialization.jsonObject(with: body.prefix(length))) as? [String: Any]
        return json ?? [:]
    }

    /// Runs the command on the main thread and waits for the answer; this
    /// queue is never the main one, so the wait can't deadlock.
    private func dispatch(_ request: [String: Any]) -> (ok: Bool, body: String) {
        guard let kind = request["kind"] as? String, ["sighting", "reflect", "reset", "name", "friends", "notify"].contains(kind) else {
            return (false, "Unknown command. Use sighting, reflect, reset, name, friends or notify.")
        }
        // Works from anywhere, onboarding included: it's the phone's, not a screen's.
        if kind == "notify" { return Self.notify(request) }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                guard let handler, let friends else { return (false, "Bloom is still in onboarding. Finish it, then try again.") }
                if kind == "friends" { return (true, friends().joined(separator: "\n")) }
                if let problem = handler(request) { return (false, problem) }
                return (true, "ok")
            }
        }
    }

    /// Posts a notification as if a push had come in. With a delay it still
    /// lands once the phone is locked or Bloom is in the background, when
    /// the remote itself can't reach it. Runs on the remote's queue, so
    /// waiting on the notification center here never blocks the app.
    private static func notify(_ request: [String: Any]) -> (ok: Bool, body: String) {
        let title = (request["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = (request["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !body.isEmpty else { return (false, "A notification needs a title or a message.") }

        let center = UNUserNotificationCenter.current()
        let done = DispatchSemaphore(value: 0)
        var allowed = false
        center.getNotificationSettings { settings in
            allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
            done.signal()
        }
        done.wait()
        guard allowed else {
            return (false, "Notifications are off for Bloom. Turn them on in Settings › Notifications › Bloom.")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let delay = max(0, request["delay"] as? Double ?? 0)
        let trigger = delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) : nil
        var failure: Error?
        center.add(UNNotificationRequest(identifier: "remote-\(UUID().uuidString)", content: content, trigger: trigger)) { error in
            failure = error
            done.signal()
        }
        done.wait()
        if let failure { return (false, "Couldn’t post it: \(failure.localizedDescription)") }
        return (true, delay > 0 ? "ok, in \(Int(delay)) seconds" : "ok")
    }

    private func reply(on connection: NWConnection, ok: Bool, body: String) {
        let body = body + "\n"
        let status = ok ? "200 OK" : "400 Bad Request"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
