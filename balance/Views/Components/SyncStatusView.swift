import SwiftUI

// ============================================================
// MARK: - SyncStatusView (tiny inline hint)
// ============================================================
// Plain centered icon + text. No capsule, no border, no animation.
// Tap → popup with sync details.
//
// Sync continues automatically:
//   - Saves auto-push after a 2-second debounce
//   - Realtime fires on cross-device changes within ~1.5 s
//   - Periodic background sync runs every 2 minutes
//   - Network reconnect triggers an immediate full reconcile
//
// Real-time alerts (offline, error, long-pending) live in the
// `SyncStatusPill` overlay at the top of ContentView.
// ============================================================

struct SyncStatusView: View {
    @Binding var store: Store
    @State private var showDetails = false
    @ObservedObject private var coordinator = SyncCoordinator.shared

    /// Hide the calm "Auto-sync" hint whenever `SyncStatusPill` is showing
    /// something the user actually needs to see (offline / error / long-
    /// pending). The pill overlays the top of the screen, so two indicators
    /// in the same band would collide.
    private var pillIsActive: Bool {
        if !coordinator.isOnline { return true }
        if case .error = coordinator.status { return true }
        return false
    }

    var body: some View {
        Group {
            if !pillIsActive {
                Button {
                    showDetails = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.icloud")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Auto-sync")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(DS.Colors.subtext.opacity(0.75))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Tap to see sync details.")
                .transition(.opacity)
            } else {
                // Empty placeholder keeps layout stable while the pill takes over.
                Color.clear.frame(height: 1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: pillIsActive)
        .sheet(isPresented: $showDetails) {
            SyncDetailsSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

// ============================================================
// MARK: - Details Sheet
// ============================================================

private struct SyncDetailsSheet: View {
    @ObservedObject private var coordinator = SyncCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    private var headlineText: String {
        if !coordinator.isOnline { return "Offline" }
        if case .error = coordinator.status { return "Sync error" }
        if coordinator.status.isActive { return "Syncing now" }
        return "All synced"
    }

    private var headlineColor: Color {
        if !coordinator.isOnline { return DS.Colors.warning }
        if case .error = coordinator.status { return DS.Colors.danger }
        return DS.Colors.positive
    }

    private var headlineIcon: String {
        if !coordinator.isOnline { return "cloud.slash.fill" }
        if case .error = coordinator.status { return "exclamationmark.icloud.fill" }
        if coordinator.status.isActive { return "arrow.triangle.2.circlepath" }
        return "checkmark.icloud.fill"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(headlineColor.opacity(0.14))
                            .frame(width: 76, height: 76)
                        Image(systemName: headlineIcon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(headlineColor)
                    }
                    Text(headlineText)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(DS.Colors.text)

                    if let last = coordinator.lastSuccessfulSync {
                        Text("Last synced \(timeAgo(last))")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)        // clears the drag indicator
                .padding(.bottom, 24)

                // Body
                VStack(alignment: .leading, spacing: 16) {
                    bullet(
                        icon: "arrow.up.arrow.down.circle.fill",
                        title: "Saves push within 2 seconds",
                        body: "Every change you make is uploaded to the cloud after a short debounce — no need to tap anything."
                    )
                    bullet(
                        icon: "antenna.radiowaves.left.and.right",
                        title: "Live updates from other devices",
                        body: "Changes you make on another iPhone, iPad, or Mac appear here within a couple of seconds."
                    )
                    bullet(
                        icon: "clock.arrow.circlepath",
                        title: "Background safety net",
                        body: "A full sync runs in the background every 2 minutes, just to be sure nothing is left behind."
                    )
                    bullet(
                        icon: "wifi.slash",
                        title: "Offline is fine",
                        body: "Edits are saved locally and pushed automatically the moment you're back online."
                    )
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
            }
        }
        .scrollIndicators(.hidden)
        .background(DS.Colors.bg)
    }

    @ViewBuilder
    private func bullet(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60   { return "just now" }
        if s < 3600 { return "\(s / 60) min ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}

#Preview {
    @Previewable @State var s = Store()
    SyncStatusView(store: $s)
        .padding()
        .background(DS.Colors.bg)
}
