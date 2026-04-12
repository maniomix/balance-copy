import Foundation
import Combine

// ============================================================
// MARK: - AI Action History (Phase 3: Audit + Undo)
// ============================================================
//
// Records every AI action with:
//   • what was proposed and executed
//   • trust decision (level, reason, risk)
//   • before/after state for undo
//   • explanation of why the AI did it
//   • action grouping for multi-action requests
//   • undo status and capability
//
// Persisted to UserDefaults so it survives app restarts.
//
// ============================================================

// MARK: - Action Record

/// A single recorded AI action with full audit context.
struct AIActionRecord: Identifiable, Codable {
    let id: UUID
    let action: CodableAction
    let executedAt: Date

    // ── Audit context ──
    let summary: String
    let explanation: String         // why the AI did this
    let trustLevel: String          // "auto", "confirm", "neverAuto"
    let trustReason: String         // from TrustDecision.reason
    let riskScore: Double           // 0.0–1.0
    let riskLevel: String           // "none", "low", "medium", "high", "critical"
    let intentType: String          // from IntentClassification
    let confidence: Double          // intent confidence

    // ── Status ──
    let outcome: ActionOutcome
    let isUndoable: Bool
    var isUndone: Bool = false
    var undoneAt: Date? = nil

    // ── Grouping ──
    let groupId: UUID?              // links actions from one user request
    let groupLabel: String?         // e.g. "Clean up March transactions"

    // ── Before/after state ──
    let snapshot: ActionSnapshot

    /// Lightweight codable wrapper for the action identity.
    struct CodableAction: Codable {
        let id: UUID
        let type: String            // raw value of AIAction.ActionType
        let amountCents: Int?
        let category: String?
        let note: String?
        let targetId: String?       // transaction/goal/recurring ID affected

        init(from action: AIAction) {
            self.id = action.id
            self.type = action.type.rawValue
            self.amountCents = action.params.amount ?? action.params.budgetAmount ??
                               action.params.goalTarget ?? action.params.subscriptionAmount ??
                               action.params.contributionAmount
            self.category = action.params.category ?? action.params.budgetCategory
            self.note = action.params.note ?? action.params.goalName ??
                        action.params.subscriptionName ?? action.params.recurringName
            self.targetId = action.params.transactionId
        }
    }
}

// MARK: - Action Outcome

enum ActionOutcome: String, Codable {
    case executed       // ran successfully
    case failed         // attempted but failed
    case blocked        // trust system prevented it
    case pending        // waiting for user confirmation
    case confirmed      // user confirmed, then executed
    case rejected       // user rejected it
    case undone         // was executed, then undone
}

// MARK: - Action Snapshot (Before/After)

/// Captures enough state to display audit info and support undo.
/// Not a full event-sourcing replay — just practical local snapshots.
enum ActionSnapshot: Codable {

    /// Transaction was added — store its ID for removal.
    case addedTransaction(transactionId: String)

    /// Transaction was edited — store old field values.
    case editedTransaction(EditedFields)

    /// Transaction was deleted — store the full serialized transaction.
    case deletedTransaction(SerializedTransaction)

    /// Budget was changed — store month key and old value.
    case budgetChanged(monthKey: String, oldAmount: Int?)

    /// Category budget was changed.
    case categoryBudgetChanged(monthKey: String, categoryKey: String, oldAmount: Int?)

    /// Subscription/recurring was added — store name for removal.
    case addedRecurring(name: String)

    /// Goal was created — store ID for deletion.
    case createdGoal(goalId: String)

    /// Goal contribution — store goal name and amount for reversal.
    case addedContribution(goalName: String, amount: Int)

    /// Not undoable or no state needed (analysis, blocked, failed).
    case none

    // ── Nested types ──

    struct EditedFields: Codable {
        let transactionId: String
        let oldAmount: Int
        let oldCategory: String
        let oldNote: String
        let oldDate: Date
        let oldType: String // "income" or "expense"
    }

    struct SerializedTransaction: Codable {
        let id: String
        let amount: Int
        let category: String
        let note: String
        let date: Date
        let type: String
        let paymentMethod: String
    }
}

// MARK: - Action Group

/// Groups related action records from one user request.
struct AIActionRecordGroup: Identifiable {
    let id: UUID
    let label: String
    let timestamp: Date
    let records: [AIActionRecord]

    var count: Int { records.count }
    var hasUndoable: Bool { records.contains { $0.isUndoable && !$0.isUndone } }
}

// MARK: - Explanation Builder

/// Builds human-readable explanations from trust + intent context.
enum AIExplanationBuilder {

    /// Build an explanation for why an AI action was taken.
    static func explain(
        action: AIAction,
        trustDecision: TrustDecision?,
        intentType: String,
        isAutoExecuted: Bool
    ) -> String {
        let actionLabel = action.type.rawValue.replacingOccurrences(of: "_", with: " ")

        // Blocked actions
        if let decision = trustDecision, decision.level == .neverAuto {
            return decision.blockMessage ?? "Blocked by trust policy"
        }

        // Build from trust reason if available
        if let decision = trustDecision {
            if decision.preferenceInfluenced {
                switch decision.level {
                case .auto:
                    return "User preference allows auto-execution for this low-risk \(actionLabel)"
                case .confirm:
                    return "User preference requires confirmation for \(actionLabel)"
                case .neverAuto:
                    return decision.blockMessage ?? "Blocked by user trust preferences"
                }
            }

            // Risk-based
            if decision.riskScore.level >= .high {
                return "High risk (\(decision.riskScore.level.rawValue)) — requires careful review"
            }
        }

        // Auto-executed: explain why it was safe
        if isAutoExecuted {
            switch action.type {
            case .analyze, .compare, .forecast, .advice:
                return "Read-only analysis — no data changed"
            case .editTransaction:
                let p = action.params
                if p.category != nil && p.amount == nil && p.date == nil {
                    return "Matched your usual merchant-to-category pattern"
                }
                if p.note != nil && p.amount == nil && p.category == nil {
                    return "Low-risk note/tag edit auto-applied"
                }
                return "Auto-applied based on mode and risk level"
            default:
                return "Auto-applied based on mode and risk level"
            }
        }

        // Confirmed actions
        return "Executed after user confirmation"
    }
}

// MARK: - Snapshot Builder

/// Creates ActionSnapshot from execution results.
enum AISnapshotBuilder {

    /// Convert old UndoData to new ActionSnapshot.
    static func fromUndoData(_ undoData: AIActionRecord_Legacy.UndoData) -> ActionSnapshot {
        switch undoData {
        case .addedTransaction(let txnId):
            return .addedTransaction(transactionId: txnId.uuidString)

        case .editedTransaction(let txnId, let oldAmount, let oldCat, let oldNote, let oldDate, let oldType):
            return .editedTransaction(.init(
                transactionId: txnId.uuidString,
                oldAmount: oldAmount,
                oldCategory: oldCat,
                oldNote: oldNote,
                oldDate: oldDate,
                oldType: oldType
            ))

        case .deletedTransaction(let txn):
            return .deletedTransaction(.init(
                id: txn.id.uuidString,
                amount: txn.amount,
                category: txn.category.storageKey,
                note: txn.note,
                date: txn.date,
                type: txn.type == .income ? "income" : "expense",
                paymentMethod: txn.paymentMethod.rawValue
            ))

        case .budgetChanged(let monthKey, let oldAmount):
            return .budgetChanged(monthKey: monthKey, oldAmount: oldAmount)

        case .categoryBudgetChanged(let monthKey, let catKey, let oldAmount):
            return .categoryBudgetChanged(monthKey: monthKey, categoryKey: catKey, oldAmount: oldAmount)

        case .addedSubscription(let name):
            return .addedRecurring(name: name)

        case .createdGoal(let goalId):
            return .createdGoal(goalId: goalId.uuidString)

        case .addedContribution(let goalName, let amount):
            return .addedContribution(goalName: goalName, amount: amount)

        case .nonUndoable:
            return .none
        }
    }

    /// Determine if a snapshot supports undo.
    static func isUndoable(_ snapshot: ActionSnapshot) -> Bool {
        switch snapshot {
        case .none: return false
        default:    return true
        }
    }
}

/// Type alias to reference the old UndoData from AIActionExecutor without renaming it.
/// This preserves backward compat with the executor's return type.
enum AIActionRecord_Legacy {
    typealias UndoData = _LegacyUndoData
}

/// The original UndoData enum, still used by AIActionExecutor.
/// Kept as the executor's return type; converted to ActionSnapshot for storage.
enum _LegacyUndoData {
    case addedTransaction(transactionId: UUID)
    case editedTransaction(transactionId: UUID, oldAmount: Int, oldCategory: String,
                           oldNote: String, oldDate: Date, oldType: String)
    case deletedTransaction(Transaction)
    case budgetChanged(monthKey: String, oldAmount: Int?)
    case categoryBudgetChanged(monthKey: String, categoryKey: String, oldAmount: Int?)
    case addedSubscription(name: String)
    case createdGoal(goalId: UUID)
    case addedContribution(goalName: String, amount: Int)
    case nonUndoable
}

// MARK: - Action History Manager

@MainActor
class AIActionHistory: ObservableObject {
    static let shared = AIActionHistory()

    @Published private(set) var records: [AIActionRecord] = []

    private let maxRecords = 200
    private let storageKey = "ai.actionHistory.v2"

    private init() {
        load()
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Recording
    // ══════════════════════════════════════════════════════════

    /// Record a fully-executed action with trust + intent context.
    func record(
        action: AIAction,
        result: AIActionExecutor.ExecutionResult,
        trustDecision: TrustDecision?,
        classification: IntentClassification?,
        groupId: UUID?,
        groupLabel: String?,
        isAutoExecuted: Bool
    ) {
        let explanation = AIExplanationBuilder.explain(
            action: action,
            trustDecision: trustDecision,
            intentType: classification?.intentType.rawValue ?? "unknown",
            isAutoExecuted: isAutoExecuted
        )

        let snapshot = AISnapshotBuilder.fromUndoData(result.undoData)
        let undoable = result.success && AISnapshotBuilder.isUndoable(snapshot)

        let entry = AIActionRecord(
            id: UUID(),
            action: AIActionRecord.CodableAction(from: action),
            executedAt: Date(),
            summary: result.summary,
            explanation: explanation,
            trustLevel: trustDecision?.level.rawValue ?? "confirm",
            trustReason: trustDecision?.reason ?? "",
            riskScore: trustDecision?.riskScore.value ?? 0,
            riskLevel: trustDecision?.riskScore.level.rawValue ?? "none",
            intentType: classification?.intentType.rawValue ?? "unknown",
            confidence: classification?.confidence ?? 0,
            outcome: result.success ? (isAutoExecuted ? .executed : .confirmed) : .failed,
            isUndoable: undoable,
            groupId: groupId,
            groupLabel: groupLabel,
            snapshot: snapshot
        )

        records.insert(entry, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    /// Record a blocked action (not executed).
    func recordBlocked(
        action: AIAction,
        trustDecision: TrustDecision,
        classification: IntentClassification?,
        groupId: UUID?,
        groupLabel: String?
    ) {
        let explanation = AIExplanationBuilder.explain(
            action: action,
            trustDecision: trustDecision,
            intentType: classification?.intentType.rawValue ?? "unknown",
            isAutoExecuted: false
        )

        let entry = AIActionRecord(
            id: UUID(),
            action: AIActionRecord.CodableAction(from: action),
            executedAt: Date(),
            summary: trustDecision.blockMessage ?? "Action blocked",
            explanation: explanation,
            trustLevel: trustDecision.level.rawValue,
            trustReason: trustDecision.reason,
            riskScore: trustDecision.riskScore.value,
            riskLevel: trustDecision.riskScore.level.rawValue,
            intentType: classification?.intentType.rawValue ?? "unknown",
            confidence: classification?.confidence ?? 0,
            outcome: .blocked,
            isUndoable: false,
            groupId: groupId,
            groupLabel: groupLabel,
            snapshot: .none
        )

        records.insert(entry, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        save()
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Undo
    // ══════════════════════════════════════════════════════════

    /// Whether the most recent undoable action can be undone.
    var canUndo: Bool {
        records.contains { $0.isUndoable && !$0.isUndone }
    }

    /// Undo a specific action by ID. Returns a summary or nil.
    func undo(_ recordId: UUID, store: inout Store) async -> String? {
        guard let idx = records.firstIndex(where: { $0.id == recordId }),
              records[idx].isUndoable, !records[idx].isUndone else { return nil }

        let record = records[idx]
        let result = await performUndo(snapshot: record.snapshot, store: &store)

        if let result {
            records[idx].isUndone = true
            records[idx].undoneAt = Date()
            save()
            return "Undid: \(record.summary)"
        }
        return result
    }

    /// Undo the most recent undoable action.
    func undoLast(store: inout Store) async -> String? {
        guard let record = records.first(where: { $0.isUndoable && !$0.isUndone }) else { return nil }
        return await undo(record.id, store: &store)
    }

    /// Undo all actions in a group.
    func undoGroup(_ groupId: UUID, store: inout Store) async -> [String] {
        let groupRecords = records
            .filter { $0.groupId == groupId && $0.isUndoable && !$0.isUndone }
            .reversed() // undo in reverse execution order

        var results: [String] = []
        for record in groupRecords {
            if let msg = await undo(record.id, store: &store) {
                results.append(msg)
            }
        }
        return results
    }

    private func performUndo(snapshot: ActionSnapshot, store: inout Store) async -> String? {
        switch snapshot {
        case .addedTransaction(let txnIdStr):
            guard let uuid = UUID(uuidString: txnIdStr),
                  let idx = store.transactions.firstIndex(where: { $0.id == uuid }) else { return nil }
            store.transactions.remove(at: idx)
            store.trackDeletion(of: uuid)
            return "removed"

        case .editedTransaction(let fields):
            guard let uuid = UUID(uuidString: fields.transactionId),
                  let idx = store.transactions.firstIndex(where: { $0.id == uuid }) else { return nil }
            store.transactions[idx].amount = fields.oldAmount
            store.transactions[idx].category = Category(storageKey: fields.oldCategory) ?? .other
            store.transactions[idx].note = fields.oldNote
            store.transactions[idx].date = fields.oldDate
            store.transactions[idx].type = fields.oldType == "income" ? .income : .expense
            store.transactions[idx].lastModified = Date()
            return "restored"

        case .deletedTransaction(let serialized):
            guard let uuid = UUID(uuidString: serialized.id) else { return nil }
            let txn = Transaction(
                id: uuid,
                amount: serialized.amount,
                date: serialized.date,
                category: Category(storageKey: serialized.category) ?? .other,
                note: serialized.note,
                paymentMethod: PaymentMethod(rawValue: serialized.paymentMethod) ?? .card,
                type: serialized.type == "income" ? .income : .expense
            )
            store.transactions.append(txn)
            store.deletedTransactionIds.removeAll { $0 == serialized.id }
            return "restored"

        case .budgetChanged(let monthKey, let oldAmount):
            if let old = oldAmount {
                store.budgetsByMonth[monthKey] = old
            } else {
                store.budgetsByMonth.removeValue(forKey: monthKey)
            }
            return "reverted"

        case .categoryBudgetChanged(let monthKey, let catKey, let oldAmount):
            var catBudgets = store.categoryBudgetsByMonth[monthKey] ?? [:]
            if let old = oldAmount {
                catBudgets[catKey] = old
            } else {
                catBudgets.removeValue(forKey: catKey)
            }
            store.categoryBudgetsByMonth[monthKey] = catBudgets
            return "reverted"

        case .addedRecurring(let name):
            if let idx = store.recurringTransactions.firstIndex(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) {
                store.recurringTransactions.remove(at: idx)
                return "removed"
            }
            return nil

        case .createdGoal(let goalIdStr):
            guard let uuid = UUID(uuidString: goalIdStr),
                  let goal = GoalManager.shared.goals.first(where: { $0.id == uuid }) else { return nil }
            _ = await GoalManager.shared.deleteGoal(goal)
            return "removed"

        case .addedContribution(let goalName, let amount):
            guard let goal = GoalManager.shared.goals.first(where: {
                $0.name.localizedCaseInsensitiveCompare(goalName) == .orderedSame
            }) else { return nil }
            _ = await GoalManager.shared.addContribution(to: goal, amount: -amount, note: "Undo via AI")
            return "reversed"

        case .none:
            return nil
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Queries
    // ══════════════════════════════════════════════════════════

    /// Recent records (last N).
    func recent(_ count: Int = 20) -> [AIActionRecord] {
        Array(records.prefix(count))
    }

    /// Records grouped by their groupId.
    func groupedRecords() -> [AIActionRecordGroup] {
        var groups: [UUID: [AIActionRecord]] = [:]
        var ungrouped: [AIActionRecord] = []
        var groupLabels: [UUID: String] = [:]
        var groupTimestamps: [UUID: Date] = [:]

        for record in records {
            if let gid = record.groupId {
                groups[gid, default: []].append(record)
                if let label = record.groupLabel { groupLabels[gid] = label }
                if groupTimestamps[gid] == nil { groupTimestamps[gid] = record.executedAt }
            } else {
                ungrouped.append(record)
            }
        }

        var result: [AIActionRecordGroup] = []

        // Multi-record groups
        for (gid, recs) in groups {
            result.append(AIActionRecordGroup(
                id: gid,
                label: groupLabels[gid] ?? "Grouped actions",
                timestamp: groupTimestamps[gid] ?? Date(),
                records: recs
            ))
        }

        // Ungrouped as single-record groups
        for record in ungrouped {
            result.append(AIActionRecordGroup(
                id: record.id,
                label: record.summary,
                timestamp: record.executedAt,
                records: [record]
            ))
        }

        return result.sorted { $0.timestamp > $1.timestamp }
    }

    /// Count of actions today.
    var todayCount: Int {
        records.filter { Calendar.current.isDateInToday($0.executedAt) }.count
    }

    /// Most common action type.
    var topActionType: String {
        var counts: [String: Int] = [:]
        for record in records {
            counts[record.action.type, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
            .replacingOccurrences(of: "_", with: " ")
            .capitalized ?? "—"
    }

    /// Count of undone actions.
    var undoneCount: Int {
        records.filter(\.isUndone).count
    }

    /// Count of blocked actions.
    var blockedCount: Int {
        records.filter { $0.outcome == .blocked }.count
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Persistence
    // ══════════════════════════════════════════════════════════

    func clear() {
        records.removeAll()
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([AIActionRecord].self, from: data) {
            records = saved
        }
    }
}
