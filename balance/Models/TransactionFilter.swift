import Foundation

// Single source of truth for the Transactions screen filter sheet.
// Empty `categories` / `paymentMethods` means "no filter on that axis"
// (i.e. show all). Same goes for `useDateRange == false` and empty
// amount text fields.
struct TransactionFilter: Equatable, Codable {
    var categories: Set<Category>
    var paymentMethods: Set<PaymentMethod>
    var accountIds: Set<UUID>
    var useDateRange: Bool
    var dateFrom: Date
    var dateTo: Date
    var minAmountText: String
    var maxAmountText: String

    init(
        categories: Set<Category> = [],
        paymentMethods: Set<PaymentMethod> = [],
        accountIds: Set<UUID> = [],
        useDateRange: Bool = false,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        minAmountText: String = "",
        maxAmountText: String = ""
    ) {
        self.categories = categories
        self.paymentMethods = paymentMethods
        self.accountIds = accountIds
        self.useDateRange = useDateRange
        let now = Date()
        let monthStart = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now)
        ) ?? now
        self.dateFrom = dateFrom ?? monthStart
        self.dateTo = dateTo ?? now
        self.minAmountText = minAmountText
        self.maxAmountText = maxAmountText
    }

    // MARK: - Per-axis activity

    func isCategoryActive(allCategories: [Category]) -> Bool {
        !categories.isEmpty && categories.count != allCategories.count
    }

    var isPaymentMethodActive: Bool {
        !paymentMethods.isEmpty && paymentMethods.count != PaymentMethod.allCases.count
    }

    var isAccountActive: Bool { !accountIds.isEmpty }

    var isAmountActive: Bool {
        DS.Format.cents(from: minAmountText) > 0 || DS.Format.cents(from: maxAmountText) > 0
    }

    var isDateActive: Bool { useDateRange }

    func activeCount(allCategories: [Category]) -> Int {
        var n = 0
        if isCategoryActive(allCategories: allCategories) { n += 1 }
        // Payment + account share one section in the UI; count as one axis
        // when either is engaged.
        if isPaymentMethodActive || isAccountActive { n += 1 }
        if isDateActive { n += 1 }
        if isAmountActive { n += 1 }
        return n
    }

    // MARK: - Apply

    func apply(to txs: [Transaction], allCategories: [Category]) -> [Transaction] {
        var out = txs

        if isCategoryActive(allCategories: allCategories) {
            out = out.filter { categories.contains($0.category) }
        }

        if isPaymentMethodActive {
            out = out.filter { paymentMethods.contains($0.paymentMethod) }
        }

        if isAccountActive {
            out = out.filter { tx in
                guard let id = tx.accountId else { return false }
                return accountIds.contains(id)
            }
        }

        let minCents = DS.Format.cents(from: minAmountText)
        let maxCents = DS.Format.cents(from: maxAmountText)
        if minCents > 0 { out = out.filter { $0.amount >= minCents } }
        if maxCents > 0 { out = out.filter { $0.amount <= maxCents } }

        if useDateRange {
            let cal = Calendar.current
            let start = cal.startOfDay(for: dateFrom)
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: dateTo)) ?? dateTo
            out = out.filter { $0.date >= start && $0.date < end }
        }

        return out
    }

    // MARK: - Mutators

    mutating func reset() {
        self = TransactionFilter()
    }
}
