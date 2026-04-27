import SwiftUI
import SkeletonUI

// ============================================================
// MARK: - AI Thinking Shimmer
// ============================================================
//
// Skeleton shimmer loading state shown while the AI model
// is processing (before first token arrives).
// Supports dynamic phase labels for a richer experience.
//
// ============================================================

struct AIThinkingShimmer: View {
    var label: String = "Thinking…"
    var icon: String = "brain"

    @Environment(\.colorScheme) private var colorScheme
    @State private var dotCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Phase label with icon and animated dots
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.accent)
                    .symbolEffect(.pulse, options: .repeating)

                Text(label)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.3), value: label)
            }

            // Shimmer lines mimicking a response
            VStack(alignment: .leading, spacing: 8) {
                shimmerLine(widthFraction: 0.92)
                shimmerLine(widthFraction: 0.78)
                shimmerLine(widthFraction: 0.55)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
        )
    }

    private func shimmerLine(widthFraction: CGFloat) -> some View {
        GeometryReader { geo in
            Text(" ")
                .frame(width: geo.size.width * widthFraction, height: 12)
                .skeleton(
                    with: true,
                    animation: .linear(duration: 1.5, delay: 0.1, autoreverses: false),
                    appearance: .gradient(
                        color: shimmerBase,
                        background: shimmerHighlight
                    ),
                    shape: .capsule
                )
        }
        .frame(height: 12)
    }

    private var shimmerBase: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private var shimmerHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.12)
    }
}

// MARK: - Skeleton Action Card (shimmer placeholder for action cards)

struct AIActionCardShimmer: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header shimmer
            HStack(spacing: 8) {
                Text(" ")
                    .frame(width: 20, height: 20)
                    .skeleton(
                        with: true,
                        animation: .linear(duration: 1.5),
                        appearance: .gradient(color: shimmerBase, background: shimmerHighlight),
                        shape: .circle
                    )

                Text(" ")
                    .frame(width: 100, height: 14)
                    .skeleton(
                        with: true,
                        animation: .linear(duration: 1.5),
                        appearance: .gradient(color: shimmerBase, background: shimmerHighlight),
                        shape: .capsule
                    )

                Spacer()

                Text(" ")
                    .frame(width: 50, height: 14)
                    .skeleton(
                        with: true,
                        animation: .linear(duration: 1.5),
                        appearance: .gradient(color: shimmerBase, background: shimmerHighlight),
                        shape: .capsule
                    )
            }

            // Detail rows shimmer
            VStack(spacing: 6) {
                shimmerDetailRow()
                shimmerDetailRow(valueFraction: 0.3)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colorScheme == .dark
                          ? Color.white.opacity(0.05)
                          : Color.black.opacity(0.03))
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
        )
    }

    private func shimmerDetailRow(valueFraction: CGFloat = 0.4) -> some View {
        HStack {
            Text(" ")
                .frame(width: 80, height: 10)
                .skeleton(
                    with: true,
                    animation: .linear(duration: 1.5),
                    appearance: .gradient(color: shimmerBase, background: shimmerHighlight),
                    shape: .capsule
                )
            Spacer()
            Text(" ")
                .frame(width: 60, height: 10)
                .skeleton(
                    with: true,
                    animation: .linear(duration: 1.5),
                    appearance: .gradient(color: shimmerBase, background: shimmerHighlight),
                    shape: .capsule
                )
        }
    }

    private var shimmerBase: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
    }

    private var shimmerHighlight: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.15)
            : Color.black.opacity(0.12)
    }
}

// ============================================================
// MARK: - AI Generating Gradient
// ============================================================
//
// Animated multi-stop gradient shown while the AI is generating.
// Conveys "alive / working" without being noisy.
//
// ============================================================

/// Apple-Intelligence-style backdrop ported from the macOS app.
/// Uses iOS 18 `MeshGradient` with two deep-saturated palettes that
/// crossfade in place; inner mesh control points wander on independent
/// axes; a black 35% overlay gives the "behind dark glass" feel without
/// needing an extra material layer on top.
struct AIGeneratingGradient: View {
    var cornerRadius: CGFloat = 16

    private static let paletteA: [Color] = [
        Color(red: 0.04, green: 0.07, blue: 0.20),
        Color(red: 0.13, green: 0.07, blue: 0.24),
        Color(red: 0.24, green: 0.08, blue: 0.22),
        Color(red: 0.04, green: 0.12, blue: 0.24),
        Color(red: 0.16, green: 0.12, blue: 0.28),
        Color(red: 0.28, green: 0.10, blue: 0.20),
        Color(red: 0.08, green: 0.16, blue: 0.24),
        Color(red: 0.18, green: 0.12, blue: 0.24),
        Color(red: 0.30, green: 0.14, blue: 0.18)
    ]
    private static let paletteB: [Color] = [
        Color(red: 0.02, green: 0.10, blue: 0.22),
        Color(red: 0.18, green: 0.08, blue: 0.20),
        Color(red: 0.30, green: 0.12, blue: 0.16),
        Color(red: 0.04, green: 0.16, blue: 0.22),
        Color(red: 0.14, green: 0.10, blue: 0.24),
        Color(red: 0.26, green: 0.08, blue: 0.24),
        Color(red: 0.08, green: 0.18, blue: 0.20),
        Color(red: 0.20, green: 0.10, blue: 0.22),
        Color(red: 0.28, green: 0.12, blue: 0.24)
    ]

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                meshBody
            } else {
                fallbackBody
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }

    @available(iOS 18.0, *)
    private var meshBody: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let mix = 0.5 + 0.5 * sin(t * 0.45)

            // Inner mesh control points wander on independent axes; corners
            // are pinned so the gradient never tears off the edges.
            let cx = Float(0.20 * sin(t * 0.37))
            let cy = Float(0.20 * cos(t * 0.51))
            let topX    = Float(0.5 + 0.20 * sin(t * 0.40))
            let bottomX = Float(0.5 + 0.20 * cos(t * 0.46 + 1.5))
            let leftY   = Float(0.5 + 0.20 * cos(t * 0.43))
            let rightY  = Float(0.5 + 0.20 * sin(t * 0.39 + 0.9))

            let points: [SIMD2<Float>] = [
                SIMD2(0.0, 0.0),       SIMD2(topX, 0.0),            SIMD2(1.0, 0.0),
                SIMD2(0.0, leftY),     SIMD2(0.5 + cx, 0.5 + cy),   SIMD2(1.0, rightY),
                SIMD2(0.0, 1.0),       SIMD2(bottomX, 1.0),         SIMD2(1.0, 1.0)
            ]

            let blended: [Color] = zip(Self.paletteA, Self.paletteB).map { a, b in
                Self.blend(a, b, t: mix)
            }

            MeshGradient(width: 3, height: 3, points: points, colors: blended)
                .overlay(Color.black.opacity(0.35))
        }
    }

    private var fallbackBody: some View {
        // iOS 17 fallback — corners-only crossfade between the two palettes.
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let mix = 0.5 + 0.5 * sin(t * 0.45)
            LinearGradient(
                colors: [
                    Self.blend(Self.paletteA[0], Self.paletteB[0], t: mix),
                    Self.blend(Self.paletteA[4], Self.paletteB[4], t: mix),
                    Self.blend(Self.paletteA[8], Self.paletteB[8], t: mix)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(Color.black.opacity(0.35))
        }
    }

    private static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let ua = UIColor(a)
        let ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let f = CGFloat(t)
        return Color(
            red:   Double(ar * (1 - f) + br * f),
            green: Double(ag * (1 - f) + bg * f),
            blue:  Double(ab * (1 - f) + bb * f)
        )
    }
}
