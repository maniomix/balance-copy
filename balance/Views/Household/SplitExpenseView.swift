import SwiftUI

// ============================================================
// MARK: - Split Expense View
// ============================================================

struct SplitExpenseView: View {
    @Binding var store: Store
    @StateObject private var manager = HouseholdManager.shared
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var note = ""
    @State private var selectedCategory: Category = .dining
    @State private var selectedSplitRule: SplitRule = .equal
    @State private var paidByMe = true
    @State private var customPercentage: Double = 50
    @State private var customAmountMeText = ""
    @State private var date = Date()
    @State private var alsoAddToStore = true

    private var amountCents: Int { DS.Format.cents(from: amountText) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    amountSection
                    splitRuleSection
                    detailsSection
                    previewSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Split Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addExpense() }
                        .disabled(amountCents <= 0)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Amount

    private var amountSection: some View {
        DS.Card {
            VStack(spacing: 12) {
                Text("Amount")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .multilineTextAlignment(.center)

                // Paid by toggle
                HStack(spacing: 12) {
                    Text("Paid by")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                    Picker("", selection: $paidByMe) {
                        Text("Me").tag(true)
                        if let partner = manager.household?.partner {
                            Text(partner.displayName).tag(false)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: - Split Rule

    private var splitRuleSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Split Method")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    splitButton(.equal)
                    splitButton(.paidByMe)
                    splitButton(.paidByPartner)
                }

                // Custom percentage slider
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if case .percentage = selectedSplitRule {
                            selectedSplitRule = .equal
                        } else {
                            selectedSplitRule = .percentage(customPercentage)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "chart.pie.fill")
                            .font(.system(size: 12))
                        Text("Custom %")
                            .font(DS.Typography.caption.weight(.medium))
                    }
                    .foregroundStyle(isPercentage ? .white : DS.Colors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isPercentage ? DS.Colors.accent : DS.Colors.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }

                if isPercentage {
                    VStack(spacing: 6) {
                        Slider(value: $customPercentage, in: 0...100, step: 5)
                            .tint(DS.Colors.accent)
                            .onChange(of: customPercentage) { _, val in
                                selectedSplitRule = .percentage(val)
                            }
                        HStack {
                            Text("Me: \(Int(customPercentage))%")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text("Partner: \(100 - Int(customPercentage))%")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.text)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    private var isPercentage: Bool {
        if case .percentage = selectedSplitRule { return true }
        return false
    }

    private func splitButton(_ rule: SplitRule) -> some View {
        let isSelected = selectedSplitRule == rule
        return Button {
            Haptics.light()
            selectedSplitRule = rule
        } label: {
            VStack(spacing: 4) {
                Image(systemName: rule.icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(rule.displayName)
                    .font(DS.Typography.caption.weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : DS.Colors.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? DS.Colors.accent : DS.Colors.surface2)
            )
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                TextField("Note", text: $note)
                    .font(DS.Typography.body)

                // Category picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.allCategories, id: \.self) { cat in
                            let isSelected = selectedCategory == cat
                            Button {
                                selectedCategory = cat
                            } label: {
                                Text(cat.title)
                                    .font(DS.Typography.caption.weight(.medium))
                                    .foregroundStyle(isSelected ? .white : DS.Colors.text)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        isSelected ? DS.Colors.accent : DS.Colors.surface2,
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                }

                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .font(DS.Typography.body)

                Toggle("Also add to my transactions", isOn: $alsoAddToStore)
                    .font(DS.Typography.body)
                    .tint(DS.Colors.accent)
            }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Split Preview")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if let h = manager.household, amountCents > 0 {
                    let currentUserId = authManager.currentUser?.uid ?? ""
                    let paidByUser = paidByMe ? currentUserId : (h.partner?.userId ?? "")
                    let tempExpense = SplitExpense(
                        householdId: h.id,
                        amount: amountCents,
                        paidBy: paidByUser,
                        splitRule: selectedSplitRule
                    )
                    let splits = tempExpense.splits(members: h.members)

                    ForEach(h.members) { member in
                        let share = splits.first(where: { $0.userId == member.userId })?.amount ?? 0
                        let isPayer = member.userId == paidByUser
                        HStack {
                            Text(member.displayName)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.text)
                            if isPayer {
                                Text("(paid)")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.accent)
                            }
                            Spacer()
                            Text(DS.Format.money(share))
                                .font(DS.Typography.number)
                                .foregroundStyle(DS.Colors.text)
                        }
                    }

                    let owed = tempExpense.payerOwed(members: h.members)
                    if owed > 0 {
                        Divider()
                        HStack {
                            let payerName = paidByMe ? "You" : (h.partner?.displayName ?? "Partner")
                            Text("\(payerName) is owed back")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Spacer()
                            Text(DS.Format.money(owed))
                                .font(DS.Typography.number.weight(.bold))
                                .foregroundStyle(DS.Colors.positive)
                        }
                    }
                } else {
                    Text("Enter an amount to see the split")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }

    // MARK: - Action

    private func addExpense() {
        guard let h = manager.household, amountCents > 0 else { return }

        let currentUserId = authManager.currentUser?.uid ?? ""
        let paidByUser = paidByMe ? currentUserId : (h.partner?.userId ?? "")
        let txnId = UUID()

        manager.addSplitExpense(
            amount: amountCents,
            paidBy: paidByUser,
            splitRule: selectedSplitRule,
            category: selectedCategory.storageKey,
            note: note,
            date: date,
            transactionId: txnId
        )

        // Also add as personal transaction if toggled
        if alsoAddToStore {
            let splits = SplitExpense(
                householdId: h.id,
                amount: amountCents,
                paidBy: paidByUser,
                splitRule: selectedSplitRule
            ).splits(members: h.members)
            let myShare = splits.first(where: { $0.userId == currentUserId })?.amount ?? amountCents

            let txn = Transaction(
                id: txnId,
                amount: myShare,
                date: date,
                category: selectedCategory,
                note: note.isEmpty ? "Split: \(selectedSplitRule.displayName)" : "Split: \(note)",
                type: .expense
            )
            // Intentionally bypasses TransactionService — split expenses are household-
            // originated records with no balance/goal side-effects. Persistence is handled
            // by ContentView's onChange(of: store) safety-net save.
            store.add(txn)
        }

        Haptics.success()
        AnalyticsManager.shared.track(.splitExpenseAdded)
        dismiss()
    }
}
