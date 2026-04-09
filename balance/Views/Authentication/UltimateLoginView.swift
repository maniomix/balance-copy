import SwiftUI

struct UltimateLoginView: View {
    @EnvironmentObject private var authManager: AuthManager

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var showResetSuccess = false
    @State private var errorMessage: String?

    var onSignUp: () -> Void

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack {
                    Spacer()

                    VStack(spacing: 32) {
                        logoSection
                        loginForm
                        signUpLink
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
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordSheet(
                email: $resetEmail,
                showSuccess: $showResetSuccess
            )
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

            Text("Welcome back")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
        }
    }

    // MARK: - Login Form

    private var loginForm: some View {
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
                HStack {
                    Text("Password")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Colors.text)

                    Spacer()

                    Button {
                        resetEmail = email
                        showForgotPassword = true
                    } label: {
                        Text("Forgot?")
                            .font(DS.Typography.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.subtext)
                        .frame(width: 20)

                    if showPassword {
                        TextField("Enter your password", text: $password)
                            .font(DS.Typography.body)
                            .textContentType(.password)
                    } else {
                        SecureField("Enter your password", text: $password)
                            .font(DS.Typography.body)
                            .textContentType(.password)
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                }
                .padding(14)
                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            // Sign In Button
            Button {
                signIn()
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
            }
            .buttonStyle(DS.PrimaryButton())
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .opacity((email.isEmpty || password.isEmpty) ? 0.5 : 1.0)
        }
        .padding(24)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Sign Up Link

    private var signUpLink: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                onSignUp()
            }
        } label: {
            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .foregroundStyle(DS.Colors.subtext)
                Text("Sign Up")
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

                Text("Signing in...")
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(DS.Materials.ultraThin)
            .cornerRadius(16)
        }
    }

    // MARK: - Actions

    private func signIn() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    password: password.trimmingCharacters(in: .whitespaces)
                )

                await MainActor.run {
                    isLoading = false
                }
            } catch let authError as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = authError.errorDescription ?? "Sign in failed. Please try again."
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = AppConfig.shared.safeErrorMessage(
                        detail: error.localizedDescription,
                        fallback: "Sign in failed. Please check your credentials and try again."
                    )
                }
            }
        }
    }

}

// MARK: - Forgot Password Sheet

struct ForgotPasswordSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Binding var email: String
    @Binding var showSuccess: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    // Icon
                    ZStack {
                        Circle()
                            .fill(DS.Colors.accent.opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: "key.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(DS.Colors.accent)
                    }

                    // Title
                    VStack(spacing: 8) {
                        Text("Reset Password")
                            .font(DS.Typography.largeTitle)
                            .foregroundStyle(DS.Colors.text)

                        Text("Enter your email and we'll send you a link to reset your password")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

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
                    .padding(.horizontal, 24)

                    // Error Message
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(DS.Colors.danger)
                            Text(errorMessage)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.danger)
                        }
                        .padding(.horizontal, 24)
                    }

                    // Send Button
                    Button {
                        sendResetEmail()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Send Reset Link")
                            }
                        }
                    }
                    .buttonStyle(DS.PrimaryButton())
                    .disabled(email.isEmpty || isLoading)
                    .opacity(email.isEmpty ? 0.5 : 1.0)
                    .padding(.horizontal, 24)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(DS.Colors.accent)
                }
            }
        }
    }

    private func sendResetEmail() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await authManager.resetPassword(email: email.trimmingCharacters(in: .whitespaces).lowercased())

                await MainActor.run {
                    isLoading = false
                    showSuccess = true
                    dismiss()
                }
            } catch let authError as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = authError.errorDescription ?? "Could not send reset email."
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = AppConfig.shared.safeErrorMessage(
                        detail: error.localizedDescription,
                        fallback: "Could not send reset email. Please try again."
                    )
                }
            }
        }
    }
}

#Preview {
    UltimateLoginView(onSignUp: {})
        .environmentObject(AuthManager.shared)
}
