import SwiftUI

/// A span of a single day, measured in fractional hours past midnight (13.5 == 1:30PM).
struct AvailabilityWindow: Equatable, Identifiable {
    var start: Double
    var end: Double

    var id: String { "\(start)-\(end)" }
    var isEmpty: Bool { end <= start }
}

extension Array where Element == AvailabilityWindow {
    /// Sorted, with touching or overlapping windows collapsed into one.
    var merged: [AvailabilityWindow] {
        var out: [AvailabilityWindow] = []
        for window in filter({ !$0.isEmpty }).sorted(by: { $0.start < $1.start }) {
            if let last = out.last, window.start <= last.end {
                out[out.count - 1].end = Swift.max(last.end, window.end)
            } else {
                out.append(window)
            }
        }
        return out
    }

    /// Every span covered by either side — the light green bands.
    func union(_ other: [AvailabilityWindow]) -> [AvailabilityWindow] {
        (self + other).merged
    }

    /// Everything in `self` that `cut` does not cover.
    func subtracting(_ cut: AvailabilityWindow) -> [AvailabilityWindow] {
        guard !cut.isEmpty else { return merged }
        var out: [AvailabilityWindow] = []
        for window in merged {
            if cut.end <= window.start || cut.start >= window.end {
                out.append(window)
                continue
            }
            if cut.start > window.start {
                out.append(AvailabilityWindow(start: window.start, end: cut.start))
            }
            if cut.end < window.end {
                out.append(AvailabilityWindow(start: cut.end, end: window.end))
            }
        }
        return out
    }

    /// The window containing `hour`, if any.
    func window(containing hour: Double) -> AvailabilityWindow? {
        merged.first { hour >= $0.start && hour <= $0.end }
    }

    /// Every span covered by both sides — the dark green bands.
    func intersection(_ other: [AvailabilityWindow]) -> [AvailabilityWindow] {
        var out: [AvailabilityWindow] = []
        for mine in merged {
            for theirs in other.merged {
                let start = Swift.max(mine.start, theirs.start)
                let end = Swift.min(mine.end, theirs.end)
                if end > start { out.append(AvailabilityWindow(start: start, end: end)) }
            }
        }
        return out.merged
    }
}

/// The scrubbable day strip. Drag horizontally to move through the day.
struct AvailabilityTimeline: View {
    /// How the bands read.
    enum Style {
        /// Light green where either person is free, dark green where both are.
        case overlap
        /// Neutral where both are free, with one green slot you can resize.
        case slotPicker
    }

    @Environment(\.colorScheme) private var colorScheme

    let mine: [AvailabilityWindow]
    let theirs: [AvailabilityWindow]
    /// Hour parked against the left edge when the strip first appears.
    var initialHour: Double = 9
    var style: Style = .overlap
    /// The chosen slot, in `.slotPicker` style. Its handles write back here.
    var slot: Binding<AvailabilityWindow>?

    /// Quarter-hour steps, with a floor so a slot can never collapse to nothing.
    private let snap: Double = 0.25
    private let minimumSlot: Double = 0.5
    private let trackSpace = "availability-track"

    /// Distance between the finger and the edge it grabbed, so the slot never jumps.
    @State private var grabOffset: Double?
    /// Set on touch-down on a handle, which switches the scroll pan off for the
    /// duration — otherwise the strip would scroll instead of resizing the slot.
    @State private var isAdjustingSlot = false

    private let dayStart: Double = 0
    private let dayEnd: Double = 24
    private let hourWidth: CGFloat = 25.23
    private let trackHeight: CGFloat = 52
    private let corner: CGFloat = 12
    private let leadInset: CGFloat = 12.5
    private let labelGap: CGFloat = 8
    private let labelHeight: CGFloat = 14

    private var isDark: Bool { colorScheme == .dark }
    private var tickHours: [Int] { Array(Int(dayStart)..<Int(dayEnd)) }
    private var contentWidth: CGFloat { x(dayEnd - 1) + leadInset }
    private var unionWindows: [AvailabilityWindow] { mine.union(theirs) }
    private var overlapWindows: [AvailabilityWindow] { mine.intersection(theirs) }

    /// In `.slotPicker`, the bands are the shared time and the slot is cut out of them.
    private var bandWindows: [AvailabilityWindow] {
        switch style {
        case .overlap:
            return unionWindows
        case .slotPicker:
            guard let slot else { return overlapWindows }
            return overlapWindows.subtracting(slot.wrappedValue)
        }
    }

    private var bandFill: Color {
        style == .overlap ? KithTheme.availability : KithTheme.suggestionCard(isDark)
    }

    private var tickFill: Color {
        style == .overlap ? KithTheme.timelineTick(isDark) : KithTheme.ink(isDark).opacity(0.05)
    }

    private var hourLabelFill: Color {
        style == .overlap ? KithTheme.secondary(isDark) : KithTheme.ink(isDark)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(KithTheme.timelineTrack(isDark))
                .frame(height: trackHeight)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: labelGap) {
                        track
                        hourLabels
                    }
                }
                .scrollDisabled(isAdjustingSlot)
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .frame(height: trackHeight)
                        Rectangle()
                    }
                }
                .onAppear {
                    DispatchQueue.main.async {
                        proxy.scrollTo(scrollAnchorID, anchor: .leading)
                    }
                }
            }
        }
        .frame(height: trackHeight + labelGap + labelHeight)
        .accessibilityElement(children: style == .slotPicker ? .contain : .ignore)
        .accessibilityLabel("Shared Availability")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint(
            style == .slotPicker
                ? "Swipe horizontally to see the rest of the day, or drag a handle to change the time"
                : "Swipe horizontally to see the rest of the day"
        )
    }

    private var track: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tickHours, id: \.self) { hour in
                Rectangle()
                    .fill(tickFill)
                    .frame(width: 1, height: trackHeight)
                    .offset(x: x(Double(hour)) - 0.5)
            }

            ForEach(bandWindows) { window in
                band(window, fill: bandFill)
            }

            // Drawn across the full strip so the hatch stays continuous band to band.
            DiagonalHatch(spacing: 17.25, slope: 0.7)
                .stroke(KithTheme.availabilityHatch, lineWidth: 1.6)
                .frame(width: contentWidth, height: trackHeight)
                .mask { WindowsShape(rects: bandWindows.map(rect), corner: corner).fill(Color.black) }

            if style == .overlap {
                ForEach(overlapWindows) { window in
                    band(window, fill: KithTheme.overlap)
                }
            } else if let slot {
                selectedSlot(slot)
            }

            scrollAnchor
        }
        .frame(width: contentWidth, height: trackHeight, alignment: .topLeading)
        .coordinateSpace(name: trackSpace)
    }

    private var hourLabels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(tickHours, id: \.self) { hour in
                Text(Self.hourLabel(hour))
                    .font(.kithCaption)
                    .monospacedDigit()
                    .foregroundStyle(hourLabelFill)
                    .frame(width: hourWidth, height: labelHeight)
                    .offset(x: x(Double(hour)) - hourWidth / 2)
            }
        }
        .frame(width: contentWidth, height: labelHeight, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// A zero-width marker the scroll proxy can park against the leading edge.
    private var scrollAnchor: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: max(0, x(initialHour) - leadInset), height: 1)
            Color.clear.frame(width: 1, height: 1).id(scrollAnchorID)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
    }

    private var scrollAnchorID: String { "availability-start" }

    @ViewBuilder
    private func selectedSlot(_ slot: Binding<AvailabilityWindow>) -> some View {
        let window = slot.wrappedValue
        let box = rect(window)

        band(window, fill: KithTheme.availability)

        handle(slot, edge: .start).offset(x: box.minX + 4)
        handle(slot, edge: .end).offset(x: box.maxX - 7)
    }

    private enum SlotEdge { case start, end }

    /// A 3pt grip with a 44pt invisible target, so the thumb has something to find.
    private func handle(_ slot: Binding<AvailabilityWindow>, edge: SlotEdge) -> some View {
        Capsule()
            .fill(KithTheme.slotHandle)
            .frame(width: 3, height: 20)
            .frame(width: 44, height: trackHeight)
            .contentShape(Rectangle())
            .offset(x: -20.5)
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(trackSpace))
                    .onChanged { value in
                        isAdjustingSlot = true
                        let touched = hour(atX: value.location.x)
                        let anchor = edge == .start ? slot.wrappedValue.start : slot.wrappedValue.end
                        let offset = grabOffset ?? (touched - anchor)
                        if grabOffset == nil { grabOffset = offset }
                        apply(slot, edge: edge, to: touched - offset)
                    }
                    .onEnded { _ in
                        grabOffset = nil
                        isAdjustingSlot = false
                    }
            )
            .accessibilityLabel(edge == .start ? "Start time" : "End time")
            .accessibilityValue(Self.timeLabel(edge == .start ? slot.wrappedValue.start : slot.wrappedValue.end))
            .accessibilityAdjustableAction { direction in
                let anchor = edge == .start ? slot.wrappedValue.start : slot.wrappedValue.end
                apply(slot, edge: edge, to: anchor + (direction == .increment ? snap : -snap))
            }
    }

    /// Snaps to the quarter hour and keeps the slot inside one shared window.
    private func apply(_ slot: Binding<AvailabilityWindow>, edge: SlotEdge, to hour: Double) {
        let current = slot.wrappedValue
        let bounds = overlapWindows.window(containing: (current.start + current.end) / 2)
            ?? AvailabilityWindow(start: dayStart, end: dayEnd)
        let snapped = (hour / snap).rounded() * snap

        switch edge {
        case .start:
            let limit = min(current.end - minimumSlot, bounds.end - minimumSlot)
            slot.wrappedValue.start = min(max(snapped, bounds.start), limit)
        case .end:
            let limit = max(current.start + minimumSlot, bounds.start + minimumSlot)
            slot.wrappedValue.end = max(min(snapped, bounds.end), limit)
        }
    }

    private func hour(atX x: CGFloat) -> Double {
        dayStart + Double(x - leadInset) / Double(hourWidth)
    }

    private func band(_ window: AvailabilityWindow, fill: Color) -> some View {
        let box = rect(window)
        return RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .frame(width: box.width, height: box.height)
            .offset(x: box.minX)
    }

    private func rect(_ window: AvailabilityWindow) -> CGRect {
        let minX = max(0, x(window.start))
        let maxX = min(contentWidth, x(window.end))
        return CGRect(x: minX, y: 0, width: max(0, maxX - minX), height: trackHeight)
    }

    private func x(_ hour: Double) -> CGFloat {
        leadInset + CGFloat(hour - dayStart) * hourWidth
    }

    private var accessibilitySummary: String {
        let overlaps = overlapWindows
        guard !overlaps.isEmpty else { return "No overlapping free time" }
        return overlaps
            .map { "\(Self.timeLabel($0.start)) to \(Self.timeLabel($0.end))" }
            .joined(separator: ", ")
    }

    static func hourLabel(_ hour: Int) -> String {
        let twelve = hour % 12
        return twelve == 0 ? "12" : "\(twelve)"
    }

    static func timeLabel(_ hour: Double) -> String {
        let minutes = Int((hour * 60).rounded())
        let h24 = (minutes / 60) % 24
        let minute = minutes % 60
        let suffix = h24 < 12 ? "AM" : "PM"
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d%@", h12, minute, suffix)
    }
}

/// The union bands as a single shape, used to mask the hatch.
private struct WindowsShape: Shape {
    var rects: [CGRect]
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for box in rects where box.width > 0 {
            path.addRoundedRect(
                in: box,
                cornerSize: CGSize(width: corner, height: corner),
                style: .continuous
            )
        }
        return path
    }
}
