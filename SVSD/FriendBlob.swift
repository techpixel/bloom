import SwiftUI

/// The twelve blobs from the comp ("12 unique blobs · matched saturation").
/// Every friend gets one, picked from their name so it never changes, and it
/// follows them around the app: the halo behind their face, their colour in the
/// Today backdrop, the plate behind their initials.
enum FriendBlob: String, CaseIterable {
    case lavender, apricot, turquoise, rose, lime, sky, coral, mint, butter, periwinkle, leaf, orchid

    /// Each export is rasterised from the comp's own SVG; its grain and blur are
    /// filters the asset catalog can't draw.
    var asset: String { "Blob" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// The comp's gradient colour for this blob.
    var color: Color {
        switch self {
        case .lavender: return Color(red: 0.698, green: 0.545, blue: 0.914)   // #B28BE9
        case .apricot: return Color(red: 0.914, green: 0.698, blue: 0.545)    // #E9B28B
        case .turquoise: return Color(red: 0.545, green: 0.914, blue: 0.882)  // #8BE9E1
        case .rose: return Color(red: 0.914, green: 0.545, blue: 0.761)       // #E98BC2
        case .lime: return Color(red: 0.761, green: 0.914, blue: 0.545)       // #C2E98B
        case .sky: return Color(red: 0.545, green: 0.761, blue: 0.914)        // #8BC2E9
        case .coral: return Color(red: 0.914, green: 0.545, blue: 0.576)      // #E98B93
        case .mint: return Color(red: 0.545, green: 0.914, blue: 0.698)       // #8BE9B2
        case .butter: return Color(red: 0.914, green: 0.882, blue: 0.545)     // #E9E18B
        case .periwinkle: return Color(red: 0.545, green: 0.576, blue: 0.914) // #8B93E9
        case .leaf: return Color(red: 0.576, green: 0.914, blue: 0.545)       // #93E98B
        case .orchid: return Color(red: 0.882, green: 0.545, blue: 0.914)     // #E18BE9
        }
    }

    /// The export's size in points, blur bleed included.
    var size: CGSize {
        switch self {
        case .lavender: return CGSize(width: 131.466, height: 128.911)
        case .apricot: return CGSize(width: 179, height: 179)
        case .turquoise: return CGSize(width: 182, height: 182)
        case .rose: return CGSize(width: 171.26, height: 171.26)
        case .lime: return CGSize(width: 173.361, height: 166.349)
        case .sky: return CGSize(width: 196, height: 128)
        case .coral: return CGSize(width: 142.704, height: 142.704)
        case .mint: return CGSize(width: 167.574, height: 174.27)
        case .butter: return CGSize(width: 195, height: 136)
        case .periwinkle: return CGSize(width: 176, height: 187)
        case .leaf: return CGSize(width: 160, height: 190)
        case .orchid: return CGSize(width: 158.45, height: 152.631)
        }
    }

    /// FNV-1a over the name. Swift's own hashing is reseeded every launch, which
    /// would hand people a new blob each time.
    static func forName(_ name: String) -> FriendBlob {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return allCases[Int(hash % UInt64(allCases.count))]
    }
}

extension KithContact {
    var blob: FriendBlob { .forName(name) }
}

/// A friend's blob, drifting. The movement is slow and small — whole cycles take
/// the better part of a minute — so it reads as alive without ever pulling your
/// eye. It holds still when Reduce Motion is on.
struct DriftingBlob: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let blob: FriendBlob
    /// The blob's longest side, in points.
    var length: CGFloat
    /// Offsets the drift so no two blobs move in step.
    var seed: Double = 0
    /// How far it wanders, as a fraction of its size.
    var wander: CGFloat = 0.05

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            image
                .rotationEffect(.degrees(6 * sin(time * 0.09 + seed)))
                .scaleEffect(1 + 0.05 * sin(time * 0.13 + seed * 1.7))
                .offset(
                    x: length * wander * sin(time * 0.07 + seed * 2.3),
                    y: length * wander * cos(time * 0.06 + seed * 0.9)
                )
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var image: some View {
        let natural = blob.size
        let fit = length / max(natural.width, natural.height)
        return Image(blob.asset)
            .resizable()
            .frame(width: natural.width * fit, height: natural.height * fit)
    }
}
