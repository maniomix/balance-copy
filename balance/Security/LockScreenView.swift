import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @StateObject private var lockManager = AppLockManager.shared

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text("CENTMOND")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white)

                Spacer().frame(height: 80)

                Image(systemName: biometricIcon)
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)

                Spacer().frame(height: 24)

                Text(statusText)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))

                Spacer()

                Button {
                    lockManager.authenticate()
                } label: {
                    Text(buttonTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(lockManager.isAuthenticating)
                .opacity(lockManager.isAuthenticating ? 0.5 : 1.0)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            lockManager.authenticate()
        }
    }

    private var biometricIcon: String {
        switch lockManager.biometricType {
        case .faceID:  return "faceid"
        case .touchID: return "touchid"
        case .opticID: return "opticid"
        default:       return "lock.fill"
        }
    }

    private var statusText: String {
        if lockManager.isAuthenticating { return "Authenticating…" }
        if lockManager.lastAuthFailed   { return "Authentication failed" }
        return "Locked"
    }

    private var buttonTitle: String {
        if lockManager.lastAuthFailed { return "Try Again" }
        return "Unlock"
    }
}
