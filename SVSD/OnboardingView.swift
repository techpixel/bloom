import SwiftUI

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var didStart = false
    @State private var logoScale: CGFloat = 70
    @State private var wordmarkOpacity = 1.0
    @State private var wordmarkOffset: CGFloat = 0
    @State private var taglineVisible = false
    @State private var controlsVisible = false

    private var isDark: Bool { colorScheme == .dark }
    private var surface: Color { isDark ? .black : .white }
    private var mark: Color { isDark ? .white : .black }
    private var wordmarkColor: Color { isDark ? .black : .white }

    var body: some View {
        GeometryReader { geometry in
            let logoWidth = min(geometry.size.width * 0.648, 255)
            let logoHeight = logoWidth * 120.737 / 254.585

            ZStack {
                surface

                Image("SVSDLogo")
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(mark)
                    .scaledToFit()
                    .frame(width: logoWidth, height: logoHeight)
                    .scaleEffect(logoScale)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.475)
                    .accessibilityLabel("SVSD logo")

                Text("making friendships count.")
                    .font(.system(size: 15.62, weight: .regular))
                    .foregroundStyle(mark)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.585)
                    .opacity(taglineVisible ? 1 : 0)
                    .blur(radius: taglineVisible ? 0 : 4)
                    .offset(y: taglineVisible ? 0 : 12)

                Button {} label: {
                    Text("let’s get started")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(surface)
                        .frame(width: 194, height: 44)
                        .background {
                            Capsule().fill(mark).frame(height: 36)
                        }
                }
                .buttonStyle(.plain)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.826)
                .opacity(controlsVisible ? 1 : 0)
                .blur(radius: controlsVisible ? 0 : 4)
                .offset(y: controlsVisible ? 0 : 12)
                .allowsHitTesting(controlsVisible)
                .accessibilityHidden(!controlsVisible)

                HStack(spacing: 8) {
                    Circle().fill(mark)
                    Circle().fill(mark.opacity(0.3))
                }
                .frame(width: 24, height: 8)
                .position(x: geometry.size.width / 2 - 1, y: geometry.size.height * 0.95)
                .opacity(controlsVisible ? 1 : 0)
                .blur(radius: controlsVisible ? 0 : 4)
                .offset(y: controlsVisible ? 0 : 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Page 1 of 2")
                .accessibilityHidden(!controlsVisible)

                Text("kith")
                    .font(.system(size: 20, weight: .medium))
                    .tracking(2.4)
                    .foregroundStyle(wordmarkColor)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
                    .accessibilityHidden(true)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(surface)
        .ignoresSafeArea()
        .statusBarHidden(true)
        .onAppear(perform: beginEntrance)
    }

    private func beginEntrance() {
        guard !didStart else { return }
        didStart = true

        guard !reduceMotion else {
            logoScale = 1
            wordmarkOpacity = 0
            taglineVisible = true
            controlsVisible = true
            return
        }

        withAnimation(.timingCurve(0.2, 0, 0, 1, duration: 1.25).delay(1.05)) {
            logoScale = 1
        }
        withAnimation(.easeOut(duration: 0.2).delay(0.9)) {
            wordmarkOpacity = 0
            wordmarkOffset = -6
        }
        withAnimation(.easeOut(duration: 0.34).delay(2.3)) {
            taglineVisible = true
        }
        withAnimation(.easeOut(duration: 0.32).delay(2.42)) {
            controlsVisible = true
        }
    }
}

#Preview {
    OnboardingView()
}
