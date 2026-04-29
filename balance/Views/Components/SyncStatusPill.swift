import SwiftUI

// ============================================================
// MARK: - SyncStatusPill (Phase 7, polished)
// ============================================================
// Auto-hiding banner for sync state. Surfaces only on conditions
// the user actually needs to see:
//
//   • Offline                              — show immediately
//   • Sync error                           — show immediately
//   • Pending sync stuck > 2 s             — show after sustain delay
//
// The sustain delay matters: a normal save → push cycle takes
// 2-3 s with the 2-s debounce. Without sustain, the pill flips
// "Syncing… → hidden" every keystroke and looks broken. With
// sustain, it stays invisible for fast cycles and only appears
// when something is genuinely slow / stuck.
// ============================================================

struct SyncStatusPill: View {
    @StateObject private var coordinator = SyncCoordinator.shared
    @State private var showPendingPill: Bool = false
    @State private var pendingTask: Task<Void, Never>?

    private let pendingSustain: TimeInterval = 2.0

    var body: some View {
        Group {
            if let info = pillInfo {
                HStack(spacing: 8) {
                    Image(systemName: info.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(info.label)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(info.foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(info.background, in: Capsule())
                .overlay(Capsule().strokeBorder(info.foreground.opacity(0.18), lineWidth: 0.5))
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: pillInfo?.label)
        .onChange(of: coordinator.pendingChanges) { _, isPending in
            // Cancel any in-flight sustain task; restart only if pending again.
            pendingTask?.cancel()
            if isPending {
                pendingTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(pendingSustain * 1_000_000_000))
                    if !Task.isCancelled,
                       coordinator.pendingChanges,
                       coordinator.isOnline,
                       case .syncing = coordinator.status {
                        showPendingPill = true
                    } else if !Task.isCancelled, !coordinator.pendingChanges {
                        showPendingPill = false
                    }
                }
            } else {
                // Clear immediately on success — no point lingering.
                showPendingPill = false
            }
        }
        .onChange(of: coordinator.status) { _, newStatus in
            // Hide the pending pill the instant a non-syncing status fires
            // (success, idle, error). The error case has its own pill below.
            if case .syncing = newStatus { return }
            showPendingPill = false
        }
    }

    private var pillInfo: PillInfo? {
        if !coordinator.isOnline {
            return PillInfo(
                label: "Offline — saved locally",
                icon: "wifi.slash",
                foreground: DS.Colors.warning,
                background: DS.Colors.warning.opacity(0.16)
            )
        }
        if case .error = coordinator.status {
            return PillInfo(
                label: "Sync error — will retry",
                icon: "exclamationmark.triangle.fill",
                foreground: DS.Colors.danger,
                background: DS.Colors.danger.opacity(0.16)
            )
        }
        if showPendingPill {
            return PillInfo(
                label: "Syncing changes…",
                icon: "arrow.triangle.2.circlepath",
                foreground: DS.Colors.accent,
                background: DS.Colors.accent.opacity(0.14)
            )
        }
        return nil
    }

    private struct PillInfo {
        let label: String
        let icon: String
        let foreground: Color
        let background: Color
    }
}
