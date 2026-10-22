import SwiftUI

/// Who's in the app. The everyday build uses the comps' people. The judge's
/// build (compiled with `JUDGE_DEMO`) swaps in two made-up friends, Nora and
/// Leo, so no real person's name or photo ships in it; everyone else in it
/// is made up too.
enum DemoCast {
    #if JUDGE_DEMO
    static let isJudge = true
    #else
    static let isJudge = false
    #endif

    /// The name and email the app assumes before you've typed your own.
    static var placeholderName: String { isJudge ? "You" : "Amber" }

    // MARK: - The two friends

    static let nora = KithContact(name: "Nora Patel", face: initials("Nora Patel", .rose))
    static let leo = KithContact(name: "Leo Ortiz", face: initials("Leo Ortiz", .sky))

    /// Initials on one of the blob colours, the app's face for someone without a photo.
    static func initials(_ name: String, _ blob: FriendBlob) -> KithContact.Face {
        let letters = name.split(separator: " ").compactMap(\.first).map(String.init).joined()
        return .initials(letters, background: blob.color, ink: KithTheme.ink(false))
    }

    // MARK: - Home

    static let nudges: [TodayNudge] = [
        TodayNudge(
            contact: nora,
            seen: "You saw them at Vienna Cafe yesterday.",
            free: [
                .today: "You’re both free at 4:00 PM.",
                .thisWeek: "You’re both free Wednesday at 4:00 PM."
            ],
            idea: "grab a coffee?",
            outing: .coffee,
            place: "Vienna Cafe"
        ),
        TodayNudge(
            contact: leo,
            seen: "You saw them at the climbing gym on Sunday.",
            free: [
                .today: "You’re both free at 7:30 PM.",
                .tomorrow: "You’re both free at 6:00 PM.",
                .thisWeek: "You’re both free Friday evening."
            ],
            idea: "split a plate of fries?",
            outing: .fries
        )
    ]

    /// Your history with them. The newest is the one Home asks about; the
    /// counts line up with Recaps (Nora 3 this week and 9 this month, Leo 2 and 6).
    static let hangouts: [RecentHangout] = {
        var hangouts = [
            RecentHangout(
                contact: nora,
                title: "Coffee with Nora",
                detail: "Monday · 2 hours · Eleventh House",
                startTime: "9 AM",
                place: "Eleventh House, Lafayette",
                visitsThisMonth: 3,
                photos: [.asset("MeetupPhotoPlant"), .asset("MeetupPhotoDrink"), .asset("MeetupPhotoCafe")],
                highlightIn: [.month]
            ),
            RecentHangout(
                contact: leo,
                title: "Climbing with Leo",
                detail: "Sunday · 1 hr 30 min · Climbing gym",
                startTime: "4 PM",
                place: "Climbing gym, Lafayette",
                feelings: [.energized, .connected],
                reflection: "we finally got the purple route. leo talked me through the last move and i didn’t fall for once",
                highlightIn: [.week],
                date: RecentHangout.daysAgo(1)
            ),
            RecentHangout(
                contact: nora,
                title: "Dinner with Nora",
                detail: "Saturday · 1 hr 20 min · Home",
                startTime: "7 PM",
                place: "Home",
                feelings: [.atEase],
                highlightIn: [.week, .month],
                date: RecentHangout.daysAgo(2)
            )
        ]
        let plans = [
            ("Lunch", "12 PM", "1 hour", "Purdue Memorial Union"),
            ("Walk", "5 PM", "45 min", "Celery Bog"),
            ("Study session", "3 PM", "2 hours", "Hicks Library"),
            ("Coffee", "10 AM", "1 hr 10 min", "Vienna Cafe")
        ]
        let days = ["Friday", "Thursday", "Wednesday", "Tuesday"]
        // Older ones are all answered; unanswered, they'd have dropped out.
        let answered: [Set<Feeling>] = [[.connected], [.atEase], [.energized], [.atEase, .connected]]
        var step = 0
        for (contact, count) in [(nora, 7), (leo, 5)] {
            for _ in 0..<count {
                let plan = plans[step % plans.count]
                hangouts.append(RecentHangout(
                    contact: contact,
                    title: "\(plan.0) with \(contact.firstName)",
                    detail: "\(days[step % days.count]) · \(plan.2) · \(plan.3)",
                    startTime: plan.1,
                    place: "\(plan.3), Lafayette",
                    photos: RecentHangout.photos(at: plan.3, seed: step),
                    feelings: answered[step % answered.count],
                    date: RecentHangout.daysAgo(3 + step)
                ))
                step += 1
            }
        }
        return hangouts
    }()

    // MARK: - Friends

    static let circle: [KithContact] = [nora, leo]

    /// Nora and Leo are the judge's only friends, so there are no requests.
    static let requests: [FriendRequest] = []

    /// People in the judge's contacts who aren't on Bloom yet, to invite over
    /// Messages, so Friends doesn't sit empty. All made up, and none of them
    /// a friend: inviting one sends a text, it doesn't add them.
    static let invitees: [FriendSuggestion] = [
        ("Maya Lindqvist", FriendBlob.apricot, Connection.friendsWith("Nora")),
        ("Jonah Reyes", .turquoise, .friendsWith("Leo")),
        ("Ava Okafor", .lavender, .note("In your contacts")),
        ("Ravi Menon", .lime, .friendsWith("Nora", andOthers: true)),
        ("Clara Duval", .coral, .note("In your contacts")),
        ("Owen Park", .mint, .friendsWith("Leo")),
        ("Isla Moreno", .butter, .note("In your contacts")),
        ("Theo Brandt", .periwinkle, .note("In your contacts"))
    ].map { name, blob, connection in
        FriendSuggestion(
            contact: KithContact(name: name, face: initials(name, blob), isOnKith: false),
            connection: connection
        )
    }

    static let mutuals = ["Nora", "Leo"]

    // MARK: - Onboarding

    /// "Find your friends": just Nora and Leo, both on Bloom.
    static let onboardingFriends: [Friend] = [
        Friend(name: "Nora Patel", face: .tint(FriendBlob.rose.color), isOnKith: true),
        Friend(name: "Leo Ortiz", face: .tint(FriendBlob.sky.color), isOnKith: true)
    ]
}
