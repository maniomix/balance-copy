import SwiftUI
import Combine

// MARK: - Create / Edit Goal

struct CreateEditGoalView: View {

    enum Mode: Identifiable {
        case create
        case edit(Goal)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let g): return g.id.uuidString
            }
        }
    }

    let mode: Mode

    var body: some View {
        switch mode {
        case .create:
            CreateGoalWizard()
        case .edit(let goal):
            EditGoalForm(goal: goal)
        }
    }
}

// MARK: - Shared draft state

@MainActor
final class GoalDraft: ObservableObject {
    @Published var name = ""
    @Published var goalType: GoalType = .custom
    @Published var targetAmountText = ""
    @Published var seedAmountText = ""
    @Published var hasTargetDate = false
    @Published var targetDate: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @Published var notes = ""
    @Published var selectedAccountId: UUID?
    @Published var selectedColorToken: String = "accent"

    var targetCents: Int { DS.Format.cents(from: targetAmountText) }
    var seedCents: Int { DS.Format.cents(from: seedAmountText) }

    var requiredMonthlyPreview: Int? {
        guard hasTargetDate else { return nil }
        let remaining = max(0, targetCents - seedCents)
        guard remaining > 0 else { return 0 }
        let months = max(1, Calendar.current.dateComponents([.month], from: Date(), to: targetDate).month ?? 1)
        return remaining / months
    }
}

// MARK: - Color palette (shared)

private let goalColorOptions: [(token: String, label: String, color: Color)] = [
    ("accent",   "Blue",   DS.Colors.accent),
    ("positive", "Green",  DS.Colors.positive),
    ("warning",  "Orange", DS.Colors.warning),
    ("teal",     "Teal",   Color(hexValue: 0x14B8A6)),
    ("purple",   "Violet", Color(hexValue: 0x8B5CF6)),
    ("pink",     "Pink",   Color(hexValue: 0xEC4899)),
    ("indigo",   "Indigo", Color(hexValue: 0x6366F1)),
    ("blue",     "Sky",    Color(hexValue: 0x4A90D9)),
]

// MARK: - Create Wizard

private struct CreateGoalWizard: View {

    enum Step: Int, CaseIterable {
        case name, amount, deadline, identity, review

        var title: String {
            switch self {
            case .name:     return "What are you saving for?"
            case .amount:   return "How much?"
            case .deadline: return "By when?"
            case .identity: return "Pick a color"
            case .review:   return "Review"
            }
        }
    }

    @StateObject private var draft = GoalDraft()
    @StateObject private var goalManager = GoalManager.shared
    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step = .name
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressDots

                Text(step.title)
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(spacing: 16) {
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        switch step {
                        case .name:     NameStep(draft: draft)
                        case .amount:   AmountStep(draft: draft)
                        case .deadline: DeadlineStep(draft: draft)
                        case .identity: IdentityStep(draft: draft)
                        case .review:   ReviewStep(draft: draft, accountManager: accountManager)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }

                bottomBar
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: Progress dots

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? DS.Colors.accent : DS.Colors.surface2)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if step != .name {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        step = Step(rawValue: step.rawValue - 1) ?? .name
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(DS.Colors.surface2, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if step == .review {
                Button {
                    Task { await save() }
                } label: {
                    Label(isSaving ? "Saving…" : "Create Goal", systemImage: "checkmark")
                        .font(DS.Typography.body.weight(.semibold))
                }
                .buttonStyle(DS.PrimaryButton())
                .disabled(isSaving)
            } else {
                Button {
                    advance()
                } label: {
                    Label("Continue", systemImage: "chevron.right")
                        .font(DS.Typography.body.weight(.semibold))
                }
                .buttonStyle(DS.PrimaryButton())
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.Colors.bg)
    }

    private var canAdvance: Bool {
        switch step {
        case .name:     return !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
        case .amount:   return draft.targetCents > 0 && draft.seedCents <= draft.targetCents
        case .deadline: return true
        case .identity: return true
        case .review:   return true
        }
    }

    private func advance() {
        errorMessage = nil
        guard canAdvance else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            if let next = Step(rawValue: step.rawValue + 1) {
                step = next
            }
        }
    }

    // MARK: Save

    private func save() async {
        guard let userId = AuthManager.shared.currentUser?.uid.lowercased() else {
            errorMessage = "Please sign in to save goals."
            return
        }
        guard draft.targetCents > 0 else {
            errorMessage = "Target amount must be greater than zero."
            return
        }

        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let goal = Goal(
            name: draft.name.trimmingCharacters(in: .whitespaces),
            type: draft.goalType,
            targetAmount: draft.targetCents,
            currentAmount: draft.seedCents,
            currency: UserDefaults.standard.string(forKey: "app.currency") ?? "EUR",
            targetDate: draft.hasTargetDate ? draft.targetDate : nil,
            linkedAccountId: draft.selectedAccountId,
            icon: draft.goalType.defaultIcon,
            colorToken: draft.selectedColorToken,
            notes: draft.notes.isEmpty ? nil : draft.notes,
            isCompleted: draft.seedCents >= draft.targetCents,
            userId: userId,
            originalTargetAmount: draft.targetCents
        )

        let ok = await goalManager.createGoal(goal)
        if ok {
            dismiss()
        } else {
            errorMessage = goalManager.errorMessage ?? "Failed to create goal."
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Colors.danger)
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.danger)
            Spacer()
        }
        .padding(12)
        .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Wizard Steps

private struct NameStep: View {
    @ObservedObject var draft: GoalDraft

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 14) {
                TextField("e.g. Emergency fund", text: $draft.name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(14)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Type")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(GoalType.allCases) { type in
                        typeCell(type)
                    }
                }
            }
        }
    }

    private func typeCell(_ type: GoalType) -> some View {
        let selected = draft.goalType == type
        let tint = GoalColorHelper.color(for: draft.selectedColorToken)
        return Button {
            draft.goalType = type
            // Sync color to type default on first pick (user can override later).
            if draft.selectedColorToken == "accent" {
                draft.selectedColorToken = type.defaultColor
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: type.defaultIcon)
                    .font(.system(size: 16, weight: .medium))
                Text(type.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                selected ? tint.opacity(0.15) : DS.Colors.surface2,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? tint : DS.Colors.grid,
                            lineWidth: selected ? 1.5 : 0.5)
            )
            .foregroundStyle(selected ? tint : DS.Colors.subtext)
        }
        .buttonStyle(.plain)
    }
}

private struct AmountStep: View {
    @ObservedObject var draft: GoalDraft

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Target")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 8) {
                    Text(DS.Format.currencySymbol())
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("0", text: $draft.targetAmountText)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                }
                .padding(14)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Divider().foregroundStyle(DS.Colors.grid)

                Text("Already saved (optional)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 8) {
                    Text(DS.Format.currencySymbol())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("0", text: $draft.seedAmountText)
                        .font(DS.Typography.body)
                        .keyboardType(.decimalPad)
                }
                .padding(12)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if draft.seedCents > draft.targetCents {
                    Text("Already saved can't exceed the target.")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.danger)
                }
            }
        }
    }
}

private struct DeadlineStep: View {
    @ObservedObject var draft: GoalDraft

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 14) {
                Toggle("Set a target date", isOn: $draft.hasTargetDate.animation(.easeInOut(duration: 0.2)))
                    .tint(DS.Colors.accent)
                    .font(DS.Typography.body)

                if draft.hasTargetDate {
                    DatePicker("", selection: $draft.targetDate, in: Date()..., displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(DS.Colors.accent)

                    HStack(spacing: 8) {
                        ForEach([3, 6, 12, 24], id: \.self) { months in
                            Button {
                                draft.targetDate = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date()
                            } label: {
                                Text("\(months)mo")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(DS.Colors.subtext)
                                    .background(DS.Colors.surface2, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let monthly = draft.requiredMonthlyPreview, monthly > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                            Text("You'd need to save \(DS.Format.money(monthly))/month")
                                .font(DS.Typography.caption)
                        }
                        .foregroundStyle(DS.Colors.accent)
                    }
                } else {
                    Text("No deadline — you can save at your own pace.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }
}

private struct IdentityStep: View {
    @ObservedObject var draft: GoalDraft

    var body: some View {
        VStack(spacing: 14) {
            DS.Card {
                VStack(spacing: 14) {
                    Image(systemName: draft.goalType.defaultIcon)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(GoalColorHelper.color(for: draft.selectedColorToken))
                        .frame(width: 72, height: 72)
                        .background(
                            GoalColorHelper.color(for: draft.selectedColorToken).opacity(0.15),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                        )

                    Text(draft.name.isEmpty ? "Your goal" : draft.name)
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.text)

                    Text(DS.Format.money(draft.targetCents))
                        .font(DS.Typography.number)
                        .foregroundStyle(DS.Colors.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            DS.Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Color")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                        ForEach(goalColorOptions, id: \.token) { option in
                            colorSwatch(option)
                        }
                    }
                }
            }
        }
    }

    private func colorSwatch(_ option: (token: String, label: String, color: Color)) -> some View {
        let selected = draft.selectedColorToken == option.token
        return Button {
            draft.selectedColorToken = option.token
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(option.color)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(selected ? 1 : 0), lineWidth: 2.5)
                    )
                    .overlay(
                        Circle()
                            .stroke(option.color.opacity(selected ? 1 : 0), lineWidth: 1)
                            .padding(-2)
                    )
                Text(option.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selected ? DS.Colors.text : DS.Colors.subtext)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ReviewStep: View {
    @ObservedObject var draft: GoalDraft
    @ObservedObject var accountManager: AccountManager

    @State private var showAccountPicker = false
    @State private var showNotes = false

    var body: some View {
        VStack(spacing: 14) {
            DS.Card {
                VStack(alignment: .leading, spacing: 12) {
                    summaryRow(label: "Name", value: draft.name)
                    Divider().foregroundStyle(DS.Colors.grid)
                    summaryRow(label: "Type", value: draft.goalType.displayName)
                    Divider().foregroundStyle(DS.Colors.grid)
                    summaryRow(label: "Target", value: DS.Format.money(draft.targetCents))
                    if draft.seedCents > 0 {
                        Divider().foregroundStyle(DS.Colors.grid)
                        summaryRow(label: "Already saved", value: DS.Format.money(draft.seedCents))
                    }
                    if draft.hasTargetDate {
                        Divider().foregroundStyle(DS.Colors.grid)
                        summaryRow(
                            label: "Deadline",
                            value: draft.targetDate.formatted(.dateTime.month(.abbreviated).day().year())
                        )
                    }
                }
            }

            // Optional: account picker
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Linked account")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Button(showAccountPicker ? "Hide" : selectedAccountName ?? "None") {
                            withAnimation { showAccountPicker.toggle() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    }

                    if showAccountPicker {
                        accountPickerBody
                    }
                }
            }

            // Optional: notes
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Notes")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Button(showNotes ? "Hide" : (draft.notes.isEmpty ? "Add" : "Edit")) {
                            withAnimation { showNotes.toggle() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    }

                    if showNotes {
                        TextField("Why does this matter?", text: $draft.notes, axis: .vertical)
                            .font(DS.Typography.body)
                            .lineLimit(3...6)
                            .padding(12)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if !draft.notes.isEmpty {
                        Text(draft.notes)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    private var selectedAccountName: String? {
        guard let id = draft.selectedAccountId else { return nil }
        return accountManager.activeAccounts.first { $0.id == id }?.name
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value)
                .font(DS.Typography.body.weight(.semibold))
                .foregroundStyle(DS.Colors.text)
        }
    }

    @ViewBuilder
    private var accountPickerBody: some View {
        if accountManager.activeAccounts.isEmpty {
            Text("No accounts available")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext.opacity(0.6))
        } else {
            accountRow(
                name: "None",
                icon: "xmark.circle",
                isSelected: draft.selectedAccountId == nil
            ) {
                draft.selectedAccountId = nil
            }

            ForEach(accountManager.activeAccounts) { account in
                accountRow(
                    name: account.name,
                    icon: account.type.iconName,
                    isSelected: draft.selectedAccountId == account.id
                ) {
                    draft.selectedAccountId = account.id
                }
            }
        }
    }

    private func accountRow(name: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? DS.Colors.accent : DS.Colors.subtext)
                Text(name)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
            }
            .padding(10)
            .background(
                isSelected ? DS.Colors.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Form (single page)

private struct EditGoalForm: View {

    let goal: Goal

    @StateObject private var goalManager = GoalManager.shared
    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var goalType: GoalType = .custom
    @State private var targetAmountText = ""
    @State private var currentAmountText = ""
    @State private var hasTargetDate = false
    @State private var targetDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var selectedAccountId: UUID?
    @State private var selectedColorToken: String = "accent"
    @State private var isPaused = false
    @State private var isArchived = false
    @State private var priority: Int = 0
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    nameAndTypeCard
                    amountCard
                    timelineCard
                    colorCard
                    accountCard
                    notesCard
                    statusCard
                    deleteSection
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Edit Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(name.isEmpty || targetAmountText.isEmpty || isSaving)
                }
            }
            .alert("Delete Goal", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        _ = await goalManager.deleteGoal(goal)
                        dismiss()
                    }
                }
            } message: {
                Text("This will permanently delete this goal and all contributions.")
            }
            .onAppear(perform: loadGoal)
        }
    }

    // MARK: Cards

    private var nameAndTypeCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Goal").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)

                TextField("Goal Name", text: $name)
                    .font(DS.Typography.body)
                    .padding(12)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(GoalType.allCases) { type in
                        Button {
                            goalType = type
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: type.defaultIcon)
                                    .font(.system(size: 16, weight: .medium))
                                Text(type.displayName)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                goalType == type
                                    ? GoalColorHelper.color(for: selectedColorToken).opacity(0.15)
                                    : DS.Colors.surface2,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        goalType == type
                                            ? GoalColorHelper.color(for: selectedColorToken)
                                            : DS.Colors.grid,
                                        lineWidth: goalType == type ? 1.5 : 0.5
                                    )
                            )
                            .foregroundStyle(goalType == type
                                             ? GoalColorHelper.color(for: selectedColorToken)
                                             : DS.Colors.subtext)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var amountCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Amount").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 8) {
                    Text(DS.Format.currencySymbol())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("Target", text: $targetAmountText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .keyboardType(.decimalPad)
                }
                .padding(12)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 8) {
                    Text(DS.Format.currencySymbol())
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("Current", text: $currentAmountText)
                        .font(DS.Typography.body)
                        .keyboardType(.decimalPad)
                }
                .padding(12)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var timelineCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Target date", isOn: $hasTargetDate.animation(.easeInOut(duration: 0.2)))
                    .tint(DS.Colors.accent)
                    .font(DS.Typography.body)

                if hasTargetDate {
                    DatePicker("Date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                        .font(DS.Typography.body)
                        .tint(DS.Colors.accent)
                }
            }
        }
    }

    private var colorCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Color").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                    ForEach(goalColorOptions, id: \.token) { option in
                        Button {
                            selectedColorToken = option.token
                        } label: {
                            Circle()
                                .fill(option.color)
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(selectedColorToken == option.token ? 1 : 0), lineWidth: 2.5)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(option.color.opacity(selectedColorToken == option.token ? 1 : 0), lineWidth: 1)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var accountCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Linked account (optional)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                if accountManager.activeAccounts.isEmpty {
                    Text("No accounts available")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext.opacity(0.6))
                } else {
                    accountRow("None", icon: "xmark.circle", isSelected: selectedAccountId == nil) {
                        selectedAccountId = nil
                    }
                    ForEach(accountManager.activeAccounts) { account in
                        accountRow(account.name, icon: account.type.iconName, isSelected: selectedAccountId == account.id) {
                            selectedAccountId = account.id
                        }
                    }
                }
            }
        }
    }

    private func accountRow(_ name: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? DS.Colors.accent : DS.Colors.subtext)
                Text(name)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
            }
            .padding(10)
            .background(
                isSelected ? DS.Colors.accent.opacity(0.08) : Color.clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var notesCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .font(DS.Typography.body)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var statusCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Status").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)

                Toggle("Pause goal", isOn: $isPaused)
                    .tint(DS.Colors.accent)
                    .font(DS.Typography.body)

                Toggle("Archive", isOn: $isArchived)
                    .tint(DS.Colors.accent)
                    .font(DS.Typography.body)

                Stepper(value: $priority, in: 0...10) {
                    HStack {
                        Text("Priority").font(DS.Typography.body).foregroundStyle(DS.Colors.text)
                        Spacer()
                        Text("\(priority)")
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                .tint(DS.Colors.accent)
            }
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                Spacer()
                Image(systemName: "trash")
                Text("Delete Goal")
                Spacer()
            }
            .font(DS.Typography.body.weight(.semibold))
            .foregroundStyle(DS.Colors.danger)
            .padding(.vertical, 12)
            .background(DS.Colors.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Colors.danger.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Colors.danger)
            Text(msg)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.danger)
            Spacer()
        }
        .padding(12)
        .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Load / Save

    private func loadGoal() {
        name = goal.name
        goalType = goal.type
        targetAmountText = DS.Format.currency(goal.targetAmount)
        currentAmountText = DS.Format.currency(goal.currentAmount)
        notes = goal.notes ?? ""
        selectedColorToken = goal.colorToken
        selectedAccountId = goal.linkedAccountId
        if let d = goal.targetDate {
            hasTargetDate = true
            targetDate = d
        }
        isPaused = goal.pausedAt != nil
        isArchived = goal.isArchived
        priority = goal.priority
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let target = DS.Format.cents(from: targetAmountText)
        let current = DS.Format.cents(from: currentAmountText)

        guard target > 0 else { errorMessage = "Target must be greater than zero."; return }
        guard current >= 0 else { errorMessage = "Current amount cannot be negative."; return }
        guard current <= target else { errorMessage = "Current amount cannot exceed target."; return }

        var updated = goal
        updated.name = name
        updated.type = goalType
        updated.targetAmount = target
        updated.currentAmount = current
        updated.icon = goalType.defaultIcon
        updated.colorToken = selectedColorToken
        updated.targetDate = hasTargetDate ? targetDate : nil
        updated.notes = notes.isEmpty ? nil : notes
        updated.linkedAccountId = selectedAccountId
        updated.isCompleted = current >= target && target > 0
        updated.isArchived = isArchived
        updated.pausedAt = isPaused ? (goal.pausedAt ?? Date()) : nil
        updated.priority = priority

        let ok = await goalManager.updateGoal(updated)
        if ok {
            dismiss()
        } else {
            errorMessage = goalManager.errorMessage ?? "Failed to update goal."
        }
    }
}
