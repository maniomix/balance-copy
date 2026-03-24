import SwiftUI

// MARK: - Sync Status View

struct SyncStatusView: View {
    @Binding var store: Store
    @EnvironmentObject private var authManager: AuthManager
    @ObservedObject private var syncCoordinator = SyncCoordinator.shared

    @State private var isSyncingManually: Bool = false
    @State private var syncSuccess: Bool = false
    
    @State private var spinAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var shimmerPhase: CGFloat = -1
    @State private var orb1Angle: Double = 0
    @State private var orb2Angle: Double = 0
    
    // Ripple states (simple, like first version)
    @State private var ripple1Scale: CGFloat = 1
    @State private var ripple1Opacity: Double = 0
    @State private var ripple2Scale: CGFloat = 1
    @State private var ripple2Opacity: Double = 0
    @State private var ripple3Scale: CGFloat = 1
    @State private var ripple3Opacity: Double = 0
    
    private let syncedGreen = Color(red: 0.34, green: 0.80, blue: 0.58)
    private let syncBlue = Color(red: 0.42, green: 0.52, blue: 0.94)
    private let errorOrange = Color(red: 0.95, green: 0.60, blue: 0.25)
    
    private var isSyncing: Bool {
        syncCoordinator.status == .syncing || isSyncingManually
    }
    
    var body: some View {
        Button(action: triggerManualSync) {
            ZStack {
                rippleLayer
                pillBody
            }
        }
        .buttonStyle(SyncPressStyle())
        .onChange(of: syncCoordinator.status) { _, newStatus in
            if newStatus != .syncing && isSyncingManually {
                onSyncComplete()
            }
        }
    }
    
    // MARK: - Pill Body
    
    private var pillBody: some View {
        HStack(spacing: 8) {
            iconArea
                .frame(width: 18, height: 18)
            
            // Single line text — no VStack, no size change
            Text(statusTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(titleColor)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSyncing)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: syncSuccess)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .frame(minWidth: 130)
        .background { pillBg }
        .clipShape(Capsule())
        .overlay { if isSyncing { shimmer } }
        .clipShape(Capsule())
    }
    
    // MARK: - Icon
    
    private var iconArea: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.2), accent.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 14
                    )
                )
                .frame(width: 22, height: 22)
                .scaleEffect(pulseScale)
            
            if isSyncing { orbits }
            
            ZStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(spinAngle))
                    .opacity(isSyncing ? 1 : 0)
                    .scaleEffect(isSyncing ? 1 : 0.4)
                
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hasError ? errorOrange : syncedGreen)
                    .opacity(isSyncing ? 0 : 1)
                    .scaleEffect(isSyncing ? 0.4 : 1)
                    .symbolEffect(.bounce, value: syncSuccess)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.65), value: isSyncing)
        }
        .onChange(of: isSyncing) { _, syncing in
            if syncing { startSyncAnimations() }
            else { stopSyncAnimations() }
        }
    }
    
    // MARK: - Orbits
    
    private var orbits: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 3, height: 3)
                .offset(x: 10)
                .rotationEffect(.degrees(orb1Angle))
            
            Circle()
                .fill(Color.white.opacity(0.25))
                .frame(width: 2, height: 2)
                .offset(x: 10)
                .rotationEffect(.degrees(orb2Angle))
        }
        .transition(.opacity)
    }
    
    // MARK: - Ripple Layer (Simple stroke, like first version)
    
    private var rippleLayer: some View {
        ZStack {
            Capsule()
                .stroke(syncedGreen.opacity(ripple1Opacity), lineWidth: 2.5)
                .frame(width: 110, height: 34)
                .scaleEffect(ripple1Scale)
            
            Capsule()
                .stroke(syncedGreen.opacity(ripple2Opacity), lineWidth: 2.0)
                .frame(width: 110, height: 34)
                .scaleEffect(ripple2Scale)
            
            Capsule()
                .stroke(syncedGreen.opacity(ripple3Opacity), lineWidth: 1.5)
                .frame(width: 110, height: 34)
                .scaleEffect(ripple3Scale)
        }
    }
    
    // MARK: - Pill Background
    
    private var pillBg: some View {
        ZStack {
            Capsule().fill(.ultraThinMaterial)
            
            Capsule()
                .fill(accent.opacity(isSyncing ? 0.04 : (syncSuccess ? 0.06 : 0.0)))
            
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(isSyncing ? 0.25 : (syncSuccess ? 0.3 : 0.06)),
                            accent.opacity(isSyncing ? 0.12 : (syncSuccess ? 0.15 : 0.03))
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        }
        .animation(.easeInOut(duration: 0.4), value: isSyncing)
        .animation(.easeInOut(duration: 0.4), value: syncSuccess)
    }
    
    // MARK: - Shimmer
    
    private var shimmer: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.03), .white.opacity(0.08), .white.opacity(0.03), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .frame(width: geo.size.width * 0.4)
                .offset(x: shimmerPhase * geo.size.width)
                .onAppear {
                    shimmerPhase = -0.5
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        shimmerPhase = 1.5
                    }
                }
                .onDisappear { shimmerPhase = -1 }
        }
    }
    
    // MARK: - Computed
    
    private var accent: Color {
        if isSyncing { return syncBlue }
        if hasError { return errorOrange }
        return syncedGreen
    }
    
    private var hasError: Bool {
        if case .error = syncCoordinator.status { return true }
        return false
    }

    private var statusTitle: String {
        if isSyncing { return "Syncing..." }
        if syncSuccess { return "Synced ✓" }
        if hasError { return "Retry" }
        if case .offline = syncCoordinator.status { return "Offline" }
        if let lastSync = syncCoordinator.lastSuccessfulSync {
            return "Synced · \(timeAgo(from: lastSync))"
        }
        return "Sync"
    }
    
    private var titleColor: Color {
        if isSyncing { return .white }
        if syncSuccess { return syncedGreen }
        if hasError { return errorOrange }
        return Color(uiColor: .secondaryLabel)
    }
    
    // MARK: - Animation Control
    
    private func startSyncAnimations() {
        spinAngle = 0
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            spinAngle = 360
        }
        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
            pulseScale = 1.15
        }
        orb1Angle = 0; orb2Angle = 0
        withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
            orb1Angle = 360
        }
        withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
            orb2Angle = 360
        }
    }
    
    private func stopSyncAnimations() {
        pulseScale = 1.0
    }
    
    // MARK: - Sync Logic
    
    private func triggerManualSync() {
        guard !isSyncing else { return }

        Haptics.medium()
        isSyncingManually = true
        syncSuccess = false

        Task {
            guard let userId = authManager.currentUser?.uid else {
                await MainActor.run { resetState() }
                return
            }

            if let reconciled = await syncCoordinator.fullReconcile(store: store, userId: userId) {
                await MainActor.run {
                    store = reconciled
                    store.save(userId: userId)
                    onSyncComplete()
                }
            } else {
                await MainActor.run {
                    resetState()
                    Haptics.error()
                }
            }
        }
    }
    
    private func onSyncComplete() {
        isSyncingManually = false
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            syncSuccess = true
        }
        
        Haptics.success()
        fireRipples()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.easeInOut(duration: 0.6)) {
                syncSuccess = false
            }
        }
    }
    
    // MARK: - Ripple Fire (original style)
    
    private func fireRipples() {
        // Reset
        ripple1Scale = 1.0; ripple1Opacity = 0
        ripple2Scale = 1.0; ripple2Opacity = 0
        ripple3Scale = 1.0; ripple3Opacity = 0
        
        // Wave 1 — immediate
        withAnimation(.easeOut(duration: 1.2)) {
            ripple1Scale = 2.0
            ripple1Opacity = 0.5
        }
        withAnimation(.easeOut(duration: 1.2).delay(0.3)) {
            ripple1Opacity = 0
        }
        
        // Wave 2
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 1.3)) {
                ripple2Scale = 2.3
                ripple2Opacity = 0.35
            }
            withAnimation(.easeOut(duration: 1.3).delay(0.3)) {
                ripple2Opacity = 0
            }
        }
        
        // Wave 3
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 1.4)) {
                ripple3Scale = 2.6
                ripple3Opacity = 0.2
            }
            withAnimation(.easeOut(duration: 1.4).delay(0.3)) {
                ripple3Opacity = 0
            }
        }
    }
    
    private func resetState() {
        isSyncingManually = false
    }
    
    private func timeAgo(from date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}

// MARK: - Button Style

private struct SyncPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewStore = Store()
    VStack {
        Spacer()
        SyncStatusView(store: $previewStore)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(Color(uiColor: .systemBackground))
    .environmentObject(AuthManager.shared)
}
