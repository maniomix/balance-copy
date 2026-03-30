import XCTest
@testable import balance

/// Regression tests for engine-level correctness:
/// - ReviewItem stableKey determinism
/// - SubscriptionEngine normalization and similarity
/// - ForecastEngine safe-to-spend horizon filtering
final class EngineCorrectnessTests: XCTestCase {

    // ================================================================
    // MARK: - ReviewItem stableKey
    // ================================================================

    func testStableKeyIsDeterministicRegardlessOfIdOrder() {
        let id1 = UUID()
        let id2 = UUID()
        let id3 = UUID()

        let itemA = ReviewItem(
            transactionIds: [id1, id2, id3],
            type: .possibleDuplicate,
            priority: .high,
            reason: "Test",
            suggestedAction: .markDuplicate
        )
        let itemB = ReviewItem(
            transactionIds: [id3, id1, id2], // Different order
            type: .possibleDuplicate,
            priority: .high,
            reason: "Test",
            suggestedAction: .markDuplicate
        )

        XCTAssertEqual(itemA.stableKey, itemB.stableKey, "Same IDs in different order must produce same key")
    }

    func testStableKeyDiffersForDifferentTypes() {
        let ids = [UUID()]
        let dup = ReviewItem(
            transactionIds: ids,
            type: .possibleDuplicate,
            priority: .high,
            reason: "Test",
            suggestedAction: .markDuplicate
        )
        let spike = ReviewItem(
            transactionIds: ids,
            type: .spendingSpike,
            priority: .high,
            reason: "Test",
            suggestedAction: .reviewAmount
        )

        XCTAssertNotEqual(dup.stableKey, spike.stableKey)
    }

    func testStableKeyDiffersForDifferentTransactions() {
        let item1 = ReviewItem(
            transactionIds: [UUID()],
            type: .possibleDuplicate,
            priority: .high,
            reason: "Test",
            suggestedAction: .markDuplicate
        )
        let item2 = ReviewItem(
            transactionIds: [UUID()],
            type: .possibleDuplicate,
            priority: .high,
            reason: "Test",
            suggestedAction: .markDuplicate
        )

        XCTAssertNotEqual(item1.stableKey, item2.stableKey)
    }

    func testStableKeyFormat() {
        let id = UUID()
        let item = ReviewItem(
            transactionIds: [id],
            type: .uncategorized,
            priority: .low,
            reason: "Test",
            suggestedAction: .assignCategory
        )

        XCTAssertTrue(item.stableKey.hasPrefix("uncategorized:"))
        XCTAssertTrue(item.stableKey.contains(id.uuidString.uppercased()))
    }

    // ================================================================
    // MARK: - SubscriptionEngine.normalizeMerchant
    // ================================================================

    func testNormalizeMerchantStripsPaymentPrefixes() {
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("PP*SPOTIFY"), "spotify")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("SQ *COFFEE SHOP"), "coffee shop")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("PAYPAL *NETFLIX"), "netflix")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("GOOGLE *YOUTUBE"), "youtube")
    }

    func testNormalizeMerchantStripsTrailingNumbers() {
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("NETFLIX #12345"), "netflix")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("SPOTIFY - 8923ab"), "spotify")
    }

    func testNormalizeMerchantStripsCountryCodes() {
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("SPOTIFY US"), "spotify")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("NETFLIX UK"), "netflix")
    }

    func testNormalizeMerchantStripsSuffixes() {
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("SPOTIFY.COM"), "spotify")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("NOTION.IO"), "notion")
        XCTAssertEqual(SubscriptionEngine.normalizeMerchant("ACME INC"), "acme")
    }

    func testNormalizeMerchantCollapsesWhitespace() {
        XCTAssertEqual(
            SubscriptionEngine.normalizeMerchant("  COFFEE   SHOP  "),
            "coffee shop"
        )
    }

    func testNormalizeMerchantConsistency() {
        // The same merchant with different noise must normalize to the same string
        let variants = [
            "PP*Spotify #1234",
            "SPOTIFY.COM US",
            "  Spotify  ",
        ]
        let normalized = Set(variants.map { SubscriptionEngine.normalizeMerchant($0) })
        XCTAssertEqual(normalized.count, 1, "All variants should normalize to the same key: \(normalized)")
    }

    // MARK: - SubscriptionEngine.merchantNamesSimilar

    func testMerchantNamesSimilarExactMatch() {
        XCTAssertTrue(SubscriptionEngine.merchantNamesSimilar("Netflix", "netflix"))
    }

    func testMerchantNamesSimilarContainment() {
        XCTAssertTrue(SubscriptionEngine.merchantNamesSimilar("Spotify", "Spotify Premium"))
        XCTAssertTrue(SubscriptionEngine.merchantNamesSimilar("Netflix HD", "Netflix"))
    }

    func testMerchantNamesSimilarFirstWordMatch() {
        XCTAssertTrue(SubscriptionEngine.merchantNamesSimilar("Netflix Standard", "Netflix Premium"))
    }

    func testMerchantNamesSimilarShortFirstWordNoMatch() {
        // First words shorter than 4 chars should NOT match
        XCTAssertFalse(SubscriptionEngine.merchantNamesSimilar("AI Labs", "AI Research"))
    }

    func testMerchantNamesSimilarUnrelated() {
        XCTAssertFalse(SubscriptionEngine.merchantNamesSimilar("Netflix", "Spotify"))
    }

    // ================================================================
    // MARK: - ForecastEngine.computeSafeToSpend
    // ================================================================

    func testSafeToSpendSubtractsBillsAndGoals() {
        let bills = [
            UpcomingBill(name: "Rent", amount: 50000, dueDate: Date(), category: .rent, isRecurring: true),
            UpcomingBill(name: "Phone", amount: 5000, dueDate: Date(), category: .bills, isRecurring: true),
        ]

        let result = ForecastEngine.computeSafeToSpend(
            currentRemaining: 200000,
            daysRemaining: 15,
            upcomingBills: bills,
            monthlyGoalContributions: 10000,
            budget: 200000,
            budgetIsMissing: false
        )

        // 200000 - 55000(bills) - 10000(goals) = 135000
        XCTAssertEqual(result.totalAmount, 135000)
        XCTAssertEqual(result.reservedForBills, 55000)
        XCTAssertEqual(result.reservedForGoals, 10000)
        XCTAssertFalse(result.isOvercommitted)
    }

    func testSafeToSpendOvercommittedClampedToZero() {
        let bills = [
            UpcomingBill(name: "Rent", amount: 150000, dueDate: Date(), category: .rent, isRecurring: true),
        ]

        let result = ForecastEngine.computeSafeToSpend(
            currentRemaining: 100000,
            daysRemaining: 10,
            upcomingBills: bills,
            monthlyGoalContributions: 20000,
            budget: 100000,
            budgetIsMissing: false
        )

        // 100000 - 150000 - 20000 = -70000 → clamped to 0
        XCTAssertEqual(result.totalAmount, 0)
        XCTAssertTrue(result.isOvercommitted)
        XCTAssertEqual(result.overcommitAmount, 70000)
    }

    func testSafeToSpendPerDayDivision() {
        let result = ForecastEngine.computeSafeToSpend(
            currentRemaining: 30000,
            daysRemaining: 10,
            upcomingBills: [],
            monthlyGoalContributions: 0,
            budget: 30000,
            budgetIsMissing: false
        )

        XCTAssertEqual(result.totalAmount, 30000)
        XCTAssertEqual(result.perDay, 3000) // 30000 / 10
    }

    func testSafeToSpendZeroDaysRemaining() {
        let result = ForecastEngine.computeSafeToSpend(
            currentRemaining: 10000,
            daysRemaining: 0,
            upcomingBills: [],
            monthlyGoalContributions: 0,
            budget: 10000,
            budgetIsMissing: false
        )

        // perDay should be totalAmount when daysRemaining is 0 (not crash)
        XCTAssertEqual(result.perDay, 10000)
    }

    func testSafeToSpendNoBillsNoGoals() {
        let result = ForecastEngine.computeSafeToSpend(
            currentRemaining: 50000,
            daysRemaining: 20,
            upcomingBills: [],
            monthlyGoalContributions: 0,
            budget: 50000,
            budgetIsMissing: false
        )

        XCTAssertEqual(result.totalAmount, 50000)
        XCTAssertEqual(result.reservedForBills, 0)
        XCTAssertEqual(result.reservedForGoals, 0)
    }
}
