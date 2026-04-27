import Foundation

enum AccountSort: String, CaseIterable, Identifiable {
    case custom, balance, type, recent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .custom:  return "Custom"
        case .balance: return "Balance"
        case .type:    return "Type"
        case .recent:  return "Recent"
        }
    }

    var icon: String {
        switch self {
        case .custom:  return "line.3.horizontal"
        case .balance: return "dollarsign.circle"
        case .type:    return "tag"
        case .recent:  return "clock"
        }
    }

    /// Apply the chosen sort to a section's accounts. Custom honours the
    /// user-set displayOrder; the others sort by the obvious dimension.
    func apply(to accounts: [Account]) -> [Account] {
        switch self {
        case .custom:
            return AccountManager.sortByDisplayOrder(accounts)
        case .balance:
            return accounts.sorted { abs($0.currentBalance) > abs($1.currentBalance) }
        case .type:
            return accounts.sorted { lhs, rhs in
                if lhs.type.rawValue == rhs.type.rawValue {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.type.rawValue < rhs.type.rawValue
            }
        case .recent:
            return accounts.sorted { $0.updatedAt > $1.updatedAt }
        }
    }
}
