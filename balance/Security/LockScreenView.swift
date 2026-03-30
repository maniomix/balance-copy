import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @StateObject private var lockManager = AppLockManager.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .frame(width: 80, height: 80)

                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color(uiColor: .label))
                }

                Text("CENTMOND")
                    .font(.custom("Pacifico-Regular", size: 28))
                    .foregroundStyle(Color(uiColor: .label))

                Text("Locked")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))

                Spacer()

                // Unlock button
                Button {
                    lockManager.authenticate()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 20))
                        Text("Unlock with \(lockManager.biometricName)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color(uiColor: .label))
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .cornerRadius(14)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .onAppear {
            lockManager.authenticate()
        }
    }

    private var biometricIcon: String {
        switch lockManager.biometricType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }
}
