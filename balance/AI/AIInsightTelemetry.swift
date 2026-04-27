import Foundation
import Combine
import os.log

// ============================================================
// MARK: - Insight Telemetry (Phase 2 — iOS port)
// ============================================================
//
// Per-detector counters: shown / dismissed / actedOn / lastSeen.
// Persisted in UserDefaults (low cardinality — ~20 detector IDs
// max; no SwiftData needed). Two features:
//
//   1. Auto-mute — detectors the user repeatedly dismisses without
//      ever acting on get suppressed automatically. User can un-mute
//      from Settings. Prevents noise accumulating.
//
//   2. Surface — Settings can list every detector with its counters
//      so the user can see what's firing and toggle it.
//
// Ported from macOS Centmond `InsightTelemetry.swift`. Swapped
// @Observable → ObservableObject + @Published to match iOS's
// existing AI manager conventions.
// ============================================================

private let logger = Logger(subsystem: "com.centmond.ai", category: "InsightTelemetry")

@MainActor
final class InsightTelemetry: ObservableObject {

    static let shared = InsightTelemetry()

    struct Counters: Codable, Equatable {
        var shown: Int = 0
        var dismissed: Int = 0
        var actedOn: Int = 0
        var muted: Bool = false
        var lastSeen: Date?

        /// Dismiss-through-rate ignoring zero-denominator. Used by the
        /// auto-mute heuristic and surfaced on the Settings row.
        var dismissRate: Double {
            guard shown > 0 else { return 0 }
            return Double(dismissed) / Double(shown)
        }
    }

    @Published private(set) var counters: [String: Counters] = [:]

    // Auto-mute thresholds. Conservative — the goal is to stop obvious noise,
    // not to silently suppress anything dismissed twice.
    private static let autoMuteMinShown = 10
    private static let autoMuteMinDismissRate = 0.8

    private static let storageKey = "ai.insightTelemetry.v1"

    private init() { load() }

    // MARK: - Recording

    /// Mark that a detector's insight reached the user's feed on this
    /// refresh. Callers should dedupe first and record once per surviving
    /// insight.
    func recordShown(detectorID: String) {
        var c = counters[detectorID, default: Counters()]
        c.shown += 1
        c.lastSeen = .now
        counters[detectorID] = c
        save()
    }

    /// Mark that the user explicitly dismissed or snoozed an insight. The
    /// auto-mute check runs here so a noisy detector gets silenced on the
    /// dismissal that crosses the threshold — no wait for next refresh.
    func recordDismissed(detectorID: String) {
        var c = counters[detectorID, default: Counters()]
        c.dismissed += 1
        if !c.muted, c.shown >= Self.autoMuteMinShown,
           c.actedOn == 0,
           c.dismissRate >= Self.autoMuteMinDismissRate {
            c.muted = true
            logger.notice("Auto-muting detector \(detectorID, privacy: .public) — shown=\(c.shown), dismissed=\(c.dismissed)")
        }
        counters[detectorID] = c
        save()
    }

    /// Mark that the user ran the suggested action OR followed the deeplink.
    /// Any `actedOn` permanently blocks auto-mute — a detector the user has
    /// engaged with is considered useful, regardless of later dismissals.
    func recordActedOn(detectorID: String) {
        var c = counters[detectorID, default: Counters()]
        c.actedOn += 1
        c.lastSeen = .now
        counters[detectorID] = c
        save()
    }

    // MARK: - Mute state

    func isMuted(_ detectorID: String) -> Bool {
        counters[detectorID]?.muted ?? false
    }

    func setMuted(_ detectorID: String, muted: Bool) {
        var c = counters[detectorID, default: Counters()]
        c.muted = muted
        counters[detectorID] = c
        save()
    }

    /// Clear all counters. Exposed for "Reset telemetry" in Settings.
    func reset() {
        counters = [:]
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(counters) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([String: Counters].self, from: data) else {
            return
        }
        counters = decoded
    }
}
