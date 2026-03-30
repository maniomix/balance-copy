import Foundation
import LocalAuthentication
import Combine

@MainActor
class AppLockManager: ObservableObject {

    static let shared = AppLockManager()

    @Published var isLocked = false

    /// Whether the user has enabled app lock in Settings.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "appLock.enabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "appLock.enabled")
            if !newValue { isLocked = false }
        }
    }

    /// Whether biometric authentication is available on this device.
    var biometricType: LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    var isBiometricAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometricName: String {
        switch biometricType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        @unknown default: return "Biometrics"
        }
    }

    private init() {}

    // MARK: - Lock / Unlock

    func lockIfEnabled() {
        if isEnabled { isLocked = true }
    }

    func authenticate() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometric not available — fall through to unlocked
            isLocked = false
            return
        }

        Task {
            do {
                let success = try await context.evaluatePolicy(
                    .deviceOwnerAuthenticationWithBiometrics,
                    localizedReason: "Unlock Centmond to view your finances"
                )
                if success { isLocked = false }
            } catch {
                SecureLogger.info("Biometric auth failed or cancelled")
            }
        }
    }
}
