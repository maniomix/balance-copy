import SwiftUI

// MARK: - Launch Screen Animation

struct LaunchScreenView: View {
    @State private var titleScale: CGFloat = 0.7
    @State private var titleOpacity: Double = 0
    @State private var taglineOffset: CGFloat = 15
    @State private var taglineOpacity: Double = 0

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                Text("CENTMOND")
                    .font(.custom("Pacifico-Regular", size: 48))
                    .foregroundStyle(.white)
                    .scaleEffect(titleScale)
                    .opacity(titleOpacity)

                Text("SMART PERSONAL FINANCE")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.4))
                    .offset(y: taglineOffset)
                    .opacity(taglineOpacity)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        // Phase 1: Title fade in + scale up
        withAnimation(.easeOut(duration: 0.9)) {
            titleScale = 1.0
            titleOpacity = 1.0
        }

        // Phase 2: Tagline slides up
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            taglineOffset = 0
            taglineOpacity = 1.0
        }

        // Phase 3: Hold then fade out
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) {
                titleOpacity = 0
                taglineOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onComplete()
            }
        }
    }
}
