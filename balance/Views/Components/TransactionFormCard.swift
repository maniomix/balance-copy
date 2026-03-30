import SwiftUI

// MARK: - Insight Row

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(insight.level.color.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: insight.level.icon)
                        .foregroundStyle(insight.level.color)
                        .font(.system(size: 14, weight: .semibold))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(DS.Typography.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(insight.detail)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Month Picker

struct MonthPicker: View {
    @Binding var selectedMonth: Date
    @State private var showMonthYearPicker = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.monthChanged()
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                AnalyticsManager.shared.track(.monthSwitched)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(DS.Colors.subtext)
                    .padding(8)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                Haptics.soft()
                selectedMonth = Date()
                AnalyticsManager.shared.track(.monthSwitched)
            } label: {
                Text("This month")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        Haptics.medium()
                        showMonthYearPicker = true
                    }
            )

            Button {
                Haptics.monthChanged()
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                AnalyticsManager.shared.track(.monthSwitched)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.Colors.subtext)
                    .padding(8)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .sheet(isPresented: $showMonthYearPicker) {
            MonthYearPickerSheet(selectedDate: $selectedMonth)
        }
    }
}

// MARK: - Transaction Form Card

struct TransactionFormCard: View {
    @Binding var amountText: String
    @Binding var note: String
    @Binding var date: Date
    @Binding var category: Category
    @Binding var transactionType: TransactionType
    @Binding var store: Store

    let categories: [Category]
    let onAddCategory: () -> Void
    let onEditCategory: ((CustomCategoryModel) -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            // -- Segmented Control (Expense / Income) --
            segmentedTypeControl

            // -- Hero Amount Input --
            amountSection

            // -- Category Chips (expenses only) --
            if transactionType == .expense {
                categorySection
            }

            // -- Date Selector --
            dateSection

            // -- Note Input --
            noteSection
        }
    }

    // MARK: - Segmented Type Control
    private var segmentedTypeControl: some View {
        DS.Card(padding: 6) {
            HStack(spacing: 4) {
                segmentButton(.expense, icon: "arrow.up.right", title: "Expense")
                segmentButton(.income, icon: "arrow.down.left", title: "Income")
            }
        }
    }

    private func segmentButton(_ type: TransactionType, icon: String, title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                transactionType = type
                if type == .income {
                    category = .other
                    if note.isEmpty { note = "Income" }
                } else if note == "Income" {
                    note = ""
                }
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(
                transactionType == type
                    ? (type == .expense ? DS.Colors.danger : DS.Colors.positive)
                    : DS.Colors.subtext
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                transactionType == type
                    ? (type == .expense ? DS.Colors.danger.opacity(0.10) : DS.Colors.positive.opacity(0.10))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero Amount
    private var amountSection: some View {
        DS.Card(padding: 24) {
            VStack(spacing: 12) {
                Text("Amount")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CurrencyFormatter.currentSymbol)
                        .font(.system(size: 28, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textTertiary)

                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(DS.Typography.heroAmount)
                        .foregroundStyle(DS.Colors.text)
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }

    // MARK: - Category Chips
    private var categorySection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("Category")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.allCategories, id: \.self) { c in
                            categoryChip(c)
                        }
                        addCategoryChip
                    }
                }
            }
        }
    }

    private func categoryChip(_ c: Category) -> some View {
        let isSelected = category == c
        let chipTint: Color = {
            if case .custom(let name) = c {
                return store.customCategoryColor(for: name)
            }
            return c.tint
        }()
        let chipIcon: String = {
            if case .custom(let name) = c {
                return store.customCategoryIcon(for: name)
            }
            return c.icon
        }()

        return Button { category = c } label: {
            HStack(spacing: 7) {
                Image(systemName: chipIcon)
                    .font(.system(size: 13, weight: .medium))
                Text(c.title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? chipTint : DS.Colors.subtext)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isSelected ? chipTint.opacity(0.10) : DS.Colors.surface2,
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? chipTint.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: category)
        .contextMenu {
            if case .custom(let name) = c {
                Button {
                    if let customCat = store.customCategoriesWithIcons.first(where: { $0.name == name }) {
                        onEditCategory?(customCat)
                    }
                } label: {
                    Label("Edit Category", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    if category == c { category = .other }
                    store.deleteCustomCategory(name: name)
                    Task { try? await SupabaseManager.shared.saveStore(store) }
                } label: {
                    Label("Delete Category", systemImage: "trash")
                }
            }
        }
    }

    private var addCategoryChip: some View {
        Button { onAddCategory() } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("Add")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(DS.Colors.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DS.Colors.accentLight, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Date Selector
    private var dateSection: some View {
        DS.Card {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 36, height: 36)
                        .background(DS.Colors.accentLight, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text("Date")
                        .font(DS.Typography.body.weight(.medium))
                        .foregroundStyle(DS.Colors.text)
                }

                Spacer()

                DatePicker("", selection: $date, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }

    // MARK: - Note Input
    private var noteSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Note")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                TextField(transactionType == .income ? "e.g. Salary" : "e.g. Weekly groceries", text: $note)
                    .font(DS.Typography.body)
                    .padding(14)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}
