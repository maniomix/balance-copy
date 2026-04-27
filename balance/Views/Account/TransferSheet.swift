import SwiftUI

// MARK: - Transfer Sheet

struct TransferSheet: View {

    @Binding var store: Store
    /// Optional preselected source — surfaced from AccountDetailView.
    var preselectedSourceId: UUID? = nil

    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var sourceId: UUID? = nil
    @State private var destinationId: UUID? = nil
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @State private var working = false
    @State private var error: String? = nil
    @State private var showSourcePicker = false
    @State private var showDestPicker = false

    private var source: Account? {
        accountManager.activeAccounts.first(where: { $0.id == sourceId })
    }
    private var destination: Account? {
        accountManager.activeAccounts.first(where: { $0.id == destinationId })
    }

    private var amountCents: Int? {
        guard let value = Double(amountText), value > 0 else { return nil }
        return Int((value * 100).rounded())
    }

    private var fxConverted: (cents: Int, rate: Double)? {
        guard let src = source, let dst = destination,
              src.currency != dst.currency,
              let cents = amountCents else { return nil }
        let major = Double(cents) / 100.0
        guard let converted = CurrencyConverter.shared.convert(major, from: src.currency, to: dst.currency) else {
            return nil
        }
        let convertedCents = Int((converted * 100).rounded())
        let rate = converted / max(major, 0.0001)
        return (convertedCents, rate)
    }

    private var canSubmit: Bool {
        sourceId != nil && destinationId != nil
            && sourceId != destinationId
            && amountCents != nil
            && !working
    }

    var body: some View {
        NavigationStack {
            Form {
                accountsSection
                amountSection
                if let fx = fxConverted { fxSection(fx) }
                detailsSection
                if let err = error {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.danger)
                    }
                }
            }
            .navigationTitle("Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Send") {
                        Task { await submit() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSubmit)
                }
            }
            .sheet(isPresented: $showSourcePicker) {
                AccountPickerView(selectedAccountId: $sourceId)
            }
            .sheet(isPresented: $showDestPicker) {
                AccountPickerView(selectedAccountId: $destinationId)
            }
            .onAppear {
                if sourceId == nil { sourceId = preselectedSourceId }
            }
        }
    }

    // MARK: - Sections

    private var accountsSection: some View {
        Section("Accounts") {
            accountRow(label: "From", account: source) { showSourcePicker = true }
            accountRow(label: "To", account: destination) { showDestPicker = true }

            if let s = sourceId, let d = destinationId, s == d {
                Text("Source and destination must be different.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.danger)
            }
        }
    }

    private func accountRow(label: String, account: Account?, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack {
                Text(label).foregroundStyle(DS.Colors.subtext)
                Spacer()
                if let a = account {
                    Image(systemName: a.type.iconName)
                        .foregroundStyle(AccountColorTag.color(for: a.colorTag))
                    Text(a.name).foregroundStyle(DS.Colors.text)
                } else {
                    Text("Choose…").foregroundStyle(DS.Colors.subtext)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.subtext.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
    }

    private var amountSection: some View {
        Section("Amount") {
            HStack {
                Text(source.flatMap { CurrencyFormatter.SupportedCurrency(rawValue: $0.currency)?.symbol } ?? "")
                    .foregroundStyle(DS.Colors.subtext)
                TextField("0.00", text: $amountText)
                    .keyboardType(.decimalPad)
            }
        }
    }

    private func fxSection(_ fx: (cents: Int, rate: Double)) -> some View {
        Section("Exchange") {
            HStack {
                Text("Destination receives")
                    .foregroundStyle(DS.Colors.subtext)
                Spacer()
                Text(fmt(Double(fx.cents) / 100.0, code: destination?.currency ?? ""))
                    .font(DS.Typography.number)
                    .foregroundStyle(DS.Colors.text)
            }
            HStack {
                Text("Rate")
                    .foregroundStyle(DS.Colors.subtext)
                Spacer()
                Text(String(format: "1 %@ = %.4f %@",
                            source?.currency ?? "",
                            fx.rate,
                            destination?.currency ?? ""))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Note (optional)", text: $note)
        }
    }

    // MARK: - Submit

    private func submit() async {
        guard let sId = sourceId, let dId = destinationId, let cents = amountCents else { return }
        working = true
        defer { working = false }
        // Swift 6 / iOS 26 SDK refuses to pass main-actor-isolated `store`
        // directly inout to an async call. Round-trip through a local.
        var localStore = store
        let result = await TransferService.postTransfer(
            sourceId: sId,
            destinationId: dId,
            amountCents: cents,
            date: date,
            note: note,
            store: &localStore
        )
        store = localStore
        switch result {
        case .success:
            Haptics.success()
            dismiss()
        case .failure(let err):
            error = err.errorDescription
        }
    }

    private func fmt(_ value: Double, code: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = code
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
