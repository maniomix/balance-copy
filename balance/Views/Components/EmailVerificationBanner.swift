import SwiftUI


struct EmailVerificationBanner: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isResending = false
    @State private var isChecking = false
    @State private var showSuccess = false
    
    var isEmailVerified: Bool {
        authManager.currentUser?.isEmailVerified ?? true
    }
    
    var body: some View {
        if !isEmailVerified {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.badge.fill")
                        .foregroundStyle(DS.Colors.warning)
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Verify your email")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        Text("Check your inbox and click the verification link")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Refresh button
                    Button {
                        checkVerification()
                    } label: {
                        if isChecking {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(.white.opacity(0.2))
                    )
                    .disabled(isChecking)
                    
                    // Resend button
                    if isResending {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            resendEmail()
                        } label: {
                            Text("Resend")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(.white.opacity(0.2))
                                )
                        }
                    }
                }
                .padding(12)
                .background(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.8),
                            Color.orange.opacity(0.6)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                if showSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Colors.positive)
                        Text("Verification email sent! Check your inbox.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(DS.Colors.positive.opacity(0.15))
                }
            }
            .task {
                // Auto-check every 30 seconds
                while !isEmailVerified {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    await checkVerification()
                }
            }
        }
    }
    
    private func checkVerification() {
        guard !isChecking else { return }
        
        isChecking = true
        Task {
            do {
                try await authManager.reloadUser()
                await MainActor.run {
                    isChecking = false
                }
            } catch {
                await MainActor.run {
                    isChecking = false
                }
            }
        }
    }
    
    private func resendEmail() {
        isResending = true
        Task {
            do {
                try await authManager.resendVerificationEmail()
                await MainActor.run {
                    isResending = false
                    showSuccess = true
                }
                
                // Hide success message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    showSuccess = false
                }
            } catch {
                await MainActor.run {
                    isResending = false
                }
            }
        }
    }
}
