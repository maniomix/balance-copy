import Foundation
import Combine

// ============================================================
// MARK: - Review Queue Telemetry (Phase 6b — iOS port)
// ============================================================
//
// Lightweight UserDefaults-backed preferences + counters for the
// Review Queue:
//   - per-reason mute flags (Settings toggles them;
//     `ReviewQueueService` filters by them)
//   - rolling weekly count of resolved items (dismissed or accepted)
//
// Ported from macOS Centmond. Swapped `@Observable` → ObservableObject
// + `@Published` to match iOS's existing AI manager conventions.
// ============================================================

@MainActor
final class ReviewQueueTelemetry: ObservableObject {

    static let shared = ReviewQueueTelemetry()

    private let defaults = UserDefaults.standard
    private let mutedKey     = "reviewQueue.mutedReasons"
    private let weekCountKey = "reviewQueue.weekCount"
    private let weekStartKey = "reviewQueue.weekStart"

    /// Stored as a comma-separated raw-value string so the key stays
    /// grep-able in a defaults dump.
    @Published private(set) var mutedReasons: Set<ReviewReasonCode>

    @Published private(set) var resolvedThisWeek: Int

    private init() {
        let raw = UserDefaults.standard.string(forKey: "reviewQueue.mutedReasons") ?? ""
        self.mutedReasons = Set(
            raw.split(separator: ",").compactMap { ReviewReasonCode(rawValue: String($0)) }
        )
        self.resolvedThisWeek = UserDefaults.standard.integer(forKey: "reviewQueue.weekCount")
        self.rolloverIfNeeded()
    }

    // MARK: - Mute

    func isMuted(_ reason: ReviewReasonCode) -> Bool {
        mutedReasons.contains(reason)
    }

    func setMuted(_ reason: ReviewReasonCode, muted: Bool) {
        if muted { mutedReasons.insert(reason) }
        else     { mutedReasons.remove(reason) }
        persistMuted()
    }

    private func persistMuted() {
        let raw = mutedReasons.map(\.rawValue).sorted().joined(separator: ",")
        defaults.set(raw, forKey: mutedKey)
    }

    // MARK: - Resolved counter

    func recordResolved(count: Int = 1) {
        rolloverIfNeeded()
        resolvedThisWeek += count
        defaults.set(resolvedThisWeek, forKey: weekCountKey)
    }

    /// Reset when we cross into a new ISO week.
    private func rolloverIfNeeded() {
        let current = currentWeekStart()
        let stored = defaults.object(forKey: weekStartKey) as? Date
        if stored == nil || stored! < current {
            resolvedThisWeek = 0
            defaults.set(0, forKey: weekCountKey)
            defaults.set(current, forKey: weekStartKey)
        }
    }

    private func currentWeekStart() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }
}
