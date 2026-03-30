import SwiftUI
import CryptoKit

// MARK: - Tab

enum Tab: Hashable {
    case dashboard, transactions, budget, insights, more, accounts, goals, subscriptions, household, settings
}

// MARK: - Import History

enum ImportHistory {
    private static let key = "imports.hashes.v1"

    static func load() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr)
    }

    static func contains(_ hash: String) -> Bool {
        load().contains(hash)
    }

    static func append(_ hash: String) {
        var set = load()
        set.insert(hash)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}

// MARK: - Import Deduper

enum ImportDeduper {
    static func signature(for t: Transaction) -> String {
        let note = t.note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        let day = iso.string(from: t.date)

        let cat = String(describing: t.category)

        return "\(day)|\(t.amount)|\(cat)|\(note)"
    }

    static func datasetHash(transactions: [Transaction]) -> String {
        let lines = transactions.map(signature(for:)).sorted()
        let joined = lines.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - UUID Wrapper

struct UUIDWrapper: Identifiable {
    let id: UUID
}
