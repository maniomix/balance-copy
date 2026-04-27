import SwiftUI

/// Custom confirmation snippet rendered by the Shortcuts/Back Tap UI
/// after the App Intent runs.
///
/// IMPORTANT: Shortcuts snippets ignore `.preferredColorScheme` and host the
/// view inside a forced-dark glass overlay. Semantic colors like `.primary` /
/// `.secondary` resolve to the *device* color scheme — so on a light-mode
/// device they render black-on-dark and disappear. All text/glyph colors here
/// are explicit white tints so the snippet looks identical regardless of the
/// user's system theme.
struct QuickAddSnippetView: View {
    let amount: Double
    let currencySymbol: String
    let categoryTitle: String
    let categoryIcon: String
    let categoryTint: Color
    let date: Date
    let note: String

    private var amountText: String {
        "\(currencySymbol)\(String(format: "%.2f", amount))"
    }

    private var dateText: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Category glyph
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [categoryTint.opacity(0.95), categoryTint.opacity(0.65)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .shadow(color: categoryTint.opacity(0.45), radius: 10, x: 0, y: 4)
                Image(systemName: categoryIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Body
            VStack(alignment: .leading, spacing: 3) {
                Text(categoryTitle.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.55))

                Text(amountText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.30, green: 0.85, blue: 0.55))
                    Text(note.isEmpty ? dateText : "\(dateText) · \(note)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}
