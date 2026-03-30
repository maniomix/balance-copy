import SwiftUI

// MARK: - Create/Edit Goal View

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
    @State private var isSaving = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existing: Goal? {
        if case .edit(let g) = mode { return g }
        return nil
    }

    private let colorOptions: [(String, String, Color)] = [
        ("accent", "Purple", DS.Colors.accent),
        ("positive", "Green", DS.Colors.positive),
        ("warning", "Orange", DS.Colors.warning),
        ("blue", "Blue", Color(hexValue: 0x4A90D9)),
        ("teal", "Teal", Color(hexValue: 0x14B8A6)),
        ("purple", "Violet", Color(hexValue: 0x8B5CF6)),
        ("pink", "Pink", Color(hexValue: 0xEC4899)),
        ("indigo", "Indigo", Color(hexValue: 0x6366F1)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Error banner
                    if let errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Colors.danger)
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(DS.Colors.danger)
                            Spacer()
                        }
                        .padding(12)
                        .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal)
                    }

                    // Goal basics
                    basicsSection

                    // Amount
                    amountSection

                    // Timeline
                    timelineSection

                    // Color
                    colorSection

                    // Linked Account
                    accountSection

                    // Notes
                    notesSection

                    // Delete button (edit mode)
                    if isEditing {
                        deleteSection
                    }
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(name.isEmpty || targetAmountText.isEmpty || isSaving)
                }
            }
            .alert("Delete Goal", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        if let g = existing {
                            _ = await goalManager.deleteGoal(g)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("This will permanently delete this goal and all contributions.")
            }
            .onAppear { loadExisting() }
        }
    }

    // MARK: - Sections

    private var basicsSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Goal")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                TextField("Goal Name", text: $name)
                    .font(DS.Typography.body)
                    .padding(12)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    

                // Type picker as grid
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(GoalType.allCases) { type in
                        Button {
                            goalType = type
                            if !isEditing {
                                selectedColorToken = type.defaultColor
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
                                goalType == type
                                    ? GoalColorHelper.color(for: selectedColorToken).opacity(0.15)
                                    : DS.Colors.surface2,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(goalType == type ? GoalColorHelper.color(for: selectedColorToken) : DS.Colors.grid, lineWidth: goalType == type ? 1.5 : 0.5)
                            )
                            .foregroundStyle(goalType == type ? GoalColorHelper.color(for: selectedColorToken) : DS.Colors.subtext)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var amountSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Amount")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 8) {
                    Text(DS.Format.currencySymbol())
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("Target Amount", text: $targetAmountText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .keyboardType(.decimalPad)
                }
                .padding(12)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                

                if isEditing {
                    HStack(spacing: 8) {
                        Text(DS.Format.currencySymbol())
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                        TextField("Current Amount", text: $currentAmountText)
                            .font(DS.Typography.body)
                            .keyboardType(.decimalPad)
                    }
                    .padding(12)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
                }
            }
        }
    }

    private var timelineSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Timeline")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                Toggle("Set Target Date", isOn: $hasTargetDate.animation(.easeInOut(duration: 0.2)))
                    .tint(DS.Colors.accent)
                    .font(DS.Typography.body)

                if hasTargetDate {
                    DatePicker("Target Date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                        .font(DS.Typography.body)
                        .tint(DS.Colors.accent)

                    // Quick date shortcuts
                    HStack(spacing: 8) {
                        ForEach([3, 6, 12], id: \.self) { months in
                            Button {
                                targetDate = Calendar.current.date(byAdding: .month, value: months, to: Date()) ?? Date()
                            } label: {
                                Text("\(months)mo")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(DS.Colors.surface2, in: Capsule())
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Monthly saving preview
                    if !targetAmountText.isEmpty {
                        let target = DS.Format.cents(from: targetAmountText)
                        let current = isEditing ? DS.Format.cents(from: currentAmountText) : 0
                        let remaining = max(0, target - current)
                        let months = max(1, Calendar.current.dateComponents([.month], from: Date(), to: targetDate).month ?? 1)
                        let monthly = remaining / months

                        if monthly > 0 {
                            HStack {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                Text("You'd need to save \(DS.Format.money(monthly))/month")
                                    .font(DS.Typography.caption)
                            }
                            .foregroundStyle(DS.Colors.accent)
                            .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private var colorSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Color")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                HStack(spacing: 10) {
                    ForEach(colorOptions, id: \.0) { token, _, color in
                        Button {
                            selectedColorToken = token
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 28, height: 28)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: selectedColorToken == token ? 2.5 : 0)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(color, lineWidth: selectedColorToken == token ? 1 : 0)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var accountSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Linked Account (optional)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                if accountManager.activeAccounts.isEmpty {
                    Text("No accounts available")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext.opacity(0.6))
                } else {
                    // None option
                    Button {
                        selectedAccountId = nil
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 14))
                                .foregroundStyle(DS.Colors.subtext)
                            Text("None")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            if selectedAccountId == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }
                        .padding(10)
                        .background(
                            selectedAccountId == nil ? DS.Colors.accent.opacity(0.08) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(accountManager.activeAccounts) { account in
                        Button {
                            selectedAccountId = account.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: account.type.iconName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Colors.accent)
                                Text(account.name)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Colors.text)
                                Spacer()
                                if selectedAccountId == account.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DS.Colors.accent)
                                }
                            }
                            .padding(10)
                            .background(
                                selectedAccountId == account.id ? DS.Colors.accent.opacity(0.08) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Notes")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                TextField("Add a note (optional)", text: $notes, axis: .vertical)
                    .font(DS.Typography.body)
                    .lineLimit(3...6)
                    .padding(12)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    
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
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.Colors.danger.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func loadExisting() {
        guard let g = existing else { return }
        name = g.name
        goalType = g.type
        targetAmountText = DS.Format.currency(g.targetAmount)
        currentAmountText = DS.Format.currency(g.currentAmount)
        notes = g.notes ?? ""
        selectedColorToken = g.colorToken
        selectedAccountId = g.linkedAccountId
        if let d = g.targetDate {
            hasTargetDate = true
            targetDate = d
        }
    }

    private func save() async {
        guard let userId = AuthManager.shared.currentUser?.uid.lowercased() else {
            errorMessage = "Please sign in to save goals."
            return
        }
        errorMessage = nil
        isSaving = true

        let target = DS.Format.cents(from: targetAmountText)
        let current = DS.Format.cents(from: currentAmountText)

        guard target > 0 else {
            errorMessage = "Target amount must be greater than zero."
            isSaving = false
            return
        }

        guard current >= 0 else {
            errorMessage = "Current amount cannot be negative."
            isSaving = false
            return
        }

        guard current <= target else {
            errorMessage = "Current amount cannot exceed target amount."
            isSaving = false
            return
        }

        if var g = existing {
            g.name = name
            g.type = goalType
            g.targetAmount = target
            g.currentAmount = current
            g.icon = goalType.defaultIcon
            g.colorToken = selectedColorToken
            g.targetDate = hasTargetDate ? targetDate : nil
            g.notes = notes.isEmpty ? nil : notes
            g.linkedAccountId = selectedAccountId
            g.isCompleted = current >= target && target > 0

            let ok = await goalManager.updateGoal(g)
            if ok { dismiss() } else { errorMessage = goalManager.errorMessage ?? "Failed to update goal." }
        } else {
            let g = Goal(
                name: name,
                type: goalType,
                targetAmount: target,
                targetDate: hasTargetDate ? targetDate : nil,
                linkedAccountId: selectedAccountId,
                icon: goalType.defaultIcon,
                colorToken: selectedColorToken,
                notes: notes.isEmpty ? nil : notes,
                userId: userId
            )
            let ok = await goalManager.createGoal(g)
            if ok { dismiss() } else { errorMessage = goalManager.errorMessage ?? "Failed to create goal." }
        }

        isSaving = false
    }
}
