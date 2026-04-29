import Foundation
import SwiftUI
import Supabase
import Combine

// ============================================================
// MARK: - Auth Manager
// ============================================================
//
// Manages authentication state via Supabase SDK.
// Session tokens are stored by the SDK internally (encrypted).
//
// Security:
//   - All PII (email, userId) logged via SecureLogger (redacted in prod)
//   - Session restoration on launch prevents login screen flash
//   - Sign-out clears all local caches to prevent data leakage
//   - Password validation enforced before sending to server
//
// ============================================================

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    private var supabase: SupabaseManager {
        SupabaseManager.shared
    }

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isCheckingSession = true  // prevents login screen flash
    /// Set after a sign-up where Supabase requires email confirmation.
    /// The auth router shows EmailConfirmationView while this is non-nil.
    @Published var pendingConfirmationEmail: String?

    /// Local rate-limit state. Each sensitive auth surface tracks attempts
    /// independently so a lockout on one flow doesn't block the others.
    private var failedSignInAttempts: Int = 0
    private var lastFailedSignIn: Date?
    private var signUpAttempts: Int = 0
    private var lastSignUpAttempt: Date?
    private var resetPasswordAttempts: Int = 0
    private var lastResetPasswordAttempt: Date?
    private let maxFailedAttempts: Int = 5
    private let lockoutDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Helper Properties

    var userEmail: String {
        currentUser?.email ?? "User"
    }

    var userInitial: String {
        guard let email = currentUser?.email else { return "U" }
        return String(email.prefix(1)).uppercased()
    }

    /// Current Supabase access token for authenticated API requests.
    var accessToken: String? {
        get async {
            do {
                let session = try await supabase.client.auth.session
                return session.accessToken
            } catch {
                return nil
            }
        }
    }

    // MARK: - Init

    init() {
        Task {
            // 1. Restore existing session
            do {
                let session = try await supabase.client.auth.session
                await MainActor.run {
                    self.currentUser = session.user
                    self.isAuthenticated = true
                    self.isCheckingSession = false
                    SecureLogger.info("Session restored for user")
                }
                // Pull cross-device per-user state (Phase 5.6+).
                await SubscriptionStateSync.pull()
                await SavedFilterPresetSync.pull()
                await AIStateSync.pull()
            } catch {
                await MainActor.run {
                    self.isAuthenticated = false
                    self.isCheckingSession = false
                    SecureLogger.debug("No existing session")
                }
            }

            // 2. Listen for future auth state changes
            //
            // With `emitLocalSessionAsInitialSession: true` the SDK now
            // emits the locally-stored session on launch even if its
            // access token has expired — so we must guard on
            // `!session.isExpired` rather than just `session != nil`,
            // otherwise stale tokens would flip the user to "signed in"
            // until the first refresh actually succeeds.
            for await state in await supabase.client.auth.authStateChanges {
                await MainActor.run {
                    let validSession = state.session.flatMap { $0.isExpired ? nil : $0 }
                    self.currentUser = validSession?.user
                    self.isAuthenticated = validSession != nil
                    SecureLogger.debug("Auth state changed: \(self.isAuthenticated)")
                }
            }
        }
    }

    // MARK: - Sign Up

    func signUp(email: String, password: String, displayName: String = "User") async throws {
        // Validate inputs before sending to server
        try validateEmail(email)
        try validatePassword(password)
        try validateDisplayName(displayName)

        // Throttle: don't let attackers spam the signup endpoint
        try checkSignUpLockout()

        SecureLogger.info("Starting sign up")
        do {
            try await supabase.signUp(email: email, password: password, displayName: displayName)
            signUpAttempts = 0
            lastSignUpAttempt = nil
            SecureLogger.info("Sign up completed")
        } catch {
            signUpAttempts += 1
            lastSignUpAttempt = Date()
            SecureLogger.security("Sign up failed (attempt \(signUpAttempts))")
            if signUpAttempts >= maxFailedAttempts {
                SecureLogger.security("Sign up locked out after \(maxFailedAttempts) failed attempts")
                throw AuthError.lockedOut
            }
            throw error
        }

        // After signup, Supabase either:
        //   • returns an active session (email-confirmation OFF) → sign user in
        //   • returns no session (email-confirmation ON) → route to
        //     EmailConfirmationView via `pendingConfirmationEmail`
        do {
            let session = try await supabase.client.auth.session
            await MainActor.run {
                self.currentUser = session.user
                self.isAuthenticated = true
                self.pendingConfirmationEmail = nil
            }
        } catch {
            await MainActor.run {
                self.pendingConfirmationEmail = email
                SecureLogger.info("Sign-up pending email confirmation")
            }
        }
    }

    /// Resend the verification email for an account that's still in the
    /// pending-confirmation state.
    func resendConfirmationEmail() async throws {
        guard let email = pendingConfirmationEmail else { return }
        try await supabase.client.auth.resend(email: email, type: .signup)
        SecureLogger.info("Resent confirmation email")
    }

    /// Cancel the pending-confirmation flow and return to the sign-in screen.
    func cancelPendingConfirmation() {
        pendingConfirmationEmail = nil
    }

    // MARK: - OAuth (Google / Apple)
    //
    // Web-flow OAuth via Supabase. Supabase opens the provider's auth page,
    // user signs in, the redirect URL `centmond://auth-callback` returns
    // the user to the app where `handleOpenURL(_:)` finalizes the session.

    func signInWithGoogle() async throws {
        let url = try supabase.client.auth.getOAuthSignInURL(
            provider: .google,
            redirectTo: URL(string: "centmond://auth-callback")
        )
        await MainActor.run {
            UIApplication.shared.open(url)
        }
        SecureLogger.info("Started Google OAuth flow")
    }

    func signInWithApple() async throws {
        // Apple provider may be disabled in Supabase until the user has
        // an Apple Developer account; this will surface as a server error,
        // which is the intended UX (button shown, nicely errors).
        let url = try supabase.client.auth.getOAuthSignInURL(
            provider: .apple,
            redirectTo: URL(string: "centmond://auth-callback")
        )
        await MainActor.run {
            UIApplication.shared.open(url)
        }
        SecureLogger.info("Started Apple OAuth flow")
    }

    /// Called by the app's onOpenURL when the OAuth provider redirects back
    /// to `centmond://auth-callback?...`. Completes the session.
    func handleOpenURL(_ url: URL) {
        Task {
            do {
                try await supabase.client.auth.session(from: url)
                SecureLogger.info("OAuth session completed")
            } catch {
                SecureLogger.error("OAuth session completion failed", error)
            }
        }
    }

    // MARK: - Stale-session detection

    /// Verify the cached session still maps to a real user on the server.
    /// If the user was deleted on another device the JWT remains in Keychain
    /// and the SDK still reports `isAuthenticated = true`, but every DB write
    /// errors with FK violations against `auth.users`. Calling this on app
    /// foreground / cold start catches that case and force-signs-out.
    ///
    /// **Only signs out on the definitive "no profile row" signal.** RLS
    /// scopes `profiles` to `auth.uid()` so a deleted user gets zero rows
    /// back. Transient network / auth errors are ignored (we don't want a
    /// flight-mode user to lose their session).
    func validateSessionStillValid() async {
        guard isAuthenticated else { return }
        struct ProbeRow: Codable { let id: String }
        do {
            let rows: [ProbeRow] = try await supabase.client
                .from("profiles")
                .select("id")
                .limit(1)
                .execute()
                .value
            if rows.isEmpty {
                SecureLogger.warning("Profile missing — user was deleted; signing out")
                await forceSignOutAfterStaleSession()
            }
        } catch {
            // Network / SDK errors are ignored on the validation path — they
            // could be transient. The sync-error handler below catches the
            // definitive "FK violation against auth.users" case.
            SecureLogger.debug("Session probe errored (non-fatal): \(error.localizedDescription)")
        }
    }

    /// Inspect a sync/repository error and force-sign-out if it indicates
    /// the user no longer exists on the server (FK violation pointing at
    /// `auth.users`, or "user not found" auth error). Call this from any
    /// sync-error catch site that currently shows an error toast.
    func handleSyncError(_ error: Error) {
        let msg = String(describing: error).lowercased()
        let userGone =
            msg.contains("auth.users") ||
            msg.contains("owner_id_fkey") ||
            msg.contains("user_id_fkey") ||
            msg.contains("not present in table \"users\"") ||
            (msg.contains("violates foreign key") && msg.contains("owner_id"))
        guard userGone else { return }
        SecureLogger.warning("Sync error indicates user no longer exists; forcing sign-out")
        Task { await forceSignOutAfterStaleSession() }
    }

    /// Wipes the locally cached state and signs out without surfacing an
    /// error. Used when the server says "you don't exist anymore."
    func forceSignOutAfterStaleSession() async {
        AuthManager.wipeLocalUserData()
        do { try supabase.signOut() } catch {
            // SDK can throw if there's already no session; ignore.
        }
        await MainActor.run {
            self.isAuthenticated = false
            self.currentUser = nil
            self.pendingConfirmationEmail = nil
        }
    }

    /// The set of UserDefaults keys that should be cleared when a user is
    /// removed (delete-account on this device, or stale-session sign-out
    /// because the user was deleted on another device).
    static func wipeLocalUserData() {
        let defaults = UserDefaults.standard
        let keys = [
            "ai.actionHistory.v2", "ai.memoryStore", "ai.merchantMemory",
            "ai.fewShotExamples", "ai.userPreferences", "ai.proactive.dismissedKeys",
            "subscriptions.store_v2", "transactions.savedFilterPresets.v1",
            "goal_local_overlay_v1"
        ]
        for k in keys { defaults.removeObject(forKey: k) }
    }

    // MARK: - Sign In

    func signIn(email: String, password: String) async throws {
        // Check lockout
        try checkSignInLockout()

        do {
            try await supabase.signIn(email: email, password: password)
            // Reset on success
            failedSignInAttempts = 0
            lastFailedSignIn = nil
            SecureLogger.info("Sign in successful")
        } catch {
            failedSignInAttempts += 1
            lastFailedSignIn = Date()
            SecureLogger.security("Sign in failed (attempt \(failedSignInAttempts))")

            if failedSignInAttempts >= maxFailedAttempts {
                SecureLogger.security("Account locked out after \(maxFailedAttempts) failed attempts")
                throw AuthError.lockedOut
            }
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() throws {
        SecureLogger.info("Signing out")
        try supabase.signOut()
        isAuthenticated = false
        currentUser = nil

        // Clear sensitive local caches
        clearLocalData()
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try validateEmail(email)
        // Throttle: prevents both brute-force probing and email-bombing an inbox
        try checkResetPasswordLockout()
        do {
            try await supabase.resetPassword(email: email)
            resetPasswordAttempts = 0
            lastResetPasswordAttempt = nil
            SecureLogger.info("Password reset email sent")
        } catch {
            resetPasswordAttempts += 1
            lastResetPasswordAttempt = Date()
            SecureLogger.security("Password reset failed (attempt \(resetPasswordAttempts))")
            if resetPasswordAttempts >= maxFailedAttempts {
                SecureLogger.security("Password reset locked out after \(maxFailedAttempts) attempts")
                throw AuthError.lockedOut
            }
            throw error
        }
    }

    // MARK: - Change Password

    func changePassword(newPassword: String) async throws {
        try validatePassword(newPassword)
        try await supabase.changePassword(newPassword: newPassword)
        SecureLogger.info("Password changed")
    }

    // MARK: - Email Verification

    func reloadUser() async throws {
        _ = try await supabase.client.auth.session
    }

    func resendVerificationEmail() async throws {
        guard let email = currentUser?.email else {
            throw NSError(domain: "Auth", code: 1, userInfo: [NSLocalizedDescriptionKey: "No email found"])
        }

        try await supabase.client.auth.resend(
            email: email,
            type: .signup
        )
        SecureLogger.info("Verification email resent")
    }

    // MARK: - Validation

    private func validateEmail(_ email: String) throws {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AuthError.invalidEmail
        }
        // Basic email format check
        let emailRegex = "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}"
        guard trimmed.range(of: emailRegex, options: .regularExpression) != nil else {
            throw AuthError.invalidEmail
        }
        guard trimmed.count <= 254 else {
            throw AuthError.invalidEmail
        }
    }

    private func validatePassword(_ password: String) throws {
        guard password.count >= 8 else {
            throw AuthError.weakPassword
        }
        guard password.count <= 128 else {
            throw AuthError.weakPassword
        }
    }

    private func validateDisplayName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 100 else {
            throw AuthError.invalidDisplayName
        }
        // Block obvious injection attempts in display names
        let dangerous = ["<script", "javascript:", "onerror=", "onload="]
        for pattern in dangerous {
            if trimmed.lowercased().contains(pattern) {
                SecureLogger.security("Blocked suspicious display name input")
                throw AuthError.invalidDisplayName
            }
        }
    }

    private func checkSignInLockout() throws {
        try enforceLockout(
            attempts: &failedSignInAttempts,
            lastAttempt: &lastFailedSignIn
        )
    }

    private func checkSignUpLockout() throws {
        try enforceLockout(
            attempts: &signUpAttempts,
            lastAttempt: &lastSignUpAttempt
        )
    }

    private func checkResetPasswordLockout() throws {
        try enforceLockout(
            attempts: &resetPasswordAttempts,
            lastAttempt: &lastResetPasswordAttempt
        )
    }

    /// Shared lockout policy used by sign-in, sign-up, and password reset.
    /// If the threshold has been reached and the window hasn't elapsed, throws
    /// `AuthError.lockedOut`. Otherwise clears expired state and returns.
    private func enforceLockout(attempts: inout Int, lastAttempt: inout Date?) throws {
        guard attempts >= maxFailedAttempts, let lastFail = lastAttempt else { return }

        let elapsed = Date().timeIntervalSince(lastFail)
        if elapsed < lockoutDuration {
            throw AuthError.lockedOut
        } else {
            // Lockout expired — reset counters
            attempts = 0
            lastAttempt = nil
        }
    }

    /// Clear all locally cached user data on sign-out.
    private func clearLocalData() {
        let defaults = UserDefaults.standard
        // Remove profile caches (profile_name_*, profile_image_*)
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            if key.hasPrefix("profile_name_") ||
               key.hasPrefix("profile_image_") ||
               key.hasPrefix("analytics.") {
                defaults.removeObject(forKey: key)
            }
        }
        SecureLogger.debug("Local user caches cleared")
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidEmail
    case weakPassword
    case invalidDisplayName
    case lockedOut

    var errorDescription: String? {
        switch self {
        case .invalidEmail:
            return "Please enter a valid email address."
        case .weakPassword:
            return "Password must be at least 8 characters."
        case .invalidDisplayName:
            return "Please enter a valid display name."
        case .lockedOut:
            return "Too many failed attempts. Please wait a few minutes."
        }
    }
}
