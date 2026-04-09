import SwiftUI

struct EditTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var store: Store
    let transactionID: UUID

    @State private var amountText = ""
    @State private var note = ""
    @State private var date: Date = Date()
    @State private var category: Category = .groceries
    @State private var paymentMethod: PaymentMethod = .card
    @State private var transactionType: TransactionType = .expense  // ← جدید
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var editingCustomCategory: CustomCategoryModel?  // ← جدید
    @State private var selectedAccountId: UUID? = nil
    @State private var selectedGoalId: UUID? = nil
    @State private var showSaveFailedAlert = false
    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var goalManager = GoalManager.shared

    private var index: Int? {
        store.transactions.firstIndex { $0.id == transactionID }
    }

    var body: some View {
        NavigationView {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        TransactionFormCard(
                            amountText: $amountText,
                            note: $note,
                            date: $date,
                            category: $category,
                            transactionType: $transactionType,
                            store: $store,
                            categories: store.allCategories,
                            onAddCategory: {
                                showAddCategory = true
                            },
                            onEditCategory: { customCat in
                                editingCustomCategory = customCat
                            }
                        )

                        // ── Payment Method Card ──
                        DS.Card {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Payment Method")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)

                                HStack(spacing: 12) {
                                    ForEach(PaymentMethod.allCases, id: \.self) { method in
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                paymentMethod = method
                                                Haptics.selection()
                                            }
                                        } label: {
                                            VStack(spacing: 8) {
                                                Image(systemName: method.icon)
                                                    .font(.system(size: 22, weight: paymentMethod == method ? .semibold : .regular))
                                                    .foregroundStyle(paymentMethod == method ? method.tint : DS.Colors.subtext)
                                                    .frame(width: 48, height: 48)
                                                    .background(
                                                        paymentMethod == method
                                                            ? method.tint.opacity(0.10)
                                                            : DS.Colors.surface2,
                                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                    )

                                                Text(method.displayName)
                                                    .font(.system(size: 13, weight: paymentMethod == method ? .semibold : .medium, design: .rounded))
                                                    .foregroundStyle(paymentMethod == method ? DS.Colors.text : DS.Colors.subtext)
                                            }
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .fill(paymentMethod == method ? DS.Colors.surface : Color.clear)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                    .stroke(
                                                        paymentMethod == method ? method.tint.opacity(0.3) : Color.clear,
                                                        lineWidth: 1.5
                                                    )
                                            )
                                            .shadow(
                                                color: paymentMethod == method ? method.tint.opacity(0.12) : .clear,
                                                radius: 8,
                                                x: 0,
                                                y: 3
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        // ── Account & Goal linking ──
                        if !accountManager.accounts.isEmpty || !goalManager.activeGoals.isEmpty {
                            DS.Card {
                                VStack(alignment: .leading, spacing: 14) {
                                    // Account row
                                    if !accountManager.accounts.isEmpty {
                                        Text("Account")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)

                                        Menu {
                                            Button {
                                                selectedAccountId = nil
                                            } label: {
                                                Label("None", systemImage: "minus.circle")
                                            }
                                            Divider()
                                            ForEach(accountManager.accounts) { account in
                                                Button {
                                                    selectedAccountId = account.id
                                                } label: {
                                                    Label(account.name, systemImage: account.type.iconName)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: selectedAccountId != nil
                                                    ? (accountManager.accounts.first(where: { $0.id == selectedAccountId })?.type.iconName ?? "building.columns")
                                                    : "building.columns")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(DS.Colors.accent)
                                                    .frame(width: 36, height: 36)
                                                    .background(DS.Colors.accentLight, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                                if let id = selectedAccountId,
                                                   let account = accountManager.accounts.first(where: { $0.id == id }) {
                                                    Text(account.name)
                                                        .font(DS.Typography.body.weight(.medium))
                                                        .foregroundStyle(DS.Colors.text)
                                                } else {
                                                    Text("None")
                                                        .font(DS.Typography.body)
                                                        .foregroundStyle(DS.Colors.textTertiary)
                                                }

                                                Spacer()

                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(DS.Colors.textTertiary)
                                            }
                                            .padding(14)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                    }

                                    // Goal row (income only)
                                    if !goalManager.activeGoals.isEmpty && transactionType == .income {
                                        if !accountManager.accounts.isEmpty {
                                            Rectangle().fill(DS.Colors.grid).frame(height: 1)
                                        }

                                        Text("Contribute to Goal")
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)

                                        Menu {
                                            Button {
                                                selectedGoalId = nil
                                            } label: {
                                                Label("None", systemImage: "minus.circle")
                                            }
                                            Divider()
                                            ForEach(goalManager.activeGoals) { goal in
                                                Button {
                                                    selectedGoalId = goal.id
                                                } label: {
                                                    Label(goal.name, systemImage: goal.icon)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: selectedGoalId != nil
                                                    ? (goalManager.activeGoals.first(where: { $0.id == selectedGoalId })?.icon ?? "target")
                                                    : "target")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(DS.Colors.positive)
                                                    .frame(width: 36, height: 36)
                                                    .background(DS.Colors.positive.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                                                if let id = selectedGoalId,
                                                   let goal = goalManager.activeGoals.first(where: { $0.id == id }) {
                                                    Text(goal.name)
                                                        .font(DS.Typography.body.weight(.medium))
                                                        .foregroundStyle(DS.Colors.text)
                                                } else {
                                                    Text("None")
                                                        .font(DS.Typography.body)
                                                        .foregroundStyle(DS.Colors.textTertiary)
                                                }

                                                Spacer()

                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(DS.Colors.textTertiary)
                                            }
                                            .padding(14)
                                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(DS.Format.cents(from: amountText) <= 0 || index == nil)
                }
            }
        }  // Close NavigationView
        .onAppear {
            guard let idx = index else { return }
            let t = store.transactions[idx]
            amountText = String(format: "%.2f", Double(t.amount) / 100.0)
            note = t.note
            date = t.date
            category = t.category
            paymentMethod = t.paymentMethod
            transactionType = t.type
            selectedAccountId = t.accountId
            selectedGoalId = t.linkedGoalId
        }
        .sheet(isPresented: $showAddCategory) {
            FullCategoryEditor(
                customCategories: $store.customCategoriesWithIcons,
                onSave: { newCategory in
                    // 1. اضافه کن
                    if !store.customCategoriesWithIcons.contains(where: { $0.id == newCategory.id }) {
                        store.customCategoriesWithIcons.append(newCategory)
                    }
                    
                    // 2. Sync names
                    if !store.customCategoryNames.contains(newCategory.name) {
                        store.customCategoryNames.append(newCategory.name)
                        store.customCategoryNames.sort { $0.lowercased() < $1.lowercased() }
                    }
                    
                    // 3. انتخاب
                    category = .custom(newCategory.name)
                    
                    // 4. Save
                    Task {
                        try? await SupabaseManager.shared.saveStore(store)
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingCustomCategory) { customCat in
            FullCategoryEditor(
                customCategories: $store.customCategoriesWithIcons,
                editingCategory: customCat,
                onSave: { category in
                    // 1. Update
                    if let index = store.customCategoriesWithIcons.firstIndex(where: { $0.id == category.id }) {
                        store.customCategoriesWithIcons[index] = category
                    }
                    
                    // 2. Sync names
                    if !store.customCategoryNames.contains(category.name) {
                        store.customCategoryNames.append(category.name)
                        store.customCategoryNames.sort { $0.lowercased() < $1.lowercased() }
                    }
                    
                    // 3. Save
                    Task {
                        try? await SupabaseManager.shared.saveStore(store)
                    }
                }
            )
            .presentationDetents([.medium, .large])
        }
        .alert("Save Failed", isPresented: $showSaveFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your changes could not be saved. Please try again.")
        }
    }

    private func saveChanges() {
        guard let idx = index else { return }
        let amount = DS.Format.cents(from: amountText)
        guard amount > 0 else { return }

        let oldTransaction = store.transactions[idx]

        let newTransaction = Transaction(
            id: oldTransaction.id,
            amount: amount,
            date: date,
            category: category,
            note: note,
            paymentMethod: paymentMethod,
            type: transactionType,
            attachmentData: oldTransaction.attachmentData,
            attachmentType: oldTransaction.attachmentType,
            accountId: selectedAccountId,
            isFlagged: oldTransaction.isFlagged,
            linkedGoalId: selectedGoalId,
            lastModified: Date()
        )
        var result: PersistenceResult = .localSaveFailed
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            result = TransactionService.performEdit(old: oldTransaction, new: newTransaction, store: &store)
        }
        switch result {
        case .noChange:
            dismiss()  // transaction was already gone — just close
        case .savedLocally:
            // Transaction record is durably saved. Balance/goal delta side-effects are
            // still in flight (async) — haptic + dismiss reflects the save, not full settlement.
            Haptics.success()
            AnalyticsManager.shared.track(.transactionEdited)
            dismiss()
        case .localSaveFailed:
            showSaveFailedAlert = true
        }
    }
}
