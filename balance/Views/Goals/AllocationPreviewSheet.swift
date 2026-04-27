import SwiftUI

// MARK: - Allocation Preview Sheet
//
// Shown after a user saves an income transaction when one or more active
// `GoalAllocationRule`s match. Lets the user toggle proposals on/off and
// tweak amounts before any contribution is written. Per
// `feedback_confirm_every_action`: NEVER auto-applies. Cancel = nothing
// happens; Apply = writes via `GoalManager.addContribution` with
// `source: .allocationRule`.

struct AllocationPreviewSheet: View {

    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction
    @State var proposals: [AllocationProposal]
    let onApplied: () -> Void

    @StateObject private var goalManager = GoalManager.shared
    @State private var isApplying = false
    @State private var errorMessage: String?

    private var enabledTotal: Int {
        proposals.filter(\.enabled).reduce(0) { $0 + $1.amount }
    }

    private var incomeRemaining: Int {
        max(0, transaction.amount - enabledTotal)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard

                    ForEach($proposals) { $proposal in
                        proposalRow(proposal: $proposal)
                    }

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Save to goals?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isApplying ? "Saving…" : "Apply") {
                        Task { await apply() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isApplying || enabledTotal == 0)
                }
            }
        }
    }

    // MARK: Header

    private var headerCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Income")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    Text(DS.Format.money(transaction.amount))
                        .font(DS.Typography.number)
                        .foregroundStyle(DS.Colors.text)
                }
                Divider().foregroundStyle(DS.Colors.grid)
                HStack {
                    Text("Going to goals")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    Text(DS.Format.money(enabledTotal))
                        .font(DS.Typography.number)
                        .foregroundStyle(DS.Colors.accent)
                }
                HStack {
                    Text("Remaining")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    Text(DS.Format.money(incomeRemaining))
                        .font(DS.Typography.number)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }

    // MARK: Proposal row

    @ViewBuilder
    private func proposalRow(proposal: Binding<AllocationProposal>) -> some View {
        let p = proposal.wrappedValue
        let tint = GoalColorHelper.color(for: p.goal.colorToken)

        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: p.goal.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 32, height: 32)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.goal.name)
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(DS.Colors.text)
                        Text(p.rule.name)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .lineLimit(1)
                    }

                    Spacer()

                    Toggle("", isOn: proposal.enabled)
                        .labelsHidden()
                        .tint(DS.Colors.accent)
                }

                if proposal.wrappedValue.enabled {
                    HStack(spacing: 6) {
                        Text(DS.Format.currencySymbol())
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                        TextField(
                            "Amount",
                            text: Binding(
                                get: { DS.Format.currency(proposal.wrappedValue.amount) },
                                set: { newText in
                                    proposal.wrappedValue.amount = DS.Format.cents(from: newText)
                                }
                            )
                        )
                        .font(DS.Typography.body)
                        .keyboardType(.decimalPad)
                    }
                    .padding(10)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: Error

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

    // MARK: Apply

    private func apply() async {
        errorMessage = nil
        isApplying = true
        defer { isApplying = false }

        let toApply = proposals.filter { $0.enabled && $0.amount > 0 }
        for proposal in toApply {
            // Refresh the goal in case earlier proposals in this loop closed the gap.
            let liveGoal = goalManager.goals.first { $0.id == proposal.goal.id } ?? proposal.goal
            let cap = max(0, liveGoal.targetAmount - liveGoal.currentAmount)
            let amount = min(proposal.amount, cap)
            guard amount > 0 else { continue }

            let ok = await goalManager.addContribution(
                to: liveGoal,
                amount: amount,
                note: proposal.rule.name,
                source: .allocationRule,
                linkedTransactionId: transaction.id,
                linkedRuleId: proposal.rule.id
            )
            if !ok {
                errorMessage = goalManager.errorMessage ?? "Could not save one or more contributions."
                return
            }
        }

        onApplied()
        dismiss()
    }
}
