import SwiftUI

// MARK: - Goal Rules View
//
// Lists every `GoalAllocationRule` attached to one Goal, lets the user
// add / edit / disable / delete rules. Rules live on `Store` (value-type
// list) and persist via the usual store-save path on the parent.

struct GoalRulesView: View {

    let goal: Goal
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var showAddRule = false
    @State private var editingRule: GoalAllocationRule?

    private var rules: [GoalAllocationRule] {
        store.goalAllocationRules
            .filter { $0.goalId == goal.id }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                return a.createdAt < b.createdAt
            }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    if rules.isEmpty {
                        emptyState
                    } else {
                        ForEach(rules) { rule in
                            ruleCard(rule)
                        }
                    }
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Auto-save rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRule = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(DS.Colors.accent)
                    }
                    .accessibilityLabel("Add rule")
                }
            }
            .sheet(isPresented: $showAddRule) {
                EditAllocationRuleSheet(goal: goal, store: $store, rule: nil)
            }
            .sheet(item: $editingRule) { rule in
                EditAllocationRuleSheet(goal: goal, store: $store, rule: rule)
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        let tint = GoalColorHelper.color(for: goal.colorToken)
        return DS.Card {
            HStack(spacing: 10) {
                Image(systemName: goal.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.name)
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.text)
                    Text("Rules apply when income arrives. You'll review every match before anything moves.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }
                Spacer()
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 36))
                .foregroundStyle(DS.Colors.subtext.opacity(0.5))
            Text("No rules yet")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)
            Text("Add a rule to suggest contributions automatically when matching income shows up.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button { showAddRule = true } label: {
                Label("Add rule", systemImage: "plus")
                    .font(DS.Typography.body.weight(.semibold))
            }
            .buttonStyle(DS.PrimaryButton())
        }
        .padding(.vertical, 24)
    }

    // MARK: Rule card

    private func ruleCard(_ rule: GoalAllocationRule) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name)
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.text)
                        Text(ruleSummary(rule))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    Spacer()
                    Toggle("", isOn: ruleActiveBinding(rule))
                        .labelsHidden()
                        .tint(DS.Colors.accent)
                }
                HStack(spacing: 10) {
                    Button("Edit") { editingRule = rule }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Spacer()
                    Button(role: .destructive) {
                        delete(rule)
                    } label: {
                        Text("Delete")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Colors.danger)
                    }
                }
            }
        }
    }

    private func ruleSummary(_ rule: GoalAllocationRule) -> String {
        let amount: String = {
            switch rule.type {
            case .percentOfIncome: return "\(rule.amount)% of income"
            case .fixedPerIncome:  return DS.Format.money(rule.amount)
            case .fixedMonthly:    return "\(DS.Format.money(rule.amount)) / month"
            case .roundUpExpense:  return "Round-up"
            }
        }()
        let scope: String = {
            switch rule.source {
            case .allIncome: return "all income"
            case .category:  return "category: \(rule.sourceMatch ?? "—")"
            case .payee:     return "payee: \(rule.sourceMatch ?? "—")"
            }
        }()
        return "\(amount) · \(scope)"
    }

    private func ruleActiveBinding(_ rule: GoalAllocationRule) -> Binding<Bool> {
        Binding(
            get: { rule.isActive },
            set: { newValue in
                if let idx = store.goalAllocationRules.firstIndex(where: { $0.id == rule.id }) {
                    store.goalAllocationRules[idx].isActive = newValue
                }
            }
        )
    }

    private func delete(_ rule: GoalAllocationRule) {
        store.goalAllocationRules.removeAll { $0.id == rule.id }
    }
}

// MARK: - Edit Allocation Rule Sheet

private struct EditAllocationRuleSheet: View {

    let goal: Goal
    @Binding var store: Store
    let rule: GoalAllocationRule?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ruleType: AllocationRuleType = .percentOfIncome
    @State private var amountText = ""
    @State private var source: AllocationRuleSource = .allIncome
    @State private var sourceMatch = ""
    @State private var priority: Int = 0
    @State private var isActive = true

    private var isEditing: Bool { rule != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Name")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            TextField("e.g. 10% of paycheck", text: $name)
                                .font(DS.Typography.body)
                                .padding(12)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Rule type")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Picker("Rule type", selection: $ruleType) {
                                ForEach([AllocationRuleType.percentOfIncome, .fixedPerIncome], id: \.self) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 8) {
                                if ruleType == .fixedPerIncome {
                                    Text(DS.Format.currencySymbol())
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                TextField(amountPlaceholder, text: $amountText)
                                    .font(DS.Typography.body)
                                    .keyboardType(.numberPad)
                                if ruleType == .percentOfIncome {
                                    Text("%")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                            .padding(12)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Applies to")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                            Picker("Source", selection: $source) {
                                ForEach(AllocationRuleSource.allCases, id: \.self) { src in
                                    Text(src.displayName).tag(src)
                                }
                            }
                            .pickerStyle(.segmented)

                            if source != .allIncome {
                                TextField(source == .category ? "Category storage key" : "Payee match", text: $sourceMatch)
                                    .font(DS.Typography.body)
                                    .padding(12)
                                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Stepper(value: $priority, in: 0...10) {
                                HStack {
                                    Text("Priority")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                    Spacer()
                                    Text("\(priority)")
                                        .font(DS.Typography.number)
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                            .tint(DS.Colors.accent)

                            Toggle("Active", isOn: $isActive)
                                .tint(DS.Colors.accent)
                                .font(DS.Typography.body)
                        }
                    }
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit rule" : "New rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var amountPlaceholder: String {
        ruleType == .percentOfIncome ? "10" : "100.00"
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedAmount > 0
    }

    private var parsedAmount: Int {
        switch ruleType {
        case .percentOfIncome:
            return Int(amountText) ?? 0
        case .fixedPerIncome:
            return DS.Format.cents(from: amountText)
        case .fixedMonthly, .roundUpExpense:
            return 0
        }
    }

    private func load() {
        guard let r = rule else {
            name = ""
            ruleType = .percentOfIncome
            amountText = ""
            source = .allIncome
            sourceMatch = ""
            priority = 0
            isActive = true
            return
        }
        name = r.name
        ruleType = r.type
        switch r.type {
        case .percentOfIncome:
            amountText = String(r.amount)
        case .fixedPerIncome:
            amountText = DS.Format.currency(r.amount)
        case .fixedMonthly, .roundUpExpense:
            amountText = ""
        }
        source = r.source
        sourceMatch = r.sourceMatch ?? ""
        priority = r.priority
        isActive = r.isActive
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedMatch = sourceMatch.trimmingCharacters(in: .whitespaces)
        let storedMatch = source == .allIncome
            ? nil
            : (trimmedMatch.isEmpty ? nil : trimmedMatch)

        if let r = rule, let idx = store.goalAllocationRules.firstIndex(where: { $0.id == r.id }) {
            store.goalAllocationRules[idx].name = trimmedName
            store.goalAllocationRules[idx].type = ruleType
            store.goalAllocationRules[idx].amount = parsedAmount
            store.goalAllocationRules[idx].source = source
            store.goalAllocationRules[idx].sourceMatch = storedMatch
            store.goalAllocationRules[idx].priority = priority
            store.goalAllocationRules[idx].isActive = isActive
        } else {
            let new = GoalAllocationRule(
                goalId: goal.id,
                name: trimmedName,
                type: ruleType,
                amount: parsedAmount,
                source: source,
                sourceMatch: storedMatch,
                priority: priority,
                isActive: isActive
            )
            store.goalAllocationRules.append(new)
        }
        dismiss()
    }
}
