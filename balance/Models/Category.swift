import SwiftUI

// MARK: - Category

enum Category: Hashable, Codable {
    case groceries, rent, bills, transport, health, education, dining, shopping, other
    case custom(String)

    static var allCases: [Category] {
        [.groceries, .rent, .bills, .transport, .health, .education, .dining, .shopping, .other]
    }

    /// Stable key for persistence / dictionaries.
    /// NOTE: for custom categories we prefix with `custom:`.
    var storageKey: String {
        switch self {
        case .groceries: return "groceries"
        case .rent: return "rent"
        case .bills: return "bills"
        case .transport: return "transport"
        case .health: return "health"
        case .education: return "education"
        case .dining: return "dining"
        case .shopping: return "shopping"
        case .other: return "other"
        case .custom(let name):
            return "custom:\(name)"
        }
    }

    var title: String {
        switch self {
        case .groceries: return "Groceries"
        case .rent: return "Rent"
        case .bills: return "Bills"
        case .transport: return "Transport"
        case .health: return "Health"
        case .education: return "Education"
        case .dining: return "Dining"
        case .shopping: return "Shopping"
        case .other: return "Other"
        case .custom(let name): return name
        }
    }

    var icon: String {
        switch self {
        case .custom:
            return "tag"
        default:
            switch self {
            case .groceries: return "basket"
            case .rent: return "house"
            case .bills: return "doc.text"
            case .transport: return "car"
            case .health: return "cross.case"
            case .education: return "book"
            case .dining: return "fork.knife"
            case .shopping: return "bag"
            case .other: return "square.grid.2x2"
            case .custom: return "tag"
            }
        }
    }

    var tint: Color {
        switch self {
        case .custom:
            return Color(hexValue: 0x95A5A6)  // Gray
        default:
            switch self {
            case .groceries: return Color(hexValue: 0x2ECC71)  // Green
            case .rent: return Color(hexValue: 0x3498DB)       // Blue
            case .bills: return Color(hexValue: 0xF39C12)      // Orange
            case .transport: return Color(hexValue: 0x9B59B6)  // Purple
            case .health: return Color(hexValue: 0xE74C3C)     // Red
            case .education: return Color(hexValue: 0x1ABC9C)  // Teal
            case .dining: return Color(hexValue: 0xE91E63)     // Pink
            case .shopping: return Color(hexValue: 0xFF5722)   // Deep Orange
            case .other: return Color(hexValue: 0x607D8B)      // Blue Gray
            case .custom: return Color(hexValue: 0x95A5A6)
            }
        }
    }

    /// Create a Category from its storageKey (e.g. "dining", "custom:Coffee").
    /// Returns nil for unknown keys.
    init?(storageKey: String) {
        if storageKey.hasPrefix("custom:") {
            let name = String(storageKey.dropFirst(7))
            self = .custom(name)
            return
        }
        switch storageKey {
        case "groceries": self = .groceries
        case "rent": self = .rent
        case "bills": self = .bills
        case "transport": self = .transport
        case "health": self = .health
        case "education": self = .education
        case "dining": self = .dining
        case "shopping": self = .shopping
        case "other": self = .other
        default: return nil
        }
    }

    // MARK: - Codable
    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case system, custom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(Kind.self, forKey: .type)
        switch type {
        case .system:
            let v = try c.decode(String.self, forKey: .value)
            switch v {
            case "groceries": self = .groceries
            case "rent": self = .rent
            case "bills": self = .bills
            case "transport": self = .transport
            case "health": self = .health
            case "education": self = .education
            case "dining": self = .dining
            case "shopping": self = .shopping
            default: self = .other
            }
        case .custom:
            let name = try c.decode(String.self, forKey: .value)
            self = .custom(name)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .custom(let name):
            try c.encode(Kind.custom, forKey: .type)
            try c.encode(name, forKey: .value)
        default:
            try c.encode(Kind.system, forKey: .type)
            let raw: String
            switch self {
            case .groceries: raw = "groceries"
            case .rent: raw = "rent"
            case .bills: raw = "bills"
            case .transport: raw = "transport"
            case .health: raw = "health"
            case .education: raw = "education"
            case .dining: raw = "dining"
            case .shopping: raw = "shopping"
            case .other: raw = "other"
            case .custom: raw = "other"
            }
            try c.encode(raw, forKey: .value)
        }
    }
}

// MARK: - Custom Category Model

struct CustomCategoryModel: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var icon: String
    var colorHex: String
    var sortOrder: Int

    init(id: String = UUID().uuidString,
         name: String,
         icon: String = "tag.fill",
         colorHex: String = "AF52DE",
         sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.sortOrder = sortOrder
    }

    var color: Color {
        Color(hex: colorHex) ?? .purple
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon
        case colorHex = "color_hex"
        case sortOrder = "sort_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.icon = try c.decode(String.self, forKey: .icon)
        self.colorHex = try c.decode(String.self, forKey: .colorHex)
        self.sortOrder = (try? c.decode(Int.self, forKey: .sortOrder)) ?? 0
    }
}

// MARK: - Custom Category Resolution
//
// `Category.custom(String)` only carries the name. Icon/color live on
// `CustomCategoryModel` inside the Store. These helpers let any view that has
// a `Store` resolve the proper icon/color for a custom category instead of
// falling back to the generic gray "tag" baked into `Category.icon` / `.tint`.
extension Category {
    func icon(in store: Store) -> String {
        if case .custom(let name) = self,
           let model = store.customCategoriesWithIcons.first(where: { $0.name == name }) {
            return model.icon
        }
        return self.icon
    }

    func tint(in store: Store) -> Color {
        if case .custom(let name) = self,
           let model = store.customCategoriesWithIcons.first(where: { $0.name == name }) {
            return model.color
        }
        return self.tint
    }
}
