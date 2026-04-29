import Foundation
import Combine

struct SavedFilterPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var filter: TransactionFilter

    init(id: UUID = UUID(), name: String, filter: TransactionFilter) {
        self.id = id
        self.name = name
        self.filter = filter
    }
}

// Local-first storage for filter presets pinned to the Transactions filter
// sheet. UserDefaults is the synchronous fast path; cloud sync mirrors
// writes to `public.saved_filter_presets` and pulls on sign-in.
@MainActor
final class SavedFilterPresetStore: ObservableObject {
    static let shared = SavedFilterPresetStore()

    @Published private(set) var presets: [SavedFilterPreset] = []

    private let key = "transactions.savedFilterPresets.v1"
    private let maxCount = 5

    init() { load() }

    var canAddMore: Bool { presets.count < maxCount }

    func add(name: String, filter: TransactionFilter) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAddMore else { return }
        presets.append(SavedFilterPreset(name: trimmed, filter: filter))
        persist()
    }

    func remove(_ id: UUID) {
        presets.removeAll { $0.id == id }
        persist()
    }

    func matches(_ filter: TransactionFilter) -> SavedFilterPreset? {
        presets.first { $0.filter == filter }
    }

    /// Replace local list with the cloud snapshot. Called by
    /// `SavedFilterPresetSync.pull()` on sign-in.
    func replaceFromCloud(_ remote: [SavedFilterPreset]) {
        presets = remote
        // Persist *only* to UserDefaults — don't re-push and create a loop.
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([SavedFilterPreset].self, from: data) {
            presets = decoded
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
        SavedFilterPresetSync.push(presets)
    }
}
