import SwiftUI

// MARK: - Transaction Form
//
// Single shared form view bound to a `TransactionDraftStore`. Both the Add
// and Edit flows mount this view via `TransactionSheet`.
//
// The form is layout-only: it owns no save logic and no sheet presentation.
// Its caller is responsible for navigation chrome, attachment pickers, and
// the category editor sheet (via the callbacks it accepts).

struct TransactionForm: View {
    @ObservedObject var draftStore: TransactionDraftStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Bound app store — needed for the category list (`store.allCategories`)
    /// and custom-category icon/color lookups. The form may also write back
    /// when the user creates/deletes a custom category through the editor.
    @Binding var store: Store

    let onAddCategory: () -> Void
    let onEditCategory: ((CustomCategoryModel) -> Void)?
    let onPickAttachment: () -> Void

    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var goalManager = GoalManager.shared

    // Validation surfacing (e.g. red border on the amount field). The save
    // button itself is owned by the wrapping sheet.
    private var validation: DraftValidation {
        draftStore.validate(hasAccounts: !accountManager.accounts.isEmpty)
    }

    private var amountIssue: Bool {
        switch validation {
        case .ok: return false
        case .invalid(let issues):
            return issues.contains(.amountMissing) || issues.contains(.amountNonPositive)
        }
    }

    private var categoryIssue: Bool {
        if case .invalid(let issues) = validation, issues.contains(.categoryMissing) {
            return true
        }
        return false
    }

    private var accountIssue: Bool {
        if case .invalid(let issues) = validation, issues.contains(.accountMissing) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 16) {
            if let suggestion = draftStore.merchantSuggestion {
                merchantSuggestionBanner(suggestion)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            typeSegmented
            amountCard
            if draftStore.draft.type == .expense {
                categoryCard
            }
            detailsCard
            if let hint = draftStore.allocationHint, draftStore.draft.type == .income {
                allocationHintBanner(hint)
                    .transition(.opacity)
            }
            dateCard
            if isFutureDated {
                futureDateNotice
                    .transition(.opacity)
            }
            noteCard
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85),
                   value: draftStore.merchantSuggestion)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                   value: draftStore.allocationHint)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18),
                   value: isFutureDated)
        .onChange(of: draftStore.draft.note) { _, _ in
            draftStore.refreshSuggestions(in: store)
        }
        .onChange(of: draftStore.draft.amountText) { _, _ in
            // Allocation hint depends on amount; merchant suggestion doesn't,
            // but refreshing both is cheap.
            draftStore.refreshSuggestions(in: store)
        }
        .onChange(of: draftStore.draft.type) { _, _ in
            draftStore.refreshSuggestions(in: store)
        }
    }

    // MARK: - Suggestion banners

    private func merchantSuggestionBanner(_ s: MerchantSuggestion) -> some View {
        let categoryTint: Color = {
            if case .custom(let name) = s.category { return store.customCategoryColor(for: name) }
            return s.category.tint
        }()
        let categoryIcon: String = {
            if case .custom(let name) = s.category { return store.customCategoryIcon(for: name) }
            return s.category.icon
        }()

        return DS.Card(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 32, height: 32)
                    .background(DS.Colors.accentLight,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Looks like \(s.merchantDisplay)")
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Image(systemName: categoryIcon)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(categoryTint)
                        Text(s.category.title)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        if let cents = s.suggestedAmountCents, cents > 0 {
                            Text("· \(DS.Format.currency(cents))")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }

                Spacer(minLength: 4)

                Button {
                    draftStore.applyMerchantSuggestion()
                    Haptics.success()
                } label: {
                    Text("Apply")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(DS.Colors.accentLight, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    draftStore.dismissMerchantSuggestion()
                    Haptics.selection()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(DS.Colors.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func allocationHintBanner(_ hint: AllocationHint) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.positive)
            Text(hint.summary)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Colors.positive.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Type segmented

    private var typeSegmented: some View {
        DS.Card(padding: 6) {
            HStack(spacing: 4) {
                segmentedButton(.expense, icon: "arrow.up.right", title: "Expense")
                segmentedButton(.income, icon: "arrow.down.left", title: "Income")
            }
        }
    }

    private func segmentedButton(_ type: TransactionType, icon: String, title: String) -> some View {
        let selected = draftStore.draft.type == type
        let tint: Color = type == .expense ? DS.Colors.danger : DS.Colors.positive
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                draftStore.setType(type)
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? tint : DS.Colors.subtext)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                selected ? tint.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Amount

    private var amountCard: some View {
        DS.Card(padding: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Amount")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    if amountIssue, !draftStore.draft.amountText.isEmpty {
                        Text(validation.firstIssue?.message ?? "")
                            .font(DS.Typography.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.danger)
                            .transition(.opacity)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(CurrencyFormatter.currentSymbol)
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textTertiary)

                    TextField("0.00", text: $draftStore.draft.amountText)
                        .keyboardType(.decimalPad)
                        .font(DS.Typography.heroAmount)
                        .foregroundStyle(typeTint)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel(draftStore.draft.type == .income
                                            ? "Income amount in \(CurrencyFormatter.currentSymbol)"
                                            : "Expense amount in \(CurrencyFormatter.currentSymbol)")
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    amountIssue && !draftStore.draft.amountText.isEmpty
                        ? DS.Colors.danger.opacity(0.5)
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
        .animation(.easeInOut(duration: 0.18), value: amountIssue)
    }

    private var typeTint: Color {
        draftStore.draft.type == .expense ? DS.Colors.text : DS.Colors.positive
    }

    // MARK: - Future-date notice
    //
    // Per the rebuild plan: future-dated transactions are warned, not
    // blocked. Saving a tx for tomorrow is occasionally legitimate
    // (scheduled rent, post-dated reimbursement) so we don't reject it.

    private var isFutureDated: Bool {
        Calendar.current.startOfDay(for: draftStore.draft.date)
            > Calendar.current.startOfDay(for: Date())
    }

    private var futureDateNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.warning)
            Text("This transaction is dated in the future.")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Colors.warning.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Category

    private var categoryCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Category")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    if categoryIssue {
                        Text(DraftValidationIssue.categoryMissing.message)
                            .font(DS.Typography.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.danger)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: 10)],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(store.allCategories, id: \.self) { c in
                        categoryChip(c)
                    }
                    addCategoryChip
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    categoryIssue ? DS.Colors.danger.opacity(0.4) : Color.clear,
                    lineWidth: 1.5
                )
        )
    }

    private func categoryChip(_ c: Category) -> some View {
        let selected = draftStore.draft.category == c
        let tint: Color = {
            if case .custom(let name) = c { return store.customCategoryColor(for: name) }
            return c.tint
        }()
        let icon: String = {
            if case .custom(let name) = c { return store.customCategoryIcon(for: name) }
            return c.icon
        }()

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                draftStore.draft.category = c
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 13, weight: .medium))
                Text(c.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .medium, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? tint : DS.Colors.subtext)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                selected ? tint.opacity(0.10) : DS.Colors.surface2,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(selected ? tint.opacity(0.3) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.title)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .contextMenu {
            if case .custom(let name) = c {
                Button {
                    if let model = store.customCategoriesWithIcons.first(where: { $0.name == name }) {
                        onEditCategory?(model)
                    }
                } label: { Label("Edit Category", systemImage: "pencil") }

                Button(role: .destructive) {
                    if draftStore.draft.category == c { draftStore.draft.category = .other }
                    store.deleteCustomCategory(name: name)
                    Task { try? await SupabaseManager.shared.saveStore(store) }
                } label: { Label("Delete Category", systemImage: "trash") }
            }
        }
    }

    private var addCategoryChip: some View {
        Button(action: onAddCategory) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                Text("Add").font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(DS.Colors.accent)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.Colors.accentLight, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Details (account / goal / payment / attachment)

    private var detailsCard: some View {
        DS.Card {
            VStack(spacing: 0) {
                if !accountManager.accounts.isEmpty {
                    accountRow
                    rowDivider
                }

                if draftStore.draft.type == .income && !goalManager.activeGoals.isEmpty {
                    goalRow
                    rowDivider
                }

                paymentRow
                rowDivider
                attachmentRow
            }
        }
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(DS.Colors.grid)
            .frame(height: 1)
            .padding(.vertical, 12)
    }

    // -- Account row --
    private var accountRow: some View {
        let selected = accountManager.accounts.first(where: { $0.id == draftStore.draft.accountId })
        return Menu {
            Button {
                draftStore.draft.accountId = nil
            } label: { Label("None", systemImage: "minus.circle") }
            Divider()
            ForEach(accountManager.accounts) { account in
                Button {
                    draftStore.draft.accountId = account.id
                } label: { Label(account.name, systemImage: account.type.iconName) }
            }
        } label: {
            detailRowContent(
                icon: selected?.type.iconName ?? "building.columns",
                iconTint: DS.Colors.accent,
                iconBg: DS.Colors.accentLight,
                title: "Account",
                value: selected?.name ?? "None",
                valueIsPlaceholder: selected == nil,
                trailingIcon: "chevron.up.chevron.down",
                showsError: accountIssue && selected == nil
            )
        }
    }

    // -- Goal row (income only) --
    private var goalRow: some View {
        let selected = goalManager.activeGoals.first(where: { $0.id == draftStore.draft.linkedGoalId })
        return Menu {
            Button {
                draftStore.draft.linkedGoalId = nil
            } label: { Label("None", systemImage: "minus.circle") }
            Divider()
            ForEach(goalManager.activeGoals) { goal in
                Button {
                    draftStore.draft.linkedGoalId = goal.id
                } label: { Label(goal.name, systemImage: goal.icon) }
            }
        } label: {
            detailRowContent(
                icon: selected?.icon ?? "target",
                iconTint: DS.Colors.positive,
                iconBg: DS.Colors.positive.opacity(0.10),
                title: "Contribute to Goal",
                value: selected?.name ?? "None",
                valueIsPlaceholder: selected == nil,
                trailingIcon: "chevron.up.chevron.down",
                showsError: false
            )
        }
    }

    // -- Payment row (inline two-tile selector) --
    private var paymentRow: some View {
        HStack(spacing: 12) {
            iconTile(systemName: draftStore.draft.paymentMethod.icon,
                     tint: draftStore.draft.paymentMethod.tint,
                     bg: draftStore.draft.paymentMethod.tint.opacity(0.10))

            Text("Payment")
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Colors.text)

            Spacer()

            HStack(spacing: 6) {
                ForEach(PaymentMethod.allCases, id: \.self) { method in
                    paymentPill(method)
                }
            }
        }
    }

    private func paymentPill(_ method: PaymentMethod) -> some View {
        let selected = draftStore.draft.paymentMethod == method
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                draftStore.draft.paymentMethod = method
            }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: method.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(method.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(selected ? method.tint : DS.Colors.subtext)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                selected ? method.tint.opacity(0.10) : DS.Colors.surface2,
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(selected ? method.tint.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // -- Attachment row --
    private var attachmentRow: some View {
        Group {
            if let data = draftStore.draft.attachmentData,
               let kind = draftStore.draft.attachmentType {
                HStack(spacing: 12) {
                    iconTile(systemName: kind == .image ? "photo" : "doc.fill",
                             tint: DS.Colors.accent,
                             bg: DS.Colors.accentLight)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind == .image ? "Image attached" : "Document attached")
                            .font(DS.Typography.body.weight(.medium))
                            .foregroundStyle(DS.Colors.text)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(data.count),
                                                      countStyle: .file))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer()

                    Button {
                        withAnimation { draftStore.clearAttachment() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DS.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button(action: onPickAttachment) {
                    HStack(spacing: 12) {
                        iconTile(systemName: "paperclip",
                                 tint: DS.Colors.accent,
                                 bg: DS.Colors.accentLight)

                        Text("Add Attachment")
                            .font(DS.Typography.body.weight(.medium))
                            .foregroundStyle(DS.Colors.text)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Colors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Date

    private var dateCard: some View {
        DS.Card {
            HStack {
                iconTile(systemName: "calendar",
                         tint: DS.Colors.accent,
                         bg: DS.Colors.accentLight)
                Text("Date")
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                DatePicker("", selection: $draftStore.draft.date, displayedComponents: [.date])
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
        }
    }

    // MARK: - Note

    private var noteCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Note")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                TextField(
                    draftStore.draft.type == .income ? "e.g. Salary" : "e.g. Weekly groceries",
                    text: $draftStore.draft.note
                )
                .font(DS.Typography.body)
                .padding(14)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: - Row primitives

    private func iconTile(systemName: String, tint: Color, bg: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func detailRowContent(
        icon: String,
        iconTint: Color,
        iconBg: Color,
        title: String,
        value: String,
        valueIsPlaceholder: Bool,
        trailingIcon: String,
        showsError: Bool
    ) -> some View {
        let a11yValue = valueIsPlaceholder ? "not set" : value
        return HStack(spacing: 12) {
            iconTile(systemName: icon, tint: iconTint, bg: iconBg)

            Text(title)
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Colors.text)

            Spacer()

            Text(value)
                .font(DS.Typography.body)
                .foregroundStyle(valueIsPlaceholder
                                 ? (showsError ? DS.Colors.danger : DS.Colors.textTertiary)
                                 : DS.Colors.text)
                .lineLimit(1)

            Image(systemName: trailingIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(a11yValue)")
        .accessibilityAddTraits(.isButton)
    }
}
