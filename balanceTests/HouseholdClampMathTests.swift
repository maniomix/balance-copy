import XCTest
@testable import balance

/// Tests for the Phase 2 clamp-safe household settlement math ported from
/// macOS. Every test mutates `HouseholdManager.shared` directly, so each
/// sets up a fresh household and tears down the UserDefaults keys.
///
/// Exercises:
///   - `openDebt` is direction-safe and never goes below zero
///   - `netBalance` is the signed difference of the two clamped legs
///   - `openPairBalances` nets opposite-direction debts into one row
///   - `settleUp` walks FIFO by createdAt and only flips expenses whose
///     share fits the remaining budget
///   - archived members are excluded from counterparty lists
@MainActor
final class HouseholdClampMathTests: XCTestCase {

    private let testUserId = "test-user-owner"
    private let partnerId  = "test-user-partner"
    private let thirdId    = "test-user-third"

    override func setUp() {
        super.setUp()
        resetHouseholdState()
    }

    override func tearDown() {
        resetHouseholdState()
        super.tearDown()
    }

    private func resetHouseholdState() {
        let mgr = HouseholdManager.shared
        mgr.household = nil
        mgr.sharedBudgets = []
        mgr.splitExpenses = []
        mgr.settlements = []
        mgr.sharedGoals = []
        mgr.pendingInvites = []
        let defaults = UserDefaults.standard
        for key in [
            "household_\(testUserId)",
            "split_expenses_\(testUserId)",
            "settlements_\(testUserId)",
            "shared_budgets_\(testUserId)",
            "shared_goals_\(testUserId)",
            "household_invites_\(testUserId)"
        ] { defaults.removeObject(forKey: key) }
    }

    private func seedTwoMemberHousehold() -> Household {
        let owner = HouseholdMember(userId: testUserId, displayName: "Owner", role: .owner)
        let partner = HouseholdMember(userId: partnerId, displayName: "Partner", role: .partner)
        let h = Household(createdBy: testUserId, members: [owner, partner])
        HouseholdManager.shared.household = h
        return h
    }

    // MARK: - openDebt clamps to zero

    func testOpenDebtClampsAtZeroOnOverSettlement() {
        let h = seedTwoMemberHousehold()
        let mgr = HouseholdManager.shared

        // Partner paid $100 (10000c). Equal split → owner owes 5000c.
        mgr.splitExpenses = [
            SplitExpense(
                householdId: h.id,
                amount: 10_000,
                paidBy: partnerId,
                splitRule: .equal,
                createdAt: Date()
            )
        ]
        XCTAssertEqual(mgr.openDebt(debtor: testUserId, creditor: partnerId), 5_000)

        // Owner over-pays $80 (8000c). Debt must clamp to 0, NOT flip to -3000.
        mgr.settlements = [
            Settlement(
                householdId: h.id,
                fromUserId: testUserId,
                toUserId: partnerId,
                amount: 8_000
            )
        ]
        XCTAssertEqual(mgr.openDebt(debtor: testUserId, creditor: partnerId), 0)
        XCTAssertEqual(mgr.openDebt(debtor: partnerId, creditor: testUserId), 0,
                       "Over-settlement must not create reverse debt")
    }

    // MARK: - netBalance signed

    func testNetBalanceSignedDifference() {
        let h = seedTwoMemberHousehold()
        let mgr = HouseholdManager.shared

        // Partner paid $60 → owner owes 3000c
        mgr.splitExpenses = [
            SplitExpense(
                householdId: h.id,
                amount: 6_000,
                paidBy: partnerId,
                splitRule: .equal,
                createdAt: Date()
            )
        ]
        XCTAssertEqual(mgr.netBalance(fromUser: testUserId, toUser: partnerId), 3_000)
        XCTAssertEqual(mgr.netBalance(fromUser: partnerId, toUser: testUserId), -3_000)
    }

    // MARK: - openPairBalances nets opposite-direction debts

    func testPairBalancesNetOppositeDirections() {
        let h = seedTwoMemberHousehold()
        let mgr = HouseholdManager.shared

        // Partner paid $60 → owner owes 3000c
        // Owner paid $40 → partner owes 2000c
        // Net: owner owes partner 1000c
        mgr.splitExpenses = [
            SplitExpense(householdId: h.id, amount: 6_000, paidBy: partnerId,
                         splitRule: .equal, createdAt: Date(timeIntervalSinceNow: -200)),
            SplitExpense(householdId: h.id, amount: 4_000, paidBy: testUserId,
                         splitRule: .equal, createdAt: Date(timeIntervalSinceNow: -100))
        ]

        let pairs = mgr.openPairBalances()
        XCTAssertEqual(pairs.count, 1, "Opposite directions should collapse to one row")
        XCTAssertEqual(pairs.first?.debtor.userId, testUserId)
        XCTAssertEqual(pairs.first?.creditor.userId, partnerId)
        XCTAssertEqual(pairs.first?.amount, 1_000)
    }

    // MARK: - settleUp FIFO + fit-only flip

    func testSettleUpWalksFIFOAndOnlyFlipsExpensesThatFit() {
        let h = seedTwoMemberHousehold()
        let mgr = HouseholdManager.shared

        let oldest = SplitExpense(
            householdId: h.id, amount: 4_000, paidBy: partnerId,
            splitRule: .equal, createdAt: Date(timeIntervalSinceNow: -300)
        )
        let middle = SplitExpense(
            householdId: h.id, amount: 10_000, paidBy: partnerId,
            splitRule: .equal, createdAt: Date(timeIntervalSinceNow: -200)
        )
        let newest = SplitExpense(
            householdId: h.id, amount: 2_000, paidBy: partnerId,
            splitRule: .equal, createdAt: Date(timeIntervalSinceNow: -100)
        )
        mgr.splitExpenses = [newest, oldest, middle]

        // Owner settles 3000c toward partner.
        //   oldest  share = 2000c → fits, flipped
        //   middle  share = 5000c → doesn't fit in remaining 1000c → SKIPPED
        //   newest  share = 1000c → fits in remaining 1000c → flipped
        mgr.settleUp(fromUser: testUserId, toUser: partnerId, amount: 3_000)

        let byId = Dictionary(uniqueKeysWithValues: mgr.splitExpenses.map { ($0.id, $0) })
        XCTAssertTrue(byId[oldest.id]?.isSettled ?? false, "Oldest share fits first")
        XCTAssertFalse(byId[middle.id]?.isSettled ?? true, "Middle share doesn't fit — must stay open")
        XCTAssertTrue(byId[newest.id]?.isSettled ?? false, "Newest share fits remainder")
        XCTAssertEqual(mgr.settlements.count, 1)
        XCTAssertEqual(mgr.settlements.first?.amount, 3_000)
    }

    // MARK: - Archived members

    func testArchivedMemberFlipsActiveFlag() {
        var h = seedTwoMemberHousehold()
        // Need a third member whom the owner can archive.
        let third = HouseholdMember(userId: thirdId, displayName: "Third", role: .adult)
        h.members.append(third)
        HouseholdManager.shared.household = h

        HouseholdManager.shared.archiveMember(userId: thirdId)

        let archived = HouseholdManager.shared.household?.member(for: thirdId)
        XCTAssertEqual(archived?.isActive, false)
        XCTAssertNotNil(archived?.archivedAt)
        XCTAssertEqual(HouseholdManager.shared.household?.activeMembers.count, 2)
    }
}
