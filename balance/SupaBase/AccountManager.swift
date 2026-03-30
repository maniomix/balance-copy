import Foundation
import Supabase
import Combine

// ============================================================
// MARK: - Account Manager
// ============================================================
//
// Manages financial accounts (bank, credit card, loan, etc.)
// via Supabase. Supports soft-delete (archive) and hard-delete
// with cascading snapshot cleanup.
//
// Security:
//   - All logging via SecureLogger (no PII in production)
//   - Error messages sanitized for user display
//   - Hard delete requires ownership validation
//
// ============================================================

@MainActor
class AccountManager: ObservableObject {

    static let shared = AccountManager()

    @Published var accounts: [Account] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var client: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    // MARK: - Current User ID

    private var currentUserId: UUID? {
        guard let uid = AuthManager.shared.currentUser?.uid else { return nil }
        return UUID(uuidString: uid)
    }

    // MARK: - Fetch Accounts

    func fetchAccounts() async {
        guard let userId = currentUserId else { return }
        isLoading = true
        errorMessage = nil

        do {
            let response: [Account] = try await client
                .from("accounts")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_archived", value: false)
                .order("created_at", ascending: false)
                .execute()
                .value

            self.accounts = response
            SecureLogger.info("Fetched \(response.count) accounts")
        } catch {
            self.errorMessage = AppConfig.shared.safeErrorMessage(
                detail: "Failed to load accounts: \(error.localizedDescription)",
                fallback: "Could not load accounts. Please try again."
            )
            SecureLogger.error("Fetch accounts failed", error)
        }

        isLoading = false
    }

    /// Fetch all accounts including archived (for net worth history)
    func fetchAllAccounts() async -> [Account] {
        guard let userId = currentUserId else { return [] }
        do {
            let response: [Account] = try await client
                .from("accounts")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            return response
        } catch {
            SecureLogger.error("Fetch all accounts failed", error)
            return []
        }
    }

    // MARK: - Create Account

    func createAccount(_ account: Account) async -> Bool {
        do {
            try await client
                .from("accounts")
                .insert(account)
                .execute()

            SecureLogger.info("Account created")

            // Take initial balance snapshot
            await takeSnapshot(for: account)
            await fetchAccounts()
            return true
        } catch {
            self.errorMessage = AppConfig.shared.safeErrorMessage(
                detail: "Failed to create account: \(error.localizedDescription)",
                fallback: "Could not create account. Please try again."
            )
            SecureLogger.error("Create account failed", error)
            return false
        }
    }

    // MARK: - Update Account

    func updateAccount(_ account: Account) async -> Bool {
        var updated = account
        updated.updatedAt = Date()

        do {
            try await client
                .from("accounts")
                .update(updated)
                .eq("id", value: updated.id.uuidString)
                .execute()

            SecureLogger.info("Account updated")
            await fetchAccounts()
            return true
        } catch {
            self.errorMessage = AppConfig.shared.safeErrorMessage(
                detail: "Failed to update account: \(error.localizedDescription)",
                fallback: "Could not update account. Please try again."
            )
            SecureLogger.error("Update account failed", error)
            return false
        }
    }

    // MARK: - Archive Account (Soft Delete)

    func archiveAccount(_ account: Account) async -> Bool {
        var archived = account
        archived.isArchived = true
        archived.updatedAt = Date()
        return await updateAccount(archived)
    }

    // MARK: - Delete Account (Hard Delete)

    /// Hard-deletes an account and its associated snapshots.
    /// Validates that the account belongs to the current user before proceeding.
    func deleteAccount(_ account: Account) async -> Bool {
        // Ownership check: ensure the account belongs to the current user
        guard let userId = currentUserId,
              account.userId == userId else {
            SecureLogger.security("Attempted to delete account not owned by current user")
            self.errorMessage = "You don't have permission to delete this account."
            return false
        }

        do {
            // Delete associated snapshots first (cascading cleanup)
            try await client
                .from("account_balance_snapshots")
                .delete()
                .eq("account_id", value: account.id.uuidString)
                .execute()

            // Delete the account
            try await client
                .from("accounts")
                .delete()
                .eq("id", value: account.id.uuidString)
                .execute()

            SecureLogger.info("Account deleted")
            await fetchAccounts()

            // Notify so transaction references can be cleaned up
            NotificationCenter.default.post(
                name: .accountDidDelete,
                object: nil,
                userInfo: ["accountId": account.id]
            )

            return true
        } catch {
            self.errorMessage = AppConfig.shared.safeErrorMessage(
                detail: "Failed to delete account: \(error.localizedDescription)",
                fallback: "Could not delete account. Please try again."
            )
            SecureLogger.error("Delete account failed", error)
            return false
        }
    }

    // MARK: - Balance Updates

    /// Update account balance after a transaction is added.
    /// Returns `true` if the balance was successfully persisted to Supabase,
    /// `false` if the account was not found or the DB update failed.
    @discardableResult
    func adjustBalance(accountId: UUID, amount: Double, isExpense: Bool) async -> Bool {
        guard var account = accounts.first(where: { $0.id == accountId }) else {
            SecureLogger.warning("adjustBalance: account not found in local cache, skipping")
            return false
        }

        if account.type.isAsset {
            account.currentBalance += isExpense ? -amount : amount
        } else {
            account.currentBalance += isExpense ? amount : -amount
        }

        account.updatedAt = Date()
        let success = await updateAccount(account)
        if !success {
            SecureLogger.warning("adjustBalance: DB update failed for account")
        }
        return success
    }

    /// Reverse a balance adjustment (e.g., when deleting a transaction).
    /// Returns `true` if the reversal was successfully persisted.
    @discardableResult
    func reverseBalanceAdjustment(accountId: UUID, amount: Double, isExpense: Bool) async -> Bool {
        await adjustBalance(accountId: accountId, amount: amount, isExpense: !isExpense)
    }

    // MARK: - Balance Snapshots

    func takeSnapshot(for account: Account) async {
        let snapshot = AccountBalanceSnapshot(
            accountId: account.id,
            balance: account.currentBalance
        )
        do {
            try await client
                .from("account_balance_snapshots")
                .insert(snapshot)
                .execute()
        } catch {
            SecureLogger.warning("Failed to take snapshot")
        }
    }

    /// Take snapshots for all active accounts (call on app open)
    func takeDailySnapshots() async {
        for account in accounts {
            await takeSnapshot(for: account)
        }
        SecureLogger.info("Daily snapshots taken for \(accounts.count) accounts")
    }

    // MARK: - Computed Properties

    var activeAccounts: [Account] {
        accounts.filter { !$0.isArchived }
    }

    var assetAccounts: [Account] {
        activeAccounts.filter { $0.type.isAsset }
    }

    var liabilityAccounts: [Account] {
        activeAccounts.filter { $0.type.isLiability }
    }

    var totalAssets: Double {
        assetAccounts.reduce(0) { $0 + $1.currentBalance }
    }

    var totalLiabilities: Double {
        liabilityAccounts.reduce(0) { $0 + abs($1.currentBalance) }
    }

    var netWorth: Double {
        totalAssets - totalLiabilities
    }

    // MARK: - Converted Totals (currency-aware)

    /// Convert an account balance to the app's default currency.
    func convertedBalance(for account: Account) -> Double {
        let appCurrency = CurrencyConverter.shared.appCurrency
        if account.currency == appCurrency { return account.currentBalance }
        return CurrencyConverter.shared.convert(
            account.currentBalance,
            from: account.currency,
            to: appCurrency
        ) ?? account.currentBalance
    }

    /// Total assets converted to the app's default currency.
    var convertedTotalAssets: Double {
        assetAccounts.reduce(0) { $0 + convertedBalance(for: $1) }
    }

    /// Total liabilities converted to the app's default currency.
    var convertedTotalLiabilities: Double {
        liabilityAccounts.reduce(0) { $0 + abs(convertedBalance(for: $1)) }
    }

    /// Net worth in the app's default currency.
    var convertedNetWorth: Double {
        convertedTotalAssets - convertedTotalLiabilities
    }

    /// Whether any account has a different currency from the app setting.
    var hasMultipleCurrencies: Bool {
        let appCurrency = CurrencyConverter.shared.appCurrency
        return activeAccounts.contains { $0.currency != appCurrency }
    }
}
