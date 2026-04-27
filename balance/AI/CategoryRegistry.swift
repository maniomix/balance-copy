import SwiftUI
import os

// ============================================================
// MARK: - CategoryRegistry (Phase 5)
// ============================================================
//
// Lock-protected snapshot of the user's custom categories so AI
// subsystems that don't have a `Store` binding (system prompt
// builder, action parser, markdown renderer) can read them
// from any actor context.
//
// `AIChatView` (and any other view that owns `Store`) refreshes
// this registry whenever the custom category list changes via
// `update(from:)`. Consumers read via `customNames`, `model(for:)`,
// `icon(for:)`, `tint(for:)` — never mutate.
//
// Why a non-isolated singleton instead of passing `Store`?
//   • `AIMarkdownText` is invoked per-message inside chat bubbles.
//   • `AISystemPrompt.build()` is `static` and called from multiple
//     places (chat, prompt versioning).
//   • `AIActionParser` is a static enum reached from background tasks.
// Threading a binding through all of those would require dozens of
// signature changes for what is, in practice, read-only data.
// ============================================================

final class CategoryRegistry: @unchecked Sendable {
    static let shared = CategoryRegistry()

    private let lock = OSAllocatedUnfairLock()
    private var _customNames: [String] = []
    private var _modelsByName: [String: CustomCategoryModel] = [:]
    private var _modelsById: [String: CustomCategoryModel] = [:]

    private init() {}

    /// Sorted snapshot of user's custom category names. Safe to read from any thread.
    var customNames: [String] {
        lock.withLock { _customNames }
    }

    /// Refresh the registry from a `Store` snapshot. Idempotent — safe to
    /// call on every view appear / store-change.
    @MainActor
    func update(from store: Store) {
        let sorted = store.customCategoriesWithIcons.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.lowercased() < $1.name.lowercased()
        }
        let names = sorted.map(\.name)
        let byName = Dictionary(uniqueKeysWithValues: sorted.map { ($0.name.lowercased(), $0) })
        let byId = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0) })
        lock.withLock {
            _customNames = names
            _modelsByName = byName
            _modelsById = byId
        }
    }

    // MARK: - Resolvers

    func model(forName name: String) -> CustomCategoryModel? {
        lock.withLock { _modelsByName[name.lowercased()] }
    }

    func icon(for category: Category) -> String {
        if case .custom(let n) = category, let m = model(forName: n) { return m.icon }
        return category.icon
    }

    func tint(for category: Category) -> Color {
        if case .custom(let n) = category, let m = model(forName: n) { return m.color }
        return category.tint
    }

    /// Case-insensitive lookup. Returns the canonical name (with original
    /// casing) if a custom category matches. Used by `AIActionParser` to
    /// resolve LLM output like "coffee" → `custom:Coffee` instead of
    /// falling through to the alias map.
    func canonicalCustomName(for raw: String) -> String? {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return lock.withLock { _modelsByName[lower]?.name }
    }
}
