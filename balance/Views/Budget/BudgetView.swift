import SwiftUI

// MARK: - Budget

struct BudgetView: View {
    @Binding var store: Store
    @State private var showPaywall = false
    @StateObject private var subscriptionManager = SubscriptionManager.shared


    @State private var editingTotal = ""
    @State private var editingCategoryBudgets: [Category: String] = [:]
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var editingCustomCategory: CustomCategoryModel?
    @FocusState private var focus: Bool

    // Check if budget has changed
    private var hasChanges: Bool {
        let newValue = DS.Format.cents(from: editingTotal)
        return newValue != store.budgetTotal && newValue > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {

                    DS.Card {
                        VStack(spacing: 16) {
                            Text("Monthly Budget")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                                .textCase(.uppercase)
                                .tracking(0.5)

                            // Hero amount — large centered input
                            TextField(DS.Format.amountPlaceholder(), text: $editingTotal)
                                .keyboardType(.decimalPad)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus)
                                .font(.system(size: 42, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(DS.Colors.text)
                                .multilineTextAlignment(.center)
                                .padding(.vertical, 8)

                            // Full-width save button
                            Button(store.budgetTotal <= 0 ? "Start Tracking" : "Save Budget") {
                                let v = DS.Format.cents(from: editingTotal)
                                store.budgetTotal = max(0, v)
                                focus = false
                                Haptics.success()
                                AnalyticsManager.shared.track(.budgetSet)
                                AnalyticsManager.shared.checkFirstBudget()
                            }
                            .buttonStyle(DS.PrimaryButton())
                            .disabled(!hasChanges)
                            .opacity(hasChanges ? 1.0 : 0.5)

                            if store.budgetTotal <= 0 {
                                DS.StatusLine(
                                    title: "Analysis Paused",
                                    detail: "Set a budget to see insights",
                                    level: .watch
                                )
                            } else {
                                DS.StatusLine(
                                    title: "Budget Set",
                                    detail: "You're ready to track",
                                    level: .ok
                                )
                            }
                        }
                    }

                    if store.budgetTotal > 0 {
                        DS.Card {
                            let summary = Analytics.monthSummary(store: store)
                            VStack(alignment: .leading, spacing: 10) {
                                Text("This month")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                DS.Meter(
                                    title: "Budget used",
                                    value: summary.totalSpent,
                                    max: max(1, store.budgetTotal),
                                    hint: "\(DS.Format.percent(summary.spentRatio)) used"
                                )

                                Divider().foregroundStyle(DS.Colors.grid)

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Spent")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        Text(DS.Format.money(summary.totalSpent))
                                            .font(DS.Typography.number)
                                            .foregroundStyle(DS.Colors.text)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        HStack(spacing: 4) {
                                            Text("Remaining")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)

                                            // اگر income زیادی داشتیم که باعث شد remaining بالا بره
                                            let tx = Analytics.monthTransactions(store: store)
                                            let totalIncome = tx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
                                            if totalIncome > 0 && summary.remaining > store.budgetTotal {
                                                Text("(+income)")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundStyle(DS.Colors.positive)
                                            }
                                        }

                                        let tx = Analytics.monthTransactions(store: store)
                                        let totalIncome = tx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
                                        let hasSignificantIncome = totalIncome > store.budgetTotal * 10 / 100 // اگر income بیشتر از 10% budget بود

                                        Text(DS.Format.money(summary.remaining))
                                            .font(DS.Typography.number)
                                            .foregroundStyle(
                                                hasSignificantIncome && summary.remaining > 0 ?
                                                DS.Colors.positive :
                                                (summary.remaining >= 0 ? DS.Colors.text : DS.Colors.danger)
                                            )
                                    }
                                }
                            }
                        }
                        // Shared Budget (household) — only if user is in a household with a shared budget
                        if HouseholdManager.shared.isInHousehold {
                            let mk = Store.monthKey(store.selectedMonth)
                            if let sb = HouseholdManager.shared.sharedBudget(for: mk), sb.totalAmount > 0 {
                                let sharedSpent = HouseholdManager.shared.sharedSpending(monthKey: mk)
                                let sharedRemaining = sb.totalAmount - sharedSpent
                                let isOver = sharedSpent > sb.totalAmount

                                DS.Card {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            Label("Shared Budget", systemImage: "person.2.fill")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(DS.Colors.accent)
                                            Spacer()
                                            if isOver {
                                                Text("Over budget")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(DS.Colors.danger)
                                                    .padding(.horizontal, 7)
                                                    .padding(.vertical, 3)
                                                    .background(DS.Colors.danger.opacity(0.1), in: Capsule())
                                            }
                                        }

                                        DS.Meter(
                                            title: "Shared used",
                                            value: sharedSpent,
                                            max: max(1, sb.totalAmount),
                                            hint: "\(DS.Format.percent(Double(sharedSpent) / Double(max(1, sb.totalAmount)))) used"
                                        )

                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("Shared Spent")
                                                    .font(DS.Typography.caption)
                                                    .foregroundStyle(DS.Colors.subtext)
                                                Text(DS.Format.money(sharedSpent))
                                                    .font(DS.Typography.number)
                                                    .foregroundStyle(DS.Colors.text)
                                            }
                                            Spacer()
                                            VStack(alignment: .trailing, spacing: 4) {
                                                Text("Remaining")
                                                    .font(DS.Typography.caption)
                                                    .foregroundStyle(DS.Colors.subtext)
                                                Text(DS.Format.money(sharedRemaining))
                                                    .font(DS.Typography.number)
                                                    .foregroundStyle(isOver ? DS.Colors.danger : DS.Colors.text)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Category Budgets")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                Text("Set spending limits per category")
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.subtext)

                                Divider().foregroundStyle(DS.Colors.grid)

                                VStack(spacing: 10) {
                                    ForEach(store.allCategories, id: \.self) { c in
                                        HStack(spacing: 10) {
                                            HStack(spacing: 8) {
                                                Circle()
                                                    .fill({
                                                        if case .custom(let name) = c {
                                                            return store.customCategoryColor(for: name).opacity(0.18)
                                                        }
                                                        return c.tint.opacity(0.18)
                                                    }())
                                                    .frame(width: 26, height: 26)
                                                    .overlay(
                                                        Image(systemName: {
                                                            if case .custom(let name) = c {
                                                                return store.customCategoryIcon(for: name)
                                                            }
                                                            return c.icon
                                                        }())
                                                            .foregroundStyle({
                                                                if case .custom(let name) = c {
                                                                    return store.customCategoryColor(for: name)
                                                                }
                                                                return c.tint
                                                            }())
                                                            .font(.system(size: 12, weight: .semibold))
                                                    )
                                                Text(c.title)
                                                    .font(DS.Typography.body)
                                                    .foregroundStyle(DS.Colors.text)
                                            }
                                            Spacer()

                                            HStack(spacing: 6) {
                                                TextField("0.00", text: Binding(
                                                    get: { editingCategoryBudgets[c] ?? "" },
                                                    set: { newVal in
                                                        editingCategoryBudgets[c] = newVal
                                                        let v = DS.Format.cents(from: newVal)
                                                        store.setCategoryBudget(v, for: c)
                                                    }
                                                ))
                                                .keyboardType(.decimalPad)
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                                .multilineTextAlignment(.trailing)
                                                .font(DS.Typography.number)
                                                .padding(10)
                                                .frame(width: 120)
                                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                            }
                                        }
                                        .contextMenu {
                                            if case .custom(let name) = c {
                                                // ✅ Edit button
                                                Button {
                                                    if let customCat = store.customCategoriesWithIcons.first(where: { $0.name == name }) {
                                                        editingCustomCategory = customCat
                                                    }
                                                    Haptics.light()
                                                } label: {
                                                    Label("Edit Category", systemImage: "pencil")
                                                }

                                                // Delete button
                                                Button(role: .destructive) {
                                                    withAnimation {
                                                        store.deleteCustomCategory(name: name)
                                                        editingCategoryBudgets.removeValue(forKey: c)
                                                    }
                                                    Haptics.medium()

                                                    // Save to Supabase
                                                    Task {
                                                        try? await SupabaseManager.shared.saveStore(store)
                                                    }
                                                } label: {
                                                    Label("Delete Category", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }

                                    // Add Category Button
                                    Button {
                                        showAddCategory = true
                                        Haptics.medium()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundStyle(DS.Colors.accent)
                                            Text("Add Custom Category")
                                                .foregroundStyle(DS.Colors.text)
                                        }
                                        .font(DS.Typography.body)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }

                                Divider().foregroundStyle(DS.Colors.grid)

                                let allocated = store.totalCategoryBudgets()
                                let remainingToAllocate = store.budgetTotal - allocated

                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Allocated")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        Text(DS.Format.money(allocated))
                                            .font(DS.Typography.number)
                                            .foregroundStyle(DS.Colors.text)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Unallocated")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                        Text(DS.Format.money(remainingToAllocate))
                                            .font(DS.Typography.number)
                                            .foregroundStyle(remainingToAllocate >= 0 ? DS.Colors.text : DS.Colors.danger)
                                    }
                                }

                                if allocated > store.budgetTotal {
                                    DS.StatusLine(
                                        title: "Category caps exceed total budget",
                                        detail: "Reduce one or more category budgets so allocation stays within the monthly total.",
                                        level: .watch
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Budget")
            .dismissKeyboardOnTap()
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focus = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.accent)
                }
            }
            .onAppear {
                // Initialize with current budget
                if store.budgetTotal > 0 {
                    editingTotal = DS.Format.currency(store.budgetTotal)
                }
            }
            .sheet(isPresented: $showAddCategory) {
                FullCategoryEditor(
                    customCategories: $store.customCategoriesWithIcons,
                    onSave: { category in
                        if !store.customCategoriesWithIcons.contains(where: { $0.id == category.id }) {
                            store.customCategoriesWithIcons.append(category)
                        }

                        Task {
                            try? await SupabaseManager.shared.saveStore(store)
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingCustomCategory) { originalCategory in
                FullCategoryEditor(
                    customCategories: $store.customCategoriesWithIcons,
                    editingCategory: originalCategory,
                    onSave: { saved in
                        let oldName = originalCategory.name
                        let newName = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)

                        // 1. If the name changed, atomically rename across transactions, budgets, recurring, etc.
                        if oldName != newName && !newName.isEmpty {
                            store.renameCustomCategory(oldName: oldName, newName: newName)
                        }

                        // 2. Update icon/color in customCategoriesWithIcons
                        if let index = store.customCategoriesWithIcons.firstIndex(where: { $0.id == saved.id }) {
                            store.customCategoriesWithIcons[index] = saved
                        } else if !store.customCategoriesWithIcons.contains(where: { $0.id == saved.id }) {
                            store.customCategoriesWithIcons.append(saved)
                        }

                        // 3. Save
                        Task {
                            try? await SupabaseManager.shared.saveStore(store)
                        }
                    }
                )
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                editingTotal = store.budgetTotal > 0
                    ? String(format: "%.2f", Double(store.budgetTotal) / 100.0)
                    : ""
                var map: [Category: String] = [:]
                for c in store.allCategories {
                    let v = store.categoryBudget(for: c)
                    map[c] = v > 0 ? String(format: "%.2f", Double(v) / 100.0) : ""
                }
                editingCategoryBudgets = map
            }
            .sheet(isPresented: $showPaywall) {
            }
        }
    }
}
