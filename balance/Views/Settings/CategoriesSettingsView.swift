import SwiftUI

// ============================================================
// MARK: - Categories Settings (Phase 3)
// ============================================================
//
// First-class entry point for managing custom categories from
// Settings → Preferences. Wraps `FullCategoryManager` and wires
// its save/delete callbacks into the unified `Store` API.
//
// Previously, custom-category management was reachable only via
// the transaction picker. Phase 3 promotes it to a top-level
// surface without removing the in-flow shortcut.
//
// Implementation note: `FullCategoryEditor.saveCategory()` already
// mutates `customCategoriesWithIcons` (append on add, replace on
// edit) BEFORE invoking `onSave`. The wrapper therefore only needs
// to reconcile *side effects*:
//   • Rename → cascade tx / budgets / recurring via `Store.renameCustomCategory`
//   • Add    → mirror name to legacy `customCategoryNames` until Phase 7
//   • Delete → cascade via `Store.deleteCustomCategory`
// `previousNames` snapshots the id→name mapping so we can detect
// renames when the editor calls back.
// ============================================================

struct CategoriesSettingsView: View {
    @Binding var store: Store

    /// Snapshot of `id -> name` taken on appear and refreshed after every save.
    /// Used to detect rename so transaction/budget/recurring references migrate.
    @State private var previousNames: [String: String] = [:]

    var body: some View {
        FullCategoryManager(
            customCategories: $store.customCategoriesWithIcons,
            onSave: { model in
                if let oldName = previousNames[model.id], oldName != model.name {
                    // Rename: editor already wrote the new name into the icons
                    // list, so `renameCustomCategory` no-ops that step but still
                    // migrates transactions / budgets / recurring atomically.
                    store.renameCustomCategory(oldName: oldName, newName: model.name)
                } else if previousNames[model.id] == nil {
                    // Newly added — assign a sortOrder if the editor left it at default 0.
                    if let idx = store.customCategoriesWithIcons.firstIndex(where: { $0.id == model.id }),
                       store.customCategoriesWithIcons[idx].sortOrder == 0 {
                        let maxOrder = store.customCategoriesWithIcons.map(\.sortOrder).max() ?? -1
                        store.customCategoriesWithIcons[idx].sortOrder = maxOrder + 1
                    }
                }
                previousNames[model.id] = model.name
                _ = store.save()
            },
            onDelete: { name in
                store.deleteCustomCategory(name: name)
                previousNames = Dictionary(uniqueKeysWithValues:
                    store.customCategoriesWithIcons.map { ($0.id, $0.name) })
                _ = store.save()
            },
            onMerge: { sourceName, target in
                store.mergeCustomCategory(source: sourceName, into: target)
                previousNames = Dictionary(uniqueKeysWithValues:
                    store.customCategoriesWithIcons.map { ($0.id, $0.name) })
                _ = store.save()
            },
            onReorder: {
                _ = store.save()
            },
            usageFor: { name in
                store.customCategoryUsage(name: name)
            }
        )
        .onAppear {
            previousNames = Dictionary(uniqueKeysWithValues:
                store.customCategoriesWithIcons.map { ($0.id, $0.name) })
        }
    }
}
