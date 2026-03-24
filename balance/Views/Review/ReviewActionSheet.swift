import SwiftUI

// ============================================================
// MARK: - Review Action Sheet
// ============================================================
//
// Detail panel for acting on a single ReviewItem.
// Provides context and the appropriate action UI for each type.
// ============================================================

struct ReviewActionSheet: View {
    let item: ReviewItem
    @Binding var store: Store
    @StateObject private var engine = ReviewEngine.shared
    @Environment(\.dismiss) private var dismiss

    // State for actions
    @State private var selectedCategory: Category = .other
    @State private var normalizedName: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        headerSection
                        transactionPreview
                        actionSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Review Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            .onAppear {
                selectedCategory = item.suggestedCategory ?? .other
                normalizedName = item.merchantName ?? ""
            }
            .alert("Remove Duplicates?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Remove \(item.transactionIds.count - 1) Duplicate(s)", role: .destructive) {
                    engine.markDuplicate(item: item, store: &store)
                    Haptics.success()
                    dismiss()
                }
            } message: {
                Text("This will keep the first transaction and permanently remove the other \(item.transactionIds.count - 1) duplicate(s).")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(item.type.color.opacity(0.15))
                            .frame(width: 44, height: 44)

                        Image(systemName: item.type.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(item.type.color)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.type.displayName)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)

                        HStack(spacing: 6) {
                            Text(item.priority.displayName + " Priority")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(item.priority.color)

                            Text("·")
                                .foregroundStyle(DS.Colors.subtext)

                            Text("\(item.transactionIds.count) transaction(s)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }

                    Spacer()
                }

                // Reason
                Text(item.reason)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)

                // Spike context
                if let spike = item.spikeAmount, let avg = item.spikeAverage {
                    HStack(spacing: 16) {
                        VStack(spacing: 2) {
                            Text("This charge")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(spike))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.danger)
                        }
                        VStack(spacing: 2) {
                            Text("Category avg")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(avg))")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                        }
                        VStack(spacing: 2) {
                            Text("Multiple")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                            Text("\(String(format: "%.1f", Double(spike) / Double(max(1, avg))))x")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.warning)
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Transaction Preview

    private var transactionPreview: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Linked Transactions")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                ForEach(item.transactionIds.prefix(5), id: \.self) { txId in
                    if let tx = store.transactions.first(where: { $0.id == txId }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(tx.category.tint.opacity(0.12))
                                    .frame(width: 32, height: 32)

                                Image(systemName: tx.category.icon)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(tx.category.tint)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.note.isEmpty ? tx.category.title : tx.note)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)
                                    .lineLimit(1)

                                Text(formatDate(tx.date))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            }

                            Spacer()

                            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(tx.amount))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                        }

                        if txId != item.transactionIds.prefix(5).last {
                            Divider().opacity(0.3)
                        }
                    }
                }

                if item.transactionIds.count > 5 {
                    Text("+ \(item.transactionIds.count - 5) more")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }

    // MARK: - Action Section

    @ViewBuilder
    private var actionSection: some View {
        switch item.type {
        case .uncategorized:
            categoryPickerAction
        case .possibleDuplicate:
            duplicateAction
        case .spendingSpike:
            spikeAction
        case .recurringCandidate:
            recurringAction
        case .merchantNormalization:
            merchantAction
        }
    }

    // ─── Uncategorized: Category Picker ───

    private var categoryPickerAction: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Assign Category")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if let suggested = item.suggestedCategory {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(DS.Colors.accent)
                        Text("Suggested: \(suggested.title)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }

                // Category grid
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()),
                    GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(Category.allCases, id: \.self) { cat in
                        Button {
                            selectedCategory = cat
                            Haptics.light()
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(selectedCategory == cat ? .white : cat.tint)

                                Text(cat.title)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(selectedCategory == cat ? .white : DS.Colors.text)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == cat ? cat.tint : cat.tint.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                    }
                }

                Button {
                    engine.assignCategory(item: item, category: selectedCategory, store: &store)
                    Haptics.success()
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                        Text("Apply \(selectedCategory.title)")
                    }
                }
                .buttonStyle(DS.PrimaryButton())
            }
        }
    }

    // ─── Duplicate: Confirm removal ───

    private var duplicateAction: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Handle Duplicates")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                Text("We detected \(item.transactionIds.count) transactions that appear identical. The first one will be kept, and the rest removed.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 10) {
                    Button {
                        showDeleteConfirm = true
                        Haptics.medium()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Remove Duplicates")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.Colors.danger, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        engine.dismiss(item)
                        Haptics.light()
                        dismiss()
                    } label: {
                        Text("Not Duplicates")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // ─── Spike: Review or dismiss ───

    private var spikeAction: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review Spike")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                Text("This charge is significantly higher than usual for this category. If it's expected (e.g., annual payment, one-time purchase), you can dismiss it.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 10) {
                    Button {
                        engine.dismiss(item)
                        Haptics.light()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Looks Normal")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.positive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.Colors.positive.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    Button {
                        engine.resolve(item)
                        // Flag all transactions in this review item
                        for txId in item.transactionIds {
                            store.flagTransaction(id: txId)
                        }
                        Haptics.medium()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Flag It")
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.warning)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.Colors.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // ─── Recurring: Create recurring transaction ───

    private var recurringAction: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create Recurring")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                Text("This merchant appears regularly in your transactions. Would you like to track it as a recurring expense?")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)

                if let name = item.merchantName {
                    HStack(spacing: 6) {
                        Image(systemName: "repeat")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Colors.accent)
                        Text(name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        engine.createRecurring(item: item, store: &store)
                        Haptics.success()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Create Recurring")
                        }
                    }
                    .buttonStyle(DS.PrimaryButton())

                    Button {
                        engine.dismiss(item)
                        Haptics.light()
                        dismiss()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    // ─── Merchant Normalization ───

    private var merchantAction: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Normalize Merchant Name")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                Text("These transactions appear to be from the same merchant but have different names. Choose or edit the preferred name.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.subtext)

                TextField("Merchant name", text: $normalizedName)
                    .textFieldStyle(DS.TextFieldStyle())

                HStack(spacing: 10) {
                    Button {
                        let name = normalizedName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        engine.normalizeMerchant(item: item, normalizedName: name, store: &store)
                        Haptics.success()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Apply to \(item.transactionIds.count) Transactions")
                        }
                    }
                    .buttonStyle(DS.PrimaryButton())
                    .disabled(normalizedName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }
}
