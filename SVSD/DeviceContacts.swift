import Contacts
import UIKit

/// The phone's own contacts, offered as people to invite. Only the Release
/// build on an iPhone reads them: the Debug build you develop with never
/// touches the contacts on your phone, the judge's build has just its two
/// made-up friends, and the Mac doesn't read the Mac's.
enum DeviceContacts {
    /// On only for Celeste's build, so the demo can text real people: the
    /// user asked for real contacts there on 2026-10-21. Debug, the judge's
    /// build and the Mac stay made up.
    static var enabled: Bool {
        #if DEBUG || JUDGE_DEMO || targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }

    /// iOS hasn't been asked yet.
    static var needsAsking: Bool {
        enabled && CNContactStore.authorizationStatus(for: .contacts) == .notDetermined
    }

    /// Whether you've already let Bloom read them. Never asks.
    static var isAuthorized: Bool {
        guard enabled else { return false }
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18.0, *), status == .limited { return true }
        return status == .authorized
    }

    /// Asks once, the first time; after that it's whatever you chose.
    static func requestAccess() async -> Bool {
        guard enabled else { return false }
        if isAuthorized { return true }
        guard CNContactStore.authorizationStatus(for: .contacts) == .notDetermined else { return false }
        return (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
    }

    /// Everyone with a name, sorted by first name, with their contact photo
    /// where there is one. Nil if access isn't granted.
    static func load() async -> [KithContact]? {
        guard await requestAccess() else { return nil }
        return await Task.detached(priority: .userInitiated) { fetch() }.value
    }

    /// The same, read straight away; empty without access.
    static func fetch() -> [KithContact] {
        guard isAuthorized else { return [] }
        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]
        var people: [KithContact] = []
        var seen: Set<String> = []
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.sortOrder = .givenName
        try? CNContactStore().enumerateContacts(with: request) { contact, _ in
            let name = [contact.givenName, contact.familyName]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !name.isEmpty, seen.insert(name).inserted else { return }
            let face: KithContact.Face
            if let data = contact.thumbnailImageData, let image = UIImage(data: data) {
                face = .picture(image)
            } else {
                let letters = name.split(separator: " ").compactMap(\.first).prefix(2).map(String.init).joined()
                face = .initials(letters, background: FriendBlob.forName(name).color, ink: KithTheme.ink(false))
            }
            // A mobile number if there is one, so a text reaches a phone.
            let numbers = contact.phoneNumbers
            let phone = (numbers.first { $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone } ?? numbers.first)?
                .value.stringValue
            people.append(KithContact(name: name, face: face, isOnKith: false, phone: phone, recast: false))
        }
        return people
    }
}

/// Where Bloom reads the phone's contacts, the comps' made-up people are
/// played by real ones from it, so a demo texts real people. Anyone in the
/// phone under a part's own name plays it; Amber Zeng and Michelle Xuan are
/// always in when the phone has them; people with a photo and a number go
/// first, so the prominent parts look and work like friends.
enum Recast {
    /// Every made-up person in the app, most prominent first.
    private static let cast = [
        "Manitej Boorgu", "Michelle Xuan", "Ishan Goyal", "Ray Arayilikath", "Jadden Picardal",
        "Dev Shah", "Theo Lindqvist", "Amara Okafor", "Nina Alvarez", "Kenji Watanabe",
        "Evan Raghunathan", "Sam Reyes", "Sofia Marchetti",
        "Alicia Zhou", "Gabriel", "Leo Chen", "Mia Singh", "Jordan Tan",
        "Aanya Iyer", "Ben Walsh", "Camila Diaz", "Felix Brooks", "Grace Kim", "Hiro Tanaka",
        "Isla Evans", "Jonah Park", "Maya Gupta", "Quinn Ferreira", "Rosa Mehta", "Wes Nguyen"
    ]

    /// Always cast when they're in the phone: a first name, the start of the
    /// last, and the part they get if it's free.
    private static let pinned = [
        (first: "amber", last: "z", part: "Manitej Boorgu"),
        (first: "michelle", last: "x", part: "Michelle Xuan")
    ]

    /// Part → the real person playing it.
    private(set) static var people: [String: KithContact] = [:]
    /// A part's first name → the real person's, for lines that name them.
    private static var firstNames: [String: String] = [:]

    static var isActive: Bool { !people.isEmpty }

    static func person(playing part: String) -> KithContact? {
        people[part]
    }

    /// Casts everyone from the phone's contacts, once, if Bloom may read
    /// them. Runs at launch and again when onboarding is given access, before
    /// any of the sample people are made.
    static func prepare() {
        guard DeviceContacts.enabled, people.isEmpty, DeviceContacts.isAuthorized else { return }
        let pool = DeviceContacts.fetch()
        guard !pool.isEmpty else { return }

        var parts: [String: KithContact] = [:]
        var used: Set<String> = []
        func give(_ part: String, to person: KithContact) {
            parts[part] = person
            used.insert(person.name)
        }

        for part in cast {
            if let same = pool.first(where: { $0.name.lowercased() == part.lowercased() }) {
                give(part, to: same)
            }
        }
        for pin in pinned {
            guard let person = pool.first(where: { matches($0, first: pin.first, last: pin.last) }),
                  !used.contains(person.name),
                  let part = parts[pin.part] == nil ? pin.part : cast.first(where: { parts[$0] == nil })
            else { continue }
            give(part, to: person)
        }

        // Photo and number first, then a number, then a photo, then anyone;
        // a first name nobody else has yet before a repeat, since the app
        // often goes by first names.
        func rank(_ person: KithContact) -> Int {
            let hasPhoto: Bool
            if case .picture = person.face { hasPhoto = true } else { hasPhoto = false }
            switch (hasPhoto, person.phone != nil) {
            case (true, true): return 0
            case (false, true): return 1
            case (true, false): return 2
            case (false, false): return 3
            }
        }
        var firsts = Set(parts.values.map { $0.firstName.lowercased() })
        var rest = pool.enumerated()
            .filter { !used.contains($0.element.name) }
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
        for part in cast where parts[part] == nil {
            guard !rest.isEmpty else { break }
            let index = rest.firstIndex { !firsts.contains($0.firstName.lowercased()) } ?? 0
            let person = rest.remove(at: index)
            firsts.insert(person.firstName.lowercased())
            give(part, to: person)
        }

        people = parts
        firstNames = Dictionary(
            parts.map { (String($0.key.split(separator: " ").first ?? ""), $0.value.firstName) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// A line with the comps' first names swapped for the real people's.
    static func text(_ line: String) -> String {
        guard isActive, !firstNames.isEmpty else { return line }
        let names = firstNames.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:))
        guard let pattern = try? NSRegularExpression(pattern: "\\b(\(names.joined(separator: "|")))\\b") else { return line }
        var result = line
        for match in pattern.matches(in: line, range: NSRange(line.startIndex..., in: line)).reversed() {
            guard let range = Range(match.range, in: result), let real = firstNames[String(result[range])] else { continue }
            result.replaceSubrange(range, with: real)
        }
        return result
    }

    private static func matches(_ person: KithContact, first: String, last: String) -> Bool {
        let words = person.name.lowercased().split(separator: " ")
        guard words.count >= 2, words[0] == first else { return false }
        return words.dropFirst().contains { $0.hasPrefix(last) }
    }
}
