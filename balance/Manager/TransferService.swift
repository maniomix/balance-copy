import Foundation

// ============================================================
// MARK: - Transfer Service
// ============================================================
//
// First-class money movement between two accounts. Posts a
// two-leg transaction pair sharing a `transferGroupId`:
//   • Source leg: expense on source account
//   • Dest leg:   income on destination account
//
// FX-aware: when source and destination currencies differ, the
// destination amount is converted via `CurrencyConverter`.
// Each leg is stored in its own account's currency.
//
// Balance side-effects fire through TransactionService's existing
// `performAdd` pipeline — no bespoke balance adjust here.
//
// Filter `tx.transferGroupId == nil` in income/expense roll-ups
// so transfers don't double-count.
// ============================================================

@MainActor
enum TransferService {

    enum TransferError: Error, LocalizedError {
        case sameAccount
        case missingAccount
        case nonPositiveAmount
        case fxUnavailable

        var errorDescription: String? {
            switch self {
            case .sameAccount:       return "Source and destination must be different accounts."
            case .missingAccount:    return "Account not found."
            case .nonPositiveAmount: return "Transfer amount must be greater than zero."
            case .fxUnavailable:     return "Couldn't convert between these currencies."
            }
        }
    }

    /// Post a transfer. `amountCents` is in the source account's currency.
    /// Returns the shared `transferGroupId` on success.
    @discardableResult
    static func postTransfer(
        sourceId: UUID,
        destinationId: UUID,
        amountCents: Int,
        date: Date = Date(),
        note: String = "",
        store: inout Store
    ) async -> Result<UUID, TransferError> {

        guard sourceId != destinationId else { return .failure(.sameAccount) }
        guard amountCents > 0 else { return .failure(.nonPositiveAmount) }

        let manager = AccountManager.shared
        guard let source = manager.accounts.first(where: { $0.id == sourceId }),
              let dest   = manager.accounts.first(where: { $0.id == destinationId }) else {
            return .failure(.missingAccount)
        }

        // FX: leg amounts are stored in each leg's account currency.
        let destCents: Int
        if source.currency == dest.currency {
            destCents = amountCents
        } else {
            let sourceMajor = Double(amountCents) / 100.0
            guard let converted = CurrencyConverter.shared.convert(
                sourceMajor, from: source.currency, to: dest.currency
            ) else {
                return .failure(.fxUnavailable)
            }
            destCents = Int((converted * 100).rounded())
        }

        let groupId = UUID()
        let prefix = note.trimmingCharacters(in: .whitespaces)
        let trail = prefix.isEmpty ? "" : " — \(prefix)"

        let debit = Transaction(
            amount: amountCents,
            date: date,
            category: .other,
            note: "Transfer to \(dest.name)\(trail)",
            paymentMethod: .card,
            type: .expense,
            accountId: source.id,
            transferGroupId: groupId
        )
        let credit = Transaction(
            amount: destCents,
            date: date,
            category: .other,
            note: "Transfer from \(source.name)\(trail)",
            paymentMethod: .card,
            type: .income,
            accountId: dest.id,
            transferGroupId: groupId
        )

        TransactionService.performAdd(debit, store: &store)
        TransactionService.performAdd(credit, store: &store)
        return .success(groupId)
    }

    /// Delete both legs of a transfer. Side-effects (balance reversal) fire
    /// through TransactionService.performDelete for each leg.
    static func deleteTransfer(groupId: UUID, store: inout Store) {
        let legs = store.transactions.filter { $0.transferGroupId == groupId }
        for leg in legs {
            TransactionService.performDelete(leg, store: &store)
        }
    }

    /// All distinct transfer groups in the store, newest first, with both legs paired.
    static func groups(in store: Store) -> [(id: UUID, source: Transaction, dest: Transaction)] {
        let grouped = Dictionary(grouping: store.transactions.filter { $0.isTransfer }) {
            $0.transferGroupId ?? UUID()
        }
        var rows: [(id: UUID, source: Transaction, dest: Transaction)] = []
        for (id, legs) in grouped where legs.count == 2 {
            // expense leg = source, income leg = destination
            guard let src = legs.first(where: { $0.type == .expense }),
                  let dst = legs.first(where: { $0.type == .income }) else { continue }
            rows.append((id, src, dst))
        }
        return rows.sorted { $0.source.date > $1.source.date }
    }
}
