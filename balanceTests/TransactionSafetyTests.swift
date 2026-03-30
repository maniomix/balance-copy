import XCTest
@testable import balance

/// Regression tests for TransactionService mutation safety.
/// Protects no-op semantics, effective-set dedup, and cascading cleanup.
@MainActor
final class TransactionSafetyTests: XCTestCase {

    // MARK: - Helpers

    private func makeTx(
        id: UUID = UUID(),
        amount: Int = 500,
        category: Category = .other,
        type: TransactionType = .expense,
        date: Date = Date(),
        accountId: UUID? = nil,
        goalId: UUID? = nil
    ) -> Transaction {
        Transaction(
            id: id,
            amount: amount,
            date: date,
            category: category,
            note: "",
            paymentMethod: .card,
            type: type,
            accountId: accountId,
            linkedGoalId: goalId
        )
    }

    // MARK: - performDelete no-op safety

    func testDeleteAbsentTransactionReturnsNoChange() {
        var store = Store()
        store.transactions = [makeTx()]

        let absent = makeTx() // Different UUID, not in store
        let result = TransactionService.performDelete(absent, store: &store)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(store.transactions.count, 1, "Store should be unchanged")
    }

    func testDeletePresentTransactionRemovesIt() {
        var store = Store()
        let tx = makeTx()
        store.transactions = [tx]

        let result = TransactionService.performDelete(tx, store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertTrue(store.transactions.isEmpty)
    }

    func testDeleteTracksDeletedId() {
        var store = Store()
        let tx = makeTx()
        store.transactions = [tx]

        _ = TransactionService.performDelete(tx, store: &store)

        XCTAssertTrue(store.deletedTransactionIds.contains(tx.id.uuidString))
    }

    // MARK: - performEdit no-op safety

    func testEditAbsentTransactionReturnsNoChange() {
        var store = Store()
        let tx1 = makeTx()
        store.transactions = [tx1]

        let absent = makeTx() // Not in store
        let edited = makeTx(id: absent.id, amount: 9999)
        let result = TransactionService.performEdit(old: absent, new: edited, store: &store)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.transactions[0].amount, tx1.amount) // Unchanged
    }

    func testEditUpdatesTransaction() {
        var store = Store()
        let tx = makeTx(amount: 500)
        store.transactions = [tx]

        let edited = makeTx(id: tx.id, amount: 9999)
        let result = TransactionService.performEdit(old: tx, new: edited, store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertEqual(store.transactions[0].amount, 9999)
    }

    // MARK: - performDeleteBulk effective-set safety

    func testBulkDeleteEmptyInputReturnsNoChange() {
        var store = Store()
        store.transactions = [makeTx()]

        let result = TransactionService.performDeleteBulk([], store: &store)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(store.transactions.count, 1)
    }

    func testBulkDeleteSkipsAbsentTransactions() {
        var store = Store()
        let present = makeTx()
        let absent = makeTx() // Not in store
        store.transactions = [present]

        let result = TransactionService.performDeleteBulk([absent], store: &store)

        XCTAssertEqual(result, .noChange, "All-absent input should be no-op")
        XCTAssertEqual(store.transactions.count, 1)
    }

    func testBulkDeleteDeduplicatesInput() {
        var store = Store()
        let tx = makeTx()
        store.transactions = [tx]

        // Pass same transaction twice
        let result = TransactionService.performDeleteBulk([tx, tx], store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertTrue(store.transactions.isEmpty, "Transaction should be removed exactly once")
    }

    func testBulkDeleteOnlyRemovesEffectiveSet() {
        var store = Store()
        let tx1 = makeTx()
        let tx2 = makeTx()
        let tx3 = makeTx()
        let absent = makeTx()
        store.transactions = [tx1, tx2, tx3]

        _ = TransactionService.performDeleteBulk([tx1, absent, tx3, tx1], store: &store)

        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.transactions[0].id, tx2.id, "Only tx2 should remain")
    }

    // MARK: - performUndo duplicate-restore safety

    func testUndoSkipsAlreadyPresentTransaction() {
        var store = Store()
        let existing = makeTx(amount: 500)
        store.transactions = [existing]

        let result = TransactionService.performUndo([existing], store: &store)

        XCTAssertEqual(result, .noChange, "Already-present tx should be skipped")
        XCTAssertEqual(store.transactions.count, 1, "No duplicate should be added")
    }

    func testUndoDeduplicatesWithinBatch() {
        var store = Store()
        let tx = makeTx()
        // tx is NOT in store yet

        let result = TransactionService.performUndo([tx, tx, tx], store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertEqual(store.transactions.count, 1, "Should restore exactly once despite 3x input")
    }

    func testUndoRestoresAbsentTransaction() {
        var store = Store()
        let tx = makeTx()
        store.trackDeletion(of: tx.id)

        let result = TransactionService.performUndo([tx], store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertEqual(store.transactions.count, 1)
        XCTAssertEqual(store.transactions[0].id, tx.id)
        XCTAssertFalse(
            store.deletedTransactionIds.contains(tx.id.uuidString),
            "Deletion tracking should be cleared on undo"
        )
    }

    func testUndoMixedPresentAndAbsent() {
        var store = Store()
        let existing = makeTx()
        let deleted1 = makeTx()
        let deleted2 = makeTx()
        store.transactions = [existing]

        let result = TransactionService.performUndo([existing, deleted1, deleted2, deleted1], store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertEqual(store.transactions.count, 3, "existing + deleted1 + deleted2")
    }

    // MARK: - performClearMonth

    func testClearMonthReturnsNoChangeForEmptyMonth() {
        var store = Store()
        let march = makeDate(year: 2025, month: 3, day: 15)

        let result = TransactionService.performClearMonth(march, store: &store)

        XCTAssertEqual(result, .noChange)
    }

    // MARK: - Cascading Cleanup

    func testDidDeleteAccountNilsStaleReferences() {
        var store = Store()
        let accountId = UUID()
        store.transactions = [
            makeTx(accountId: accountId),
            makeTx(accountId: UUID()), // Different account
            makeTx(), // No account
        ]

        let result = TransactionService.didDeleteAccount(accountId, store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertNil(store.transactions[0].accountId, "Stale ref should be nil'd")
        XCTAssertNotNil(store.transactions[1].accountId, "Other account untouched")
        XCTAssertNil(store.transactions[2].accountId, "Was already nil")
    }

    func testDidDeleteAccountNoMatchReturnsNoChange() {
        var store = Store()
        store.transactions = [makeTx(accountId: UUID())]

        let result = TransactionService.didDeleteAccount(UUID(), store: &store)

        XCTAssertEqual(result, .noChange)
    }

    func testDidDeleteGoalNilsStaleReferences() {
        var store = Store()
        let goalId = UUID()
        store.transactions = [
            makeTx(goalId: goalId),
            makeTx(), // No goal
        ]

        let result = TransactionService.didDeleteGoal(goalId, store: &store)

        XCTAssertNotEqual(result, .noChange)
        XCTAssertNil(store.transactions[0].linkedGoalId)
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return Calendar.current.date(from: comps)!
    }
}

// MARK: - PersistenceResult Equatable (for test assertions)
extension PersistenceResult: @retroactive Equatable {
    public static func == (lhs: PersistenceResult, rhs: PersistenceResult) -> Bool {
        switch (lhs, rhs) {
        case (.noChange, .noChange): return true
        case (.savedLocally, .savedLocally): return true
        case (.localSaveFailed, .localSaveFailed): return true
        default: return false
        }
    }
}
