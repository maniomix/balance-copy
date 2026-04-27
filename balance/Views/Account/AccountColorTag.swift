import SwiftUI

// One-accent-per-card palette. Account.colorTag stores the raw token; this
// resolver maps it back to a Color and is also the single source of truth
// for the picker grid (Phase 5 reuses `allCases`).
enum AccountColorTag: String, CaseIterable, Identifiable {
    case blue, violet, teal, mint, orange, pink, indigo, slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue:   return DS.Colors.accent
        case .violet: return Color(red: 0.55, green: 0.40, blue: 0.95)
        case .teal:   return Color(red: 0.20, green: 0.75, blue: 0.85)
        case .mint:   return Color(red: 0.30, green: 0.80, blue: 0.60)
        case .orange: return Color(red: 0.98, green: 0.62, blue: 0.20)
        case .pink:   return Color(red: 0.95, green: 0.45, blue: 0.65)
        case .indigo: return Color(red: 0.40, green: 0.45, blue: 0.90)
        case .slate:  return Color(red: 0.50, green: 0.55, blue: 0.62)
        }
    }

    /// Resolve a stored tag (or nil) to a Color, falling back to the app accent.
    static func color(for tag: String?) -> Color {
        guard let tag, let value = AccountColorTag(rawValue: tag) else {
            return DS.Colors.accent
        }
        return value.color
    }
}
