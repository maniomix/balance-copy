import SwiftUI

// ============================================================
// MARK: - Add / Edit Subscription Sheet (Phase 5a)
// ============================================================
//
// One sheet, two entry points: the toolbar "+" in
// SubscriptionsOverviewView opens it in `.create`, the Edit
// toolbar button in SubscriptionDetailView opens it in
// `.edit(record)`. Edit mode prefills, swaps the title and
// CTA copy, and commits via `engine.updateSubscription`
// instead of `engine.addManualSubscription`.
//
// ============================================================

struct AddSubscriptionSheet: View {

    enum Mode {
        case create
        case edit(DetectedSubscription)

        var isEdit: Bool {
            if case .edit = self { return true }
            return false
        }
    }

    let mode: Mode

    @Binding var store: Store

    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = SubscriptionEngine.shared

    @State private var name: String = ""
    @State private var amountText: String = ""
    @State private var category: Category = .bills
    @State private var billingCycle: BillingCycle = .monthly
    @State private var hasRenewalDate: Bool = false
    @State private var renewalDate: Date = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var notes: String = ""
    @State private var didLoad: Bool = false

    /// Convenience: preserves the legacy call site
    /// `AddSubscriptionSheet(store: $store)` (Add toolbar in Overview).
    init(store: Binding<Store>) {
        self.mode = .create
        self._store = store
    }

    /// Edit-mode init used by SubscriptionDetailView.
    init(store: Binding<Store>, editing sub: DetectedSubscription) {
        self.mode = .edit(sub)
        self._store = store
    }

    private var amountCents: Int? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        guard let value = Double(cleaned), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amountCents != nil
    }

    private var navTitle: String { mode.isEdit ? "Edit Subscription" : "Add Subscription" }
    private var ctaTitle: String { mode.isEdit ? "Save" : "Add" }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    TextField("Name (e.g. Netflix)", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    HStack {
                        Text(DS.Format.currencySymbol())
                            .foregroundStyle(DS.Colors.subtext)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                    }

                    Picker("Category", selection: $category) {
                        ForEach(store.allCategories, id: \.self) { cat in
                            Label(cat.title, systemImage: cat.icon(in: store)).tag(cat)
                        }
                    }
                }

                Section("Billing") {
                    Picker("Cycle", selection: $billingCycle) {
                        ForEach(BillingCycle.allCases) { cycle in
                            Text(cycle.displayName).tag(cycle)
                        }
                    }

                    Toggle("Set next renewal date", isOn: $hasRenewalDate)

                    if hasRenewalDate {
                        DatePicker("Renews on",
                                   selection: $renewalDate,
                                   displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextField("Optional", text: $notes, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ctaTitle) { save() }
                        .disabled(!isValid)
                }
            }
            .onAppear { loadIfEditing() }
        }
    }

    private func loadIfEditing() {
        guard !didLoad else { return }
        didLoad = true
        if case .edit(let sub) = mode {
            name = sub.merchantName
            // Show in user-facing decimal form, comma OR dot tolerated by parser.
            amountText = String(format: "%.2f", Double(sub.expectedAmount) / 100.0)
            category = sub.category
            billingCycle = sub.billingCycle
            hasRenewalDate = sub.nextRenewalDate != nil
            if let d = sub.nextRenewalDate { renewalDate = d }
            notes = sub.notes
        }
    }

    private func save() {
        guard let cents = amountCents else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)

        switch mode {
        case .create:
            engine.addManualSubscription(
                merchantName: trimmed,
                category: category,
                amountCents: cents,
                billingCycle: billingCycle,
                nextRenewalDate: hasRenewalDate ? renewalDate : nil,
                notes: trimmedNotes
            )

        case .edit(let original):
            var updated = original
            updated.merchantName = trimmed
            updated.category = category
            updated.expectedAmount = cents
            // For manual records, lastAmount tracks expectedAmount until
            // a real charge lands. For detected records, leave lastAmount
            // alone (charge history is the source of truth there).
            if updated.source == .manual {
                updated.lastAmount = cents
            }
            updated.billingCycle = billingCycle
            updated.nextRenewalDate = hasRenewalDate ? renewalDate : nil
            updated.notes = trimmedNotes
            engine.updateSubscription(updated)
        }

        Haptics.success()
        dismiss()
    }
}
