import SwiftUI
import SkeletonUI
import Combine

// ============================================================
// MARK: - AI Model Loading View
// ============================================================
//
// Shown as an overlay while the AI model loads into memory.
// Features shimmer skeleton lines and rotating status messages
// that change over time to reassure the user.
//
// ============================================================

struct AIModelLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var messageIndex: Int = 0
    @State private var elapsedSeconds: Int = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Messages rotate every few seconds. Later messages appear after longer waits.
    private var currentMessage: String {
        let messages: [(afterSeconds: Int, text: String)] = [
            (0,  "Loading AI Model…"),
            (4,  "Preparing the neural network…"),
            (8,  "This might take a moment…"),
            (13, "Loading weights into memory…"),
            (18, "Almost there…"),
            (25, "Large models need a bit more time…"),
            (35, "Still working on it…"),
            (50, "Hang tight, nearly done…"),
        ]

        var best = messages[0].text
        for m in messages {
            if elapsedSeconds >= m.afterSeconds {
                best = m.text
            }
        }
        return best
    }

    var body: some View {
        VStack(spacing: 16) {
            // Pulsing brain icon
            Image(systemName: "brain")
                .font(.system(size: 28))
                .foregroundStyle(DS.Colors.accent)
                .symbolEffect(.pulse, options: .repeating)

            // Main status text
            Text(currentMessage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.4), value: currentMessage)

            // Shimmer skeleton lines
            VStack(alignment: .leading, spacing: 8) {
                shimmerLine(widthFraction: 0.85)
                shimmerLine(widthFraction: 0.7)
                shimmerLine(widthFraction: 0.55)
            }
            .frame(width: 200)

            // Elapsed time (show after 10 seconds)
            if elapsedSeconds >= 10 {
                Text("\(elapsedSeconds)s")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onReceive(timer) { _ in
            withAnimation {
                elapsedSeconds += 1
            }
        }
    }

    private func shimmerLine(widthFraction: CGFloat) -> some View {
        GeometryReader { geo in
            Text(" ")
                .frame(width: geo.size.width * widthFraction, height: 10)
                .skeleton(
                    with: true,
                    animation: .linear(duration: 1.5, delay: 0.1, autoreverses: false),
                    appearance: .gradient(
                        color: Color.white.opacity(0.1),
                        background: Color.white.opacity(0.2)
                    ),
                    shape: .capsule
                )
        }
        .frame(height: 10)
    }
}
