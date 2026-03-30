import SwiftUI

// MARK: - Add Transaction Sheet

struct AddTransactionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var store: Store
    @State private var showPaywall = false
    @State private var showLimitAlert = false
    
    @State private var amountText = ""
    @State private var note = ""
    private let initialMonth: Date
    @State private var date: Date
    @State private var category: Category = .groceries
    @State private var paymentMethod: PaymentMethod = .card
    @State private var transactionType: TransactionType = .expense  // ← جدید
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var editingCustomCategory: CustomCategoryModel?  // ← جدید
    @State private var attachmentData: Data? = nil
    @State private var attachmentType: AttachmentType? = nil
    @State private var showImagePicker = false
    @State private var showDocumentPicker = false
    @State private var showAttachmentOptions = false
    @State private var selectedAccountId: UUID? = nil
    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var goalManager = GoalManager.shared
    @State private var selectedGoalId: UUID? = nil
    @State private var showSaveFailedAlert = false

    init(store: Binding<Store>, initialMonth: Date) {
        self._store = store
        self.initialMonth = initialMonth

        let cal = Calendar.current
        let now = Date()

        // اگر ماه جاریه → امروز
        if cal.isDate(initialMonth, equalTo: now, toGranularity: .month) {
            self._date = State(initialValue: now)
        } else {
            // اگر ماه دیگه‌ست → روز اول ماه
            let comps = cal.dateComponents([.year, .month], from: initialMonth)
            let d = cal.date(
                from: DateComponents(
                    year: comps.year,
                    month: comps.month,
                    day: 1,
                    hour: 12
                )
            )
            self._date = State(initialValue: d ?? initialMonth)
        }
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

                        // ── Attachment Card ──
                        DS.Card {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Attachment")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)

                                if let attachmentData, let attachmentType {
                                    HStack(spacing: 12) {
                                        Image(systemName: attachmentType == .image ? "photo" : "doc.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundStyle(DS.Colors.accent)
                                            .frame(width: 44, height: 44)
                                            .background(DS.Colors.accentLight, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(attachmentType == .image ? "Image" : "Document")
                                                .font(DS.Typography.body.weight(.medium))
                                                .foregroundStyle(DS.Colors.text)
                                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(attachmentData.count), countStyle: .file))")
                                                .font(DS.Typography.caption)
                                                .foregroundStyle(DS.Colors.subtext)
                                        }

                                        Spacer()

                                        Button {
                                            withAnimation {
                                                self.attachmentData = nil
                                                self.attachmentType = nil
                                            }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 22))
                                                .foregroundStyle(DS.Colors.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(14)
                                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                } else {
                                    Button {
                                        showAttachmentOptions = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "paperclip")
                                                .font(.system(size: 15, weight: .medium))
                                            Text("Add Attachment")
                                                .font(DS.Typography.body.weight(.medium))
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(DS.ColoredButton())
                                }
                            }
                        }

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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Add Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveTransaction()
                }
                .disabled(DS.Format.cents(from: amountText) <= 0)
            }
        }
        .keyboardManagement()  // Global keyboard handling
        }  // ← Close NavigationView
        .confirmationDialog("Add attachment", isPresented: $showAttachmentOptions) {
            Button("Attach Photo") {
                showImagePicker = true
            }
            Button("Attach File") {
                showDocumentPicker = true
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showAddCategory) {
            FullCategoryEditor(
                customCategories: $store.customCategoriesWithIcons,
                onSave: { newCategory in
                    // 1. مستقیماً اضافه کن
                    if !store.customCategoriesWithIcons.contains(where: { $0.id == newCategory.id }) {
                        store.customCategoriesWithIcons.append(newCategory)
                    }
                    
                    // 2. Sync names
                    if !store.customCategoryNames.contains(newCategory.name) {
                        store.customCategoryNames.append(newCategory.name)
                        store.customCategoryNames.sort { $0.lowercased() < $1.lowercased() }
                    }
                    
                    // 3. انتخاب کن
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
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(imageData: $attachmentData, attachmentType: $attachmentType)
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(fileData: $attachmentData, attachmentType: $attachmentType)
        }
        .alert("Transaction Limit Reached", isPresented: $showLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Free users can create up to 50 transactions. Pro users have unlimited transactions.")
        }
        .sheet(isPresented: $showPaywall) {
        }
        .alert("Save Failed", isPresented: $showSaveFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your transaction could not be saved. Please try again.")
        }
    }
    
    private func saveTransaction() {
        let amount = DS.Format.cents(from: amountText)
        guard amount > 0 else { return }

        let newTransaction = Transaction(
            amount: amount,
            date: date,
            category: category,
            note: note,
            paymentMethod: paymentMethod,
            type: transactionType,
            attachmentData: attachmentData,
            attachmentType: attachmentType,
            accountId: selectedAccountId,
            linkedGoalId: selectedGoalId
        )
        var result: PersistenceResult = .localSaveFailed
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            result = TransactionService.performAdd(newTransaction, store: &store)
        }
        if case .localSaveFailed = result {
            showSaveFailedAlert = true
            return
        }
        // Transaction record is durably saved. Balance/goal side-effects are still
        // in flight (async) — haptic + dismiss reflects the save, not full settlement.
        Haptics.transactionAdded()
        AnalyticsManager.shared.track(.transactionAdded(isExpense: transactionType == .expense))
        AnalyticsManager.shared.checkFirstTransaction()
        dismiss()
    }
}
