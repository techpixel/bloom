import SwiftUI

// The onboarding mascot. One shape that follows you through the flow: it starts
// as a bare wireframe circle, gains its four points once you've told us who you
// are, fills with mint, then becomes the icon for whatever we're asking for.
//
// Every figure below is the same data — three lobes, each a closed curve through
// 64 polar samples — so any figure morphs into any other by interpolating
// numbers. That keeps the blob a single continuous object across the whole flow
// instead of a series of cross-faded pictures.

/// One soft lobe. Slots 0 and 1 are solid and slots 2 and 3 are holes, and the
/// two kinds are wound in opposite directions so a non-zero fill unions the
/// solids and carves the holes. Keeping the kinds in fixed slots is what lets a
/// solid (the person's head) and a hole (the pin's eye) sit in one figure
/// without either flipping meaning part-way through a morph.
struct BlobLobe {
    /// Position in unit space, where (0.5, 0.5) is the middle of the frame.
    var center: CGPoint
    /// Radius as a fraction of the frame, before `radii` shapes it.
    var scale: CGFloat
    /// `BlobFigure.sampleCount` radii, normalized so the widest is 1.
    var radii: [CGFloat]

    static func lerp(_ a: BlobLobe, _ b: BlobLobe, _ t: CGFloat) -> BlobLobe {
        BlobLobe(
            center: CGPoint(
                x: a.center.x + (b.center.x - a.center.x) * t,
                y: a.center.y + (b.center.y - a.center.y) * t
            ),
            scale: a.scale + (b.scale - a.scale) * t,
            radii: zip(a.radii, b.radii).map { $0 + ($1 - $0) * t }
        )
    }

    /// A lobe that contributes nothing, parked where it will grow from.
    static func hidden(at center: CGPoint) -> BlobLobe {
        BlobLobe(center: center, scale: 0, radii: BlobFigure.radii { _ in 1 })
    }
}

struct BlobFigure {
    /// Always `lobeCount`, so every figure interpolates against every other one.
    var lobes: [BlobLobe]

    static let sampleCount = 64
    /// Slots 0–1 solid, slots 2–3 holes.
    static let lobeCount = 4
    static let firstHoleSlot = 2

    static func lerp(_ a: BlobFigure, _ b: BlobFigure, _ t: CGFloat) -> BlobFigure {
        BlobFigure(lobes: zip(a.lobes, b.lobes).map { BlobLobe.lerp($0, $1, t) })
    }

    /// Samples a polar radius function at `sampleCount` angles. Angles run
    /// clockwise from the positive x-axis, matching SwiftUI's y-down space.
    static func radii(_ shape: (CGFloat) -> CGFloat) -> [CGFloat] {
        (0..<sampleCount).map { shape(2 * .pi * CGFloat($0) / CGFloat(sampleCount)) }
    }

    // MARK: - The figures

    /// Hand-drawn circle: the wireframe you start on.
    static let circle = BlobFigure(lobes: [
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.5),
            scale: 0.47,
            radii: radii { 1 + 0.014 * sin($0 * 9) + 0.009 * sin($0 * 14 + 1.2) }
        ),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5))
    ])

    /// A seed, where Bloom starts you off: a plump oval, tilted a little,
    /// drawn to a soft point at the top where it'll sprout.
    static let seed = BlobFigure(lobes: [
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.54),
            scale: 0.44,
            radii: radii { angle in
                let turned = angle - 0.28
                let oval = 1 / sqrt(pow(cos(turned) / 0.62, 2) + pow(sin(turned) / 1.0, 2))
                let tip = 0.34 * pow(max(0, -sin(turned)), 5)
                return oval * (1 + tip) + 0.01 * sin(angle * 9)
            }
        ),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5))
    ])

    /// The Kith four-point star, sampled from the comp's own vector.
    static let star = BlobFigure(lobes: [
        BlobLobe(center: CGPoint(x: 0.5, y: 0.5), scale: 0.5, radii: starRadii),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5))
    ])

    /// Contacts: head and shoulders, the way `person.fill` draws them.
    static let person = BlobFigure(lobes: [
        // Shoulders — a wide dome with a flattened bottom edge.
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.78),
            scale: 0.34,
            radii: radii { angle in
                let ellipse = 1 / sqrt(pow(cos(angle) / 1.08, 2) + pow(sin(angle) / 0.78, 2))
                let floorY = 0.42 / max(sin(angle), 0.0001)
                return sin(angle) > 0 ? min(ellipse, floorY) : ellipse
            }
        ),
        // Head — a clear gap below it keeps the two readable as one person.
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.26),
            scale: 0.19,
            radii: radii { _ in 1 }
        ),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        .hidden(at: CGPoint(x: 0.5, y: 0.5))
    ])

    /// Background location: a map pin, point down, with its eye knocked out.
    /// The sides are the tangent lines from the tip to the round head, which is
    /// what makes it read as a pin rather than an egg.
    static let locationPin: BlobFigure = {
        let tipDistance: CGFloat = 2.0
        let tangentAngle = acos(1 / tipDistance)

        return BlobFigure(lobes: [
            BlobLobe(
                center: CGPoint(x: 0.5, y: 0.34),
                scale: 0.29,
                radii: radii { angle in
                    var fromTip = angle - .pi / 2          // y is down, so this is the tip
                    while fromTip > .pi { fromTip -= 2 * .pi }
                    while fromTip < -.pi { fromTip += 2 * .pi }
                    guard abs(fromTip) < tangentAngle else { return 1 }
                    return 1 / cos(abs(fromTip) - tangentAngle)
                }
            ),
            .hidden(at: CGPoint(x: 0.5, y: 0.34)),
            BlobLobe(center: CGPoint(x: 0.5, y: 0.325), scale: 0.10, radii: radii { _ in 1 }),
            .hidden(at: CGPoint(x: 0.5, y: 0.5))
        ])
    }()

    /// Photos: a squircle frame with a sun and a hill knocked out of it.
    static let photos = BlobFigure(lobes: [
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.5),
            scale: 0.45,
            radii: radii { angle in
                let n: CGFloat = 4
                return pow(pow(abs(cos(angle)), n) + pow(abs(sin(angle)), n), -1 / n)
            }
        ),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        BlobLobe(center: CGPoint(x: 0.33, y: 0.34), scale: 0.075, radii: radii { _ in 1 }),
        // The mountain in a photo glyph.
        BlobLobe(
            center: CGPoint(x: 0.54, y: 0.72),
            scale: 0.23,
            radii: convexPolygon([
                CGPoint(x: 0, y: -1.0),
                CGPoint(x: 1.0, y: 0.55),
                CGPoint(x: -1.0, y: 0.55)
            ])
        )
    ])

    /// Calendar: the same squircle as the photo frame, with a slit under its
    /// header and one day picked out, so the photo glyph flows straight into it.
    static let calendar = BlobFigure(lobes: [
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.5),
            scale: 0.45,
            radii: radii { angle in
                let n: CGFloat = 4
                return pow(pow(abs(cos(angle)), n) + pow(abs(sin(angle)), n), -1 / n)
            }
        ),
        .hidden(at: CGPoint(x: 0.5, y: 0.5)),
        // The line under the month.
        BlobLobe(
            center: CGPoint(x: 0.5, y: 0.34),
            scale: 0.31,
            radii: convexPolygon([
                CGPoint(x: -1, y: -0.09),
                CGPoint(x: 1, y: -0.09),
                CGPoint(x: 1, y: 0.09),
                CGPoint(x: -1, y: 0.09)
            ])
        ),
        // Today.
        BlobLobe(
            center: CGPoint(x: 0.62, y: 0.62),
            scale: 0.1,
            radii: convexPolygon([
                CGPoint(x: -1, y: -1),
                CGPoint(x: 1, y: -1),
                CGPoint(x: 1, y: 1),
                CGPoint(x: -1, y: 1)
            ])
        )
    ])

    /// Radius profile of a convex polygon that contains the origin. Lets a lobe
    /// be an exact straight-edged shape rather than an approximation of one.
    static func convexPolygon(_ vertices: [CGPoint]) -> [CGFloat] {
        radii { angle in
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            var nearest = CGFloat.greatestFiniteMagnitude

            for index in vertices.indices {
                let a = vertices[index]
                let b = vertices[(index + 1) % vertices.count]
                let edge = CGPoint(x: b.x - a.x, y: b.y - a.y)
                // Outward normal, then the ray's distance to that edge's line.
                let normal = CGPoint(x: edge.y, y: -edge.x)
                let along = direction.x * normal.x + direction.y * normal.y
                guard along > 0.0001 else { continue }
                nearest = min(nearest, (a.x * normal.x + a.y * normal.y) / along)
            }
            return nearest == .greatestFiniteMagnitude ? 1 : nearest
        }
    }

    /// Radii of the comp's star vector, measured from its area centroid.
    private static let starRadii: [CGFloat] = [
        0.6208, 0.6553, 0.7045, 0.7643, 0.8267, 0.8871, 0.9380, 0.9721,
        0.9850, 0.9783, 0.9285, 0.8027, 0.6453, 0.5573, 0.5152, 0.4966,
        0.4938, 0.5046, 0.5307, 0.5779, 0.6572, 0.7720, 0.8820, 0.9479,
        0.9331, 0.8558, 0.7665, 0.6914, 0.6389, 0.6028, 0.5836, 0.5795,
        0.5911, 0.6198, 0.6680, 0.7349, 0.8072, 0.8760, 0.9377, 0.9841,
        1.0000, 0.9480, 0.8535, 0.7561, 0.6808, 0.6309, 0.6008, 0.5860,
        0.5844, 0.5960, 0.6230, 0.6677, 0.7178, 0.7742, 0.8350, 0.8800,
        0.8805, 0.8185, 0.7302, 0.6619, 0.6212, 0.5992, 0.5929, 0.6002
    ]
}

/// Where the blob is in the flow. Stages are adjacent in the order the user
/// meets them, so `BlobShape` only ever interpolates between neighbours.
enum BlobStage: CGFloat {
    case circle = 0
    case star = 1
    case starFilled = 2
    case person = 3
    case locationPin = 4
    case photos = 5
    case calendar = 6
    case starSmall = 7
}

/// The blob's outline at a fractional stage. Animating `stage` morphs the shape.
/// `time` and `ripple` keep the edge alive: two slow waves run round every lobe,
/// at every stage, so the blob ripples before, during and after a morph.
struct BlobShape: Shape {
    var stage: CGFloat
    /// Seconds; drives the waves along the edge.
    var time: Double = 0
    /// Wave height. 1 is the resting wobble; a keystroke briefly raises it.
    var ripple: CGFloat = 0

    var animatableData: CGFloat {
        get { stage }
        set { stage = newValue }
    }

    /// Stage index → figure. Repeats are intentional: the star's shape is reused
    /// across several screens that only differ in color or size.
    private static let table: [BlobFigure] = [
        .seed, .star, .star, .person, .locationPin, .photos, .calendar, .star
    ]

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(stage, 0), CGFloat(Self.table.count - 1))
        let low = Int(clamped.rounded(.down))
        let high = min(low + 1, Self.table.count - 1)
        let figure = BlobFigure.lerp(Self.table[low], Self.table[high], clamped - CGFloat(low))

        var path = Path()
        for (slot, lobe) in figure.lobes.enumerated() where lobe.scale > 0.0005 {
            path.addPath(Self.lobePath(lobe, in: rect, isHole: slot >= BlobFigure.firstHoleSlot, wave: wave(seed: CGFloat(slot))))
        }
        return path
    }

    /// The edge's offset at an angle, as a fraction of the radius: a three-crest
    /// wave and a five-crest wave travelling opposite ways, about 2% tall at rest.
    private func wave(seed: CGFloat) -> (CGFloat) -> CGFloat {
        let t = CGFloat(time)
        let height = 0.022 * ripple
        return { angle in
            height * (0.6 * sin(angle * 3 + t * 0.9 + seed) + 0.4 * sin(angle * 5 - t * 0.7 + seed * 1.7))
        }
    }

    private static func lobePath(_ lobe: BlobLobe, in rect: CGRect, isHole: Bool, wave: (CGFloat) -> CGFloat) -> Path {
        var points = lobe.radii.enumerated().map { index, radius -> CGPoint in
            let angle = 2 * .pi * CGFloat(index) / CGFloat(BlobFigure.sampleCount)
            let rippled = radius * (1 + wave(angle))
            return CGPoint(
                x: rect.minX + (lobe.center.x + lobe.scale * rippled * cos(angle)) * rect.width,
                y: rect.minY + (lobe.center.y + lobe.scale * rippled * sin(angle)) * rect.height
            )
        }
        // Opposite winding is what makes a hole a hole under the non-zero rule.
        if isHole { points.reverse() }
        return closedCurve(through: points)
    }

    /// Catmull-Rom through every sample, so 64 points read as one smooth curve.
    private static func closedCurve(through points: [CGPoint]) -> Path {
        var path = Path()
        let count = points.count
        guard count > 3 else { return path }

        path.move(to: points[0])
        for index in 0..<count {
            let previous = points[(index - 1 + count) % count]
            let start = points[index]
            let end = points[(index + 1) % count]
            let next = points[(index + 2) % count]

            path.addCurve(
                to: end,
                control1: CGPoint(
                    x: start.x + (end.x - previous.x) / 6,
                    y: start.y + (end.y - previous.y) / 6
                ),
                control2: CGPoint(
                    x: end.x - (next.x - start.x) / 6,
                    y: end.y - (next.y - start.y) / 6
                )
            )
        }
        path.closeSubpath()
        return path
    }
}

/// The blob as it appears on screen: a wireframe outline early on, a mint mass
/// later. Both are drawn every time and cross-faded, so the fill arriving is its
/// own moment rather than a hard swap. Its edge ripples the whole time it's on
/// screen, and each `pulse` (a keystroke) sends a bigger ripple through it.
struct KithBlob: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var pulseDate: Date?

    var stage: CGFloat
    var fill: Color
    var stroke: Color
    /// 0 = wireframe, 1 = solid.
    var fillAmount: CGFloat
    /// Bump this to ripple the edge, e.g. once per character typed.
    var pulse = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let ripple = reduceMotion ? 0 : 1 + boost(at: context.date)

            let shape = BlobShape(stage: stage, time: time, ripple: ripple)

            ZStack {
                // The welcome logo's old treatment: crisp on the left, melting
                // into blur on the right, with grain over both.
                ZStack {
                    shape
                        .fill(fill)
                        .mask(LinearGradient(
                            stops: [.init(color: .black, location: 0.4), .init(color: .clear, location: 0.78)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                    shape
                        .fill(fill)
                        .blur(radius: 6)
                        .opacity(0.86)
                        .mask(LinearGradient(
                            stops: [.init(color: .clear, location: 0.36), .init(color: .black, location: 0.74)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                }
                .padding(14)
                .colorEffect(ShaderLibrary.grain(.float(Float(displayScale)), .float(0.14)))
                .padding(-14)
                .opacity(Double(fillAmount))

                shape
                    .stroke(stroke.opacity(Double(1 - fillAmount)), lineWidth: 1)
            }
            // A slow breathe on top of the ripple.
            .scaleEffect(
                x: 1 + 0.012 * CGFloat(sin(time * 0.42)),
                y: 1 + 0.012 * CGFloat(cos(time * 0.35))
            )
            .rotationEffect(.degrees(1.6 * sin(time * 0.22)))
        }
        .onChange(of: pulse) { pulseDate = .now }
    }

    /// Extra ripple from the last pulse: up to 1.8× more, gone after 0.7s.
    private func boost(at date: Date) -> CGFloat {
        guard let pulseDate else { return 0 }
        let elapsed = date.timeIntervalSince(pulseDate)
        guard elapsed < 0.7 else { return 0 }
        return 1.8 * CGFloat(1 - elapsed / 0.7)
    }
}

/// The welcome screen's colour: big watercolour washes that bloom out of
/// nothing round the edges, spread and drift, then fade as others open (the
/// `watercolorBloom` shader does the painting). Holds still with Reduce Motion.
struct WatercolorBloom: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var startDate = Date()

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || scenePhase != .active)) { timeline in
                // A moment with several washes open, for the still version.
                let time = reduceMotion ? 7 : timeline.date.timeIntervalSince(startDate)
                Rectangle()
                    .fill(KithTheme.canvas(colorScheme == .dark))
                    .colorEffect(ShaderLibrary.watercolorBloom(
                        .float2(geometry.size),
                        .float(Float(time)),
                        .float(Float(displayScale)),
                        .float(colorScheme == .dark ? 1 : 0)
                    ))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
