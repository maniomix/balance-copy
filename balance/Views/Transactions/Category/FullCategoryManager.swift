import SwiftUI

// MARK: - Full Category Manager
struct FullCategoryManager: View {
    @Binding var customCategories: [CustomCategoryModel]
    let onSave: ((CustomCategoryModel) -> Void)?
    /// Called when the user confirms deletion of a custom category. Caller
    /// should run `Store.deleteCustomCategory(name:)` to clean up references.
    let onDelete: ((String) -> Void)?
    /// Called when the user merges a custom category into another category.
    /// Caller should run `Store.mergeCustomCategory(source:into:)`.
    let onMerge: ((_ sourceName: String, _ target: Category) -> Void)?
    /// Returns (transactions, recurring, budget months) referencing the name.
    /// When provided, the manager shows usage counts in the delete dialog.
    let usageFor: ((String) -> (transactions: Int, recurring: Int, budgets: Int))?
    /// Called when the user reorders custom categories. Caller should persist
    /// the new `sortOrder` values via the binding (already mutated).
    let onReorder: (() -> Void)?
    /// Optional list of merge targets. Built-ins are always included; the
    /// manager filters out the source when offering the picker.
    let mergeTargets: [Category]?

    @State private var showAddCategory = false
    @State private var editingCategory: CustomCategoryModel?
    @State private var pendingDelete: CustomCategoryModel?
    @State private var pendingMerge: CustomCategoryModel?
    @State private var editMode: EditMode = .inactive

    init(customCategories: Binding<[CustomCategoryModel]>,
         onSave: ((CustomCategoryModel) -> Void)? = nil,
         onDelete: ((String) -> Void)? = nil,
         onMerge: ((_ sourceName: String, _ target: Category) -> Void)? = nil,
         onReorder: (() -> Void)? = nil,
         usageFor: ((String) -> (transactions: Int, recurring: Int, budgets: Int))? = nil,
         mergeTargets: [Category]? = nil) {
        self._customCategories = customCategories
        self.onSave = onSave
        self.onDelete = onDelete
        self.onMerge = onMerge
        self.onReorder = onReorder
        self.usageFor = usageFor
        self.mergeTargets = mergeTargets
    }

    // Default categories (read-only)
    let defaultCategories: [(name: String, icon: String, color: Color)] = [
        ("Groceries", "cart.fill", .green),
        ("Rent", "house.fill", .orange),
        ("Bills", "doc.text.fill", .red),
        ("Transport", "car.fill", .blue),
        ("Health", "heart.fill", Color(red: 1.0, green: 0.23, blue: 0.19)),
        ("Education", "book.fill", Color(red: 0.35, green: 0.78, blue: 0.98)),
        ("Dining", "fork.knife", Color(red: 1.0, green: 0.18, blue: 0.33)),
        ("Shopping", "bag.fill", Color(red: 0.69, green: 0.32, blue: 0.87)),
        ("Other", "questionmark.circle.fill", .gray)
    ]

    // Sort by sortOrder, fall back to alphabetical for ties.
    private var orderedCustom: [CustomCategoryModel] {
        customCategories.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.name.lowercased() < $1.name.lowercased()
        }
    }

    var body: some View {
        List {
            // Default Categories
            Section("Default Categories") {
                ForEach(defaultCategories, id: \.name) { category in
                    HStack(spacing: 12) {
                        Image(systemName: category.icon)
                            .font(.system(size: 24))
                            .foregroundColor(category.color)
                            .frame(width: 40, height: 40)
                            .background(category.color.opacity(0.2))
                            .cornerRadius(8)

                        Text(category.name)

                        Spacer()

                        Circle()
                            .fill(category.color)
                            .frame(width: 20, height: 20)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Custom Categories
            Section {
                ForEach(orderedCustom) { category in
                    customRow(category)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = category
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            if onMerge != nil {
                                Button {
                                    pendingMerge = category
                                } label: {
                                    Label("Merge", systemImage: "arrow.triangle.merge")
                                }
                                .tint(.orange)
                            }
                        }
                }
                .onMove(perform: handleMove)

                Button {
                    showAddCategory = true
                } label: {
                    Label("Add Custom Category", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Custom Categories")
                    Spacer()
                    if !customCategories.isEmpty {
                        EditButton()
                            .font(.system(size: 13, weight: .medium))
                    }
                }
            } footer: {
                if !customCategories.isEmpty {
                    Text("Swipe a category to delete or merge. Tap Edit to reorder.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Manage Categories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddCategory) {
            FullCategoryEditor(customCategories: $customCategories, onSave: onSave)
        }
        .sheet(item: $editingCategory) { category in
            FullCategoryEditor(customCategories: $customCategories, editingCategory: category, onSave: onSave)
        }
        .sheet(item: $pendingMerge) { source in
            MergeTargetPicker(
                source: source,
                targets: mergeTargetsExcluding(source),
                customCategories: customCategories
            ) { target in
                onMerge?(source.name, target)
                pendingMerge = nil
            }
        }
        .alert(deleteAlertTitle, isPresented: deleteBinding, presenting: pendingDelete) { category in
            Button("Delete", role: .destructive) {
                if let idx = customCategories.firstIndex(where: { $0.id == category.id }) {
                    customCategories.remove(at: idx)
                }
                onDelete?(category.name)
            }
            Button("Cancel", role: .cancel) { }
        } message: { category in
            Text(deleteAlertMessage(for: category))
        }
    }

    // MARK: - Row

    private func customRow(_ category: CustomCategoryModel) -> some View {
        Button {
            editingCategory = category
        } label: {
            HStack(spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 24))
                    .foregroundColor(category.color)
                    .frame(width: 40, height: 40)
                    .background(category.color.opacity(0.2))
                    .cornerRadius(8)

                Text(category.name)
                    .foregroundColor(.primary)

                Spacer()

                Circle()
                    .fill(category.color)
                    .frame(width: 20, height: 20)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Reorder

    private func handleMove(from source: IndexSet, to destination: Int) {
        // Work on the displayed (ordered) list, then write sortOrder back.
        var reordered = orderedCustom
        reordered.move(fromOffsets: source, toOffset: destination)
        for (i, model) in reordered.enumerated() {
            if let idx = customCategories.firstIndex(where: { $0.id == model.id }) {
                customCategories[idx].sortOrder = i
            }
        }
        onReorder?()
    }

    // MARK: - Delete alert

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var deleteAlertTitle: String {
        guard let cat = pendingDelete else { return "Delete category?" }
        return "Delete \(cat.name)?"
    }

    private func deleteAlertMessage(for category: CustomCategoryModel) -> String {
        guard let usage = usageFor?(category.name) else {
            return "Transactions using this category will move to Other."
        }
        var lines: [String] = []
        if usage.transactions > 0 {
            lines.append("\(usage.transactions) transaction\(usage.transactions == 1 ? "" : "s") will move to Other")
        }
        if usage.recurring > 0 {
            lines.append("\(usage.recurring) recurring rule\(usage.recurring == 1 ? "" : "s") will move to Other")
        }
        if usage.budgets > 0 {
            lines.append("\(usage.budgets) monthly budget\(usage.budgets == 1 ? "" : "s") will be removed")
        }
        if lines.isEmpty {
            return "Nothing else references this category."
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Merge targets

    private func mergeTargetsExcluding(_ source: CustomCategoryModel) -> [Category] {
        let provided = mergeTargets ?? (Category.allCases + customCategories
            .filter { $0.id != source.id }
            .map { Category.custom($0.name) })
        return provided.filter { cat in
            if case .custom(let n) = cat { return n != source.name }
            return true
        }
    }
}

// MARK: - Merge target picker

private struct MergeTargetPicker: View {
    let source: CustomCategoryModel
    let targets: [Category]
    let customCategories: [CustomCategoryModel]
    let onPick: (Category) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(targets, id: \.self) { cat in
                Button {
                    onPick(cat)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: iconFor(cat))
                            .font(.system(size: 18))
                            .foregroundColor(tintFor(cat))
                            .frame(width: 32, height: 32)
                            .background(tintFor(cat).opacity(0.18))
                            .cornerRadius(8)
                        Text(cat.title)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Merge \(source.name) into…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func iconFor(_ cat: Category) -> String {
        if case .custom(let name) = cat,
           let m = customCategories.first(where: { $0.name == name }) { return m.icon }
        return cat.icon
    }

    private func tintFor(_ cat: Category) -> Color {
        if case .custom(let name) = cat,
           let m = customCategories.first(where: { $0.name == name }) { return m.color }
        return cat.tint
    }
}

#Preview {
    NavigationView {
        FullCategoryManager(customCategories: .constant([
            CustomCategoryModel(name: "Coffee", icon: "cup.and.saucer.fill", colorHex: "A0522D", sortOrder: 0),
            CustomCategoryModel(name: "Pets", icon: "pawprint.fill", colorHex: "FF6B6B", sortOrder: 1)
        ]))
    }
}
