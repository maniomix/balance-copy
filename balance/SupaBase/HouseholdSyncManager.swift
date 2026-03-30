import Foundation
import Supabase

// ============================================================
// MARK: - Household Cloud Sync
// ============================================================
//
// Extension to SupabaseManager providing CRUD operations for
// all household-related tables. Follows the same patterns as
// the existing Store sync: DTOs for encoding/decoding, upsert
// for idempotent writes, lowercase userIds throughout.
//
// Tables: households, household_members, split_expenses,
//         settlements, shared_budgets, shared_goals
//
// RLS: All tables are protected by is_household_member() — see
//      household_migration.sql for the full schema.
//
// ============================================================

extension SupabaseManager {

    // MARK: - DTOs

    private struct HouseholdDTO: Codable {
        let id: String
        let name: String
        let created_by: String
        let invite_code: String
        let created_at: String
        let updated_at: String
    }

    private struct HouseholdMemberDTO: Codable {
        let id: String
        let household_id: String
        let user_id: String
        let display_name: String
        let email: String
        let role: String
        let joined_at: String
        let shared_account_ids: String?   // JSON string or null
        let share_transactions: Bool
    }

    private struct SplitExpenseDTO: Codable {
        let id: String
        let household_id: String
        let transaction_id: String?
        let amount: Int
        let paid_by: String
        let split_rule: String
        let custom_splits: String        // JSON string
        let category: String
        let note: String
        let date: String
        let is_settled: Bool
        let settled_at: String?
        let created_at: String
    }

    private struct SettlementDTO: Codable {
        let id: String
        let household_id: String
        let from_user_id: String
        let to_user_id: String
        let amount: Int
        let note: String
        let date: String
        let related_expense_ids: String   // JSON string
        let created_at: String
    }

    private struct SharedBudgetDTO: Codable {
        let id: String
        let household_id: String
        let month_key: String
        let total_amount: Int
        let split_rule: String
        let category_budgets: String      // JSON string
        let created_at: String
        let updated_at: String
    }

    private struct SharedGoalDTO: Codable {
        let id: String
        let household_id: String
        let name: String
        let icon: String
        let target_amount: Int
        let current_amount: Int
        let created_by: String
        let created_at: String
        let updated_at: String
    }

    // MARK: - Date Formatting

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func isoString(_ date: Date) -> String {
        Self.isoFormatter.string(from: date)
    }

    private func parseISO(_ str: String) -> Date {
        Self.isoFormatter.date(from: str)
            ?? ISO8601DateFormatter().date(from: str)
            ?? Date()
    }

    // MARK: - SplitRule Encoding

    private func encodeSplitRule(_ rule: SplitRule) -> String {
        switch rule {
        case .equal: return "equal"
        case .custom: return "custom"
        case .paidByMe: return "paidByMe"
        case .paidByPartner: return "paidByPartner"
        case .percentage(let pct): return "percentage:\(pct)"
        }
    }

    private func decodeSplitRule(_ raw: String) -> SplitRule {
        switch raw {
        case "equal": return .equal
        case "custom": return .custom
        case "paidByMe": return .paidByMe
        case "paidByPartner": return .paidByPartner
        default:
            if raw.hasPrefix("percentage:"),
               let pct = Double(raw.dropFirst("percentage:".count)) {
                return .percentage(pct)
            }
            return .equal
        }
    }

    // MARK: - JSON Helpers

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        (try? String(data: JSONEncoder().encode(value), encoding: .utf8)) ?? "[]"
    }

    private func decodeJSON<T: Decodable>(_ type: T.Type, from str: String?) -> T? {
        guard let str, let data = str.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // ============================================================
    // MARK: - Household CRUD
    // ============================================================

    func saveHousehold(_ household: Household) async throws {
        let data: [String: String] = [
            "id": household.id.uuidString.lowercased(),
            "name": household.name,
            "created_by": household.createdBy.lowercased(),
            "invite_code": household.inviteCode,
            "created_at": isoString(household.createdAt),
            "updated_at": isoString(household.updatedAt)
        ]

        try await client.database
            .from("households")
            .upsert(data, onConflict: "id")
            .execute()

        SecureLogger.info("Household saved to cloud")
    }

    func loadHousehold(householdId: UUID) async throws -> Household? {
        let response: [HouseholdDTO] = try await client.database
            .from("households")
            .select()
            .eq("id", value: householdId.uuidString.lowercased())
            .execute()
            .value

        guard let dto = response.first else { return nil }
        return Household(
            id: UUID(uuidString: dto.id) ?? householdId,
            name: dto.name,
            createdBy: dto.created_by,
            members: [],  // loaded separately
            inviteCode: dto.invite_code,
            createdAt: parseISO(dto.created_at),
            updatedAt: parseISO(dto.updated_at)
        )
    }

    /// Find a household by invite code (used during join flow).
    func findHouseholdByInviteCode(_ code: String) async throws -> Household? {
        let response: [HouseholdDTO] = try await client.database
            .from("households")
            .select()
            .eq("invite_code", value: code.uppercased())
            .execute()
            .value

        guard let dto = response.first else { return nil }
        return Household(
            id: UUID(uuidString: dto.id) ?? UUID(),
            name: dto.name,
            createdBy: dto.created_by,
            members: [],
            inviteCode: dto.invite_code,
            createdAt: parseISO(dto.created_at),
            updatedAt: parseISO(dto.updated_at)
        )
    }

    func deleteHousehold(_ householdId: UUID) async throws {
        try await client.database
            .from("households")
            .delete()
            .eq("id", value: householdId.uuidString.lowercased())
            .execute()

        SecureLogger.info("Household deleted from cloud")
    }

    // ============================================================
    // MARK: - Members
    // ============================================================

    func saveHouseholdMember(_ member: HouseholdMember, householdId: UUID) async throws {
        let accountIdsJSON: String?
        if let ids = member.sharedAccountIds {
            accountIdsJSON = encodeJSON(ids)
        } else {
            accountIdsJSON = nil
        }

        var data: [String: String] = [
            "id": member.id.uuidString.lowercased(),
            "household_id": householdId.uuidString.lowercased(),
            "user_id": member.userId.lowercased(),
            "display_name": member.displayName,
            "email": member.email,
            "role": member.role.rawValue,
            "joined_at": isoString(member.joinedAt),
            "share_transactions": member.shareTransactions ? "true" : "false"
        ]
        if let json = accountIdsJSON {
            data["shared_account_ids"] = json
        }

        try await client.database
            .from("household_members")
            .upsert(data, onConflict: "household_id,user_id")
            .execute()
    }

    func loadHouseholdMembers(householdId: UUID) async throws -> [HouseholdMember] {
        let response: [HouseholdMemberDTO] = try await client.database
            .from("household_members")
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .execute()
            .value

        return response.compactMap { dto -> HouseholdMember? in
            guard let uuid = UUID(uuidString: dto.id) else { return nil }

            let sharedIds: [String]? = decodeJSON([String].self, from: dto.shared_account_ids)

            return HouseholdMember(
                id: uuid,
                userId: dto.user_id,
                displayName: dto.display_name,
                email: dto.email,
                role: HouseholdRole(rawValue: dto.role) ?? .viewer,
                joinedAt: parseISO(dto.joined_at),
                sharedAccountIds: sharedIds,
                shareTransactions: dto.share_transactions
            )
        }
    }

    func removeHouseholdMember(userId: String, householdId: UUID) async throws {
        try await client.database
            .from("household_members")
            .delete()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("user_id", value: userId.lowercased())
            .execute()
    }

    /// Find which household the current user belongs to.
    func findUserHousehold(userId: String) async throws -> UUID? {
        struct MemberHouseholdDTO: Codable {
            let household_id: String
        }

        let response: [MemberHouseholdDTO] = try await client.database
            .from("household_members")
            .select("household_id")
            .eq("user_id", value: userId.lowercased())
            .limit(1)
            .execute()
            .value

        guard let dto = response.first else { return nil }
        return UUID(uuidString: dto.household_id)
    }

    // ============================================================
    // MARK: - Split Expenses
    // ============================================================

    func saveSplitExpense(_ expense: SplitExpense) async throws {
        var data: [String: String] = [
            "id": expense.id.uuidString.lowercased(),
            "household_id": expense.householdId.uuidString.lowercased(),
            "amount": String(expense.amount),
            "paid_by": expense.paidBy.lowercased(),
            "split_rule": encodeSplitRule(expense.splitRule),
            "custom_splits": encodeJSON(expense.customSplits),
            "category": expense.category,
            "note": expense.note,
            "date": isoString(expense.date),
            "is_settled": expense.isSettled ? "true" : "false",
            "created_at": isoString(expense.createdAt)
        ]
        data["transaction_id"] = expense.transactionId.uuidString.lowercased()
        if let settledAt = expense.settledAt {
            data["settled_at"] = isoString(settledAt)
        }

        try await client.database
            .from("split_expenses")
            .upsert(data, onConflict: "id")
            .execute()
    }

    func loadSplitExpenses(householdId: UUID) async throws -> [SplitExpense] {
        let response: [SplitExpenseDTO] = try await client.database
            .from("split_expenses")
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .order("date", ascending: false)
            .execute()
            .value

        return response.compactMap { dto -> SplitExpense? in
            guard let uuid = UUID(uuidString: dto.id),
                  let hhId = UUID(uuidString: dto.household_id) else { return nil }

            let txId = dto.transaction_id.flatMap { UUID(uuidString: $0) } ?? UUID()
            let customSplits = decodeJSON([MemberSplit].self, from: dto.custom_splits) ?? []

            return SplitExpense(
                id: uuid,
                householdId: hhId,
                transactionId: txId,
                amount: dto.amount,
                paidBy: dto.paid_by,
                splitRule: decodeSplitRule(dto.split_rule),
                customSplits: customSplits,
                category: dto.category,
                note: dto.note,
                date: parseISO(dto.date),
                isSettled: dto.is_settled,
                settledAt: dto.settled_at.map { parseISO($0) },
                createdAt: parseISO(dto.created_at)
            )
        }
    }

    func deleteSplitExpense(_ expenseId: UUID) async throws {
        try await client.database
            .from("split_expenses")
            .delete()
            .eq("id", value: expenseId.uuidString.lowercased())
            .execute()
    }

    // ============================================================
    // MARK: - Settlements
    // ============================================================

    func saveSettlement(_ settlement: Settlement) async throws {
        let data: [String: String] = [
            "id": settlement.id.uuidString.lowercased(),
            "household_id": settlement.householdId.uuidString.lowercased(),
            "from_user_id": settlement.fromUserId.lowercased(),
            "to_user_id": settlement.toUserId.lowercased(),
            "amount": String(settlement.amount),
            "note": settlement.note,
            "date": isoString(settlement.date),
            "related_expense_ids": encodeJSON(settlement.relatedExpenseIds.map { $0.uuidString.lowercased() }),
            "created_at": isoString(settlement.createdAt)
        ]

        try await client.database
            .from("settlements")
            .upsert(data, onConflict: "id")
            .execute()
    }

    func loadSettlements(householdId: UUID) async throws -> [Settlement] {
        let response: [SettlementDTO] = try await client.database
            .from("settlements")
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .order("date", ascending: false)
            .execute()
            .value

        return response.compactMap { dto -> Settlement? in
            guard let uuid = UUID(uuidString: dto.id),
                  let hhId = UUID(uuidString: dto.household_id) else { return nil }

            let relatedIds = decodeJSON([String].self, from: dto.related_expense_ids)?
                .compactMap { UUID(uuidString: $0) } ?? []

            return Settlement(
                id: uuid,
                householdId: hhId,
                fromUserId: dto.from_user_id,
                toUserId: dto.to_user_id,
                amount: dto.amount,
                note: dto.note,
                date: parseISO(dto.date),
                relatedExpenseIds: relatedIds,
                createdAt: parseISO(dto.created_at)
            )
        }
    }

    // ============================================================
    // MARK: - Shared Budgets
    // ============================================================

    func saveSharedBudget(_ budget: SharedBudget) async throws {
        let data: [String: String] = [
            "id": budget.id.uuidString.lowercased(),
            "household_id": budget.householdId.uuidString.lowercased(),
            "month_key": budget.monthKey,
            "total_amount": String(budget.totalAmount),
            "split_rule": encodeSplitRule(budget.splitRule),
            "category_budgets": encodeJSON(budget.categoryBudgets),
            "created_at": isoString(budget.createdAt),
            "updated_at": isoString(budget.updatedAt)
        ]

        try await client.database
            .from("shared_budgets")
            .upsert(data, onConflict: "household_id,month_key")
            .execute()
    }

    func loadSharedBudgets(householdId: UUID) async throws -> [SharedBudget] {
        let response: [SharedBudgetDTO] = try await client.database
            .from("shared_budgets")
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .execute()
            .value

        return response.compactMap { dto -> SharedBudget? in
            guard let uuid = UUID(uuidString: dto.id),
                  let hhId = UUID(uuidString: dto.household_id) else { return nil }

            let catBudgets = decodeJSON([String: Int].self, from: dto.category_budgets) ?? [:]

            return SharedBudget(
                id: uuid,
                householdId: hhId,
                monthKey: dto.month_key,
                totalAmount: dto.total_amount,
                splitRule: decodeSplitRule(dto.split_rule),
                categoryBudgets: catBudgets,
                createdAt: parseISO(dto.created_at),
                updatedAt: parseISO(dto.updated_at)
            )
        }
    }

    // ============================================================
    // MARK: - Shared Goals
    // ============================================================

    func saveSharedGoal(_ goal: SharedGoal) async throws {
        let data: [String: String] = [
            "id": goal.id.uuidString.lowercased(),
            "household_id": goal.householdId.uuidString.lowercased(),
            "name": goal.name,
            "icon": goal.icon,
            "target_amount": String(goal.targetAmount),
            "current_amount": String(goal.currentAmount),
            "created_by": goal.createdBy.lowercased(),
            "created_at": isoString(goal.createdAt),
            "updated_at": isoString(goal.updatedAt)
        ]

        try await client.database
            .from("shared_goals")
            .upsert(data, onConflict: "id")
            .execute()
    }

    func loadSharedGoals(householdId: UUID) async throws -> [SharedGoal] {
        let response: [SharedGoalDTO] = try await client.database
            .from("shared_goals")
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .execute()
            .value

        return response.compactMap { dto -> SharedGoal? in
            guard let uuid = UUID(uuidString: dto.id),
                  let hhId = UUID(uuidString: dto.household_id) else { return nil }

            return SharedGoal(
                id: uuid,
                householdId: hhId,
                name: dto.name,
                icon: dto.icon,
                targetAmount: dto.target_amount,
                currentAmount: dto.current_amount,
                createdBy: dto.created_by,
                createdAt: parseISO(dto.created_at),
                updatedAt: parseISO(dto.updated_at)
            )
        }
    }

    func deleteSharedGoal(_ goalId: UUID) async throws {
        try await client.database
            .from("shared_goals")
            .delete()
            .eq("id", value: goalId.uuidString.lowercased())
            .execute()
    }

    // ============================================================
    // MARK: - Bulk Sync (Push / Pull)
    // ============================================================

    /// Push all household data to cloud. Called after local edits.
    func pushHouseholdData(
        household: Household,
        members: [HouseholdMember],
        splitExpenses: [SplitExpense],
        settlements: [Settlement],
        sharedBudgets: [SharedBudget],
        sharedGoals: [SharedGoal]
    ) async throws {
        // Save household first (parent row for FK constraints)
        try await saveHousehold(household)

        // Save members
        for member in members {
            try await saveHouseholdMember(member, householdId: household.id)
        }

        // Save child records
        for expense in splitExpenses {
            try await saveSplitExpense(expense)
        }
        for settlement in settlements {
            try await saveSettlement(settlement)
        }
        for budget in sharedBudgets {
            try await saveSharedBudget(budget)
        }
        for goal in sharedGoals {
            try await saveSharedGoal(goal)
        }

        SecureLogger.info("Household data pushed to cloud")
    }

    /// Pull all household data from cloud. Returns nil if no household found.
    func pullHouseholdData(userId: String) async throws -> HouseholdCloudData? {
        // Find the user's household
        guard let householdId = try await findUserHousehold(userId: userId) else {
            return nil
        }

        guard let household = try await loadHousehold(householdId: householdId) else {
            return nil
        }

        let members = try await loadHouseholdMembers(householdId: householdId)
        let splitExpenses = try await loadSplitExpenses(householdId: householdId)
        let settlements = try await loadSettlements(householdId: householdId)
        let sharedBudgets = try await loadSharedBudgets(householdId: householdId)
        let sharedGoals = try await loadSharedGoals(householdId: householdId)

        // Attach members to household
        var fullHousehold = household
        fullHousehold.members = members

        return HouseholdCloudData(
            household: fullHousehold,
            splitExpenses: splitExpenses,
            settlements: settlements,
            sharedBudgets: sharedBudgets,
            sharedGoals: sharedGoals
        )
    }
}

// MARK: - Cloud Data Container

/// Container for all household data pulled from cloud.
struct HouseholdCloudData {
    let household: Household
    let splitExpenses: [SplitExpense]
    let settlements: [Settlement]
    let sharedBudgets: [SharedBudget]
    let sharedGoals: [SharedGoal]
}
