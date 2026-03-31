import SwiftUI

struct UltimateSignUpView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var onSignIn: () -> Void

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack {
                    Spacer()

                    VStack(spacing: 32) {
                        logoSection
                        signUpForm
                        signInLink
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                }
                .frame(minHeight: UIScreen.main.bounds.height - 100)
            }

            if isLoading {
                loadingOverlay
            }
        }
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(DS.Colors.surface)
                    .frame(width: 70, height: 70)

                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(DS.Colors.text)
            }

            Text("CENTMOND")
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Colors.text)

            Text("Create your account")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    // MARK: - Sign Up Form

    private var signUpForm: some View {
        VStack(spacing: 16) {
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.subtext)
                        .frame(width: 20)

                    TextField("your@email.com", text: $email)
                        .font(DS.Typography.body)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                }
                .padding(14)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Password")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.subtext)
                        .frame(width: 20)

                    if showPassword {
                        TextField("At least 6 characters", text: $password)
                            .font(DS.Typography.body)
                            .textContentType(.newPassword)
                    } else {
                        SecureField("At least 6 characters", text: $password)
                            .font(DS.Typography.body)
                            .textContentType(.newPassword)
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                .padding(14)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Confirm Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.subtext)
                        .frame(width: 20)

                    if showConfirmPassword {
                        TextField("Re-enter password", text: $confirmPassword)
                            .font(DS.Typography.body)
                            .textContentType(.newPassword)
                    } else {
                        SecureField("Re-enter password", text: $confirmPassword)
                            .font(DS.Typography.body)
                            .textContentType(.newPassword)
                    }

                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                .padding(14)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Password Requirements
            if !password.isEmpty {
                passwordValidation
            }

            // Error Message
            if let errorMessage = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.danger)

                    Text(errorMessage)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.danger)

                    Spacer()
                }
                .padding(.horizontal, 4)
                .transition(.scale.combined(with: .opacity))
            }

            // Create Account Button
            Button {
                signUp()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Create Account")
                    }
                }
            }
            .buttonStyle(DS.PrimaryButton())
            .disabled(isLoading || !isFormValid)
            .opacity(isFormValid ? 1.0 : 0.5)
        }
        .padding(24)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Password Validation

    private var passwordValidation: some View {
        VStack(alignment: .leading, spacing: 8) {
            requirementRow(
                met: password.count >= 6,
                text: "At least 6 characters"
            )

            requirementRow(
                met: password == confirmPassword && !password.isEmpty && !confirmPassword.isEmpty,
                text: "Passwords match"
            )
        }
    }

    private func requirementRow(met: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(met ? DS.Colors.positive : DS.Colors.textTertiary)

            Text(text)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    // MARK: - Sign In Link

    private var signInLink: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                onSignIn()
            }
        } label: {
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(DS.Colors.subtext)
                Text("Sign In")
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.accent)
            }
            .font(DS.Typography.body)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                Text("Creating account...")
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(DS.Materials.ultraThin)
            .cornerRadius(16)
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        !email.isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    // MARK: - Actions

    private func signUp() {
        errorMessage = nil

        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }

        isLoading = true

        Task {
            do {
                try await authManager.signUp(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    password: password.trimmingCharacters(in: .whitespaces)
                )

                await MainActor.run {
                    isLoading = false
                    SecureLogger.info("Sign up completed")
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Sign up failed: \(error.localizedDescription)"
                    SecureLogger.error("Sign up failed", error)
                }
            }
        }
    }

}

#Preview {
    UltimateSignUpView(onSignIn: {})
        .environmentObject(AuthManager.shared)
}
