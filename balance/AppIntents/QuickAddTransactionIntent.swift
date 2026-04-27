import AppIntents
import SwiftUI

// MARK: - Category dropdown

enum QuickAddCategory: String, AppEnum {
    case groceries, dining, transport, shopping, bills, rent, health, education, other

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Category" }
    static var caseDisplayRepresentations: [QuickAddCategory: DisplayRepresentation] {
        [
            .groceries: "Groceries",
            .dining: "Dining",
            .transport: "Transport",
            .shopping: "Shopping",
            .bills: "Bills",
            .rent: "Rent",
            .health: "Health",
            .education: "Education",
            .other: "Other",
        ]
    }

    var domain: Category {
        switch self {
        case .groceries: return .groceries
        case .dining: return .dining
        case .transport: return .transport
        case .shopping: return .shopping
        case .bills: return .bills
        case .rent: return .rent
        case .health: return .health
        case .education: return .education
        case .other: return .other
        }
    }
}

// MARK: - Disabled error

struct QuickAddDisabledError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Quick Add is off. Turn it on in Centmond → Settings → Quick Add (Back Tap)."
    }
}

struct QuickAddInvalidAmountError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Amount must be greater than zero."
    }
}

// MARK: - Intent

struct QuickAddTransactionIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Add Transaction"
    static var description = IntentDescription(
        "Add a transaction to Centmond without opening the app. Designed for Back Tap.",
        categoryName: "Transactions"
    )

    /// Pure App Intent — never launches the app.
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = true

    @Parameter(title: "Amount", description: "How much was spent")
    var amount: Double

    @Parameter(title: "Category", description: "Pick a category")
    var category: QuickAddCategory?

    @Parameter(title: "Date", description: "When did this happen?")
    var date: Date?

    @Parameter(title: "Note", description: "Optional note", default: "")
    var note: String

    static var parameterSummary: some ParameterSummary {
        Summary("Quick add \(\.$amount) to \(\.$category) on \(\.$date)") {
            \.$note
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard UserDefaults.standard.bool(forKey: "backTap.quickAdd.enabled") else {
            throw QuickAddDisabledError()
        }

        // Step 1: amount (auto-prompted because it has no default)
        let cents = Int((amount * 100).rounded())
        guard cents > 0 else { throw QuickAddInvalidAmountError() }

        // Step 2: category — explicit prompt so we always ask
        let chosenCategory: QuickAddCategory
        if let c = category {
            chosenCategory = c
        } else {
            chosenCategory = try await $category.requestValue("Pick a category")
        }

        // Step 3: date — explicit prompt so we always ask
        let chosenDate: Date
        if let d = date {
            chosenDate = d
        } else {
            chosenDate = try await $date.requestValue("When did this happen?")
        }

        // Step 4: confirmation before save
        let currency = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        let symbol = CurrencyOption.lookup(currency).symbol
        let formatted = String(format: "%.2f", amount)
        let dateText = chosenDate.formatted(date: .abbreviated, time: .omitted)

        try await requestConfirmation(
            result: .result(
                dialog: IntentDialog("Add \(symbol)\(formatted) to \(chosenCategory.domain.title) on \(dateText)?")
            ),
            confirmationActionName: .add
        )

        // Step 5: save
        let userId = AuthManager.shared.currentUser?.uid
        var store = Store.load(userId: userId)

        let txn = Transaction(
            amount: cents,
            date: chosenDate,
            category: chosenCategory.domain,
            note: note,
            paymentMethod: .card,
            type: .expense
        )

        store.add(txn)
        _ = store.save(userId: userId)

        // Push the new totals into the Live Activity if one is alive.
        BudgetLiveActivityManager.shared.refresh(store: store)

        let snippet = QuickAddSnippetView(
            amount: amount,
            currencySymbol: symbol,
            categoryTitle: chosenCategory.domain.title,
            categoryIcon: chosenCategory.domain.icon,
            categoryTint: chosenCategory.domain.tint,
            date: chosenDate,
            note: note
        )

        return .result(
            dialog: IntentDialog("Added \(symbol)\(formatted) to \(chosenCategory.domain.title)."),
            view: snippet
        )
    }
}

// MARK: - App Shortcuts (so the intent shows up in Shortcuts app for Back Tap)

struct CentmondAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickAddTransactionIntent(),
            phrases: [
                "Quick add transaction in \(.applicationName)",
                "Add expense in \(.applicationName)",
                "Log spending in \(.applicationName)",
            ],
            shortTitle: "Quick Add",
            systemImageName: "plus.circle.fill"
        )
    }
}
