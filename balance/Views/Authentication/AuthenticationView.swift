import SwiftUI

// ============================================================
// MARK: - AuthenticationView (router)
// ============================================================
// Top-level auth router. Displays one of:
//   • SignInView
//   • SignUpView
//   • EmailConfirmationView (when AuthManager.pendingConfirmationEmail is set)
//
// All three views share the gradient background and the new
// OAuth-first design (Google + Apple buttons above the email form).
// ============================================================

struct AuthenticationView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var mode: Mode = .signIn

    enum Mode { case signIn, signUp }

    var body: some View {
        Group {
            if authManager.pendingConfirmationEmail != nil {
                EmailConfirmationView()
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
            } else if mode == .signUp {
                SignUpView(onSwitchToSignIn: { switchTo(.signIn) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                SignInView(onSwitchToSignUp: { switchTo(.signUp) })
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85),
                   value: authManager.pendingConfirmationEmail)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: mode)
    }

    private func switchTo(_ next: Mode) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { mode = next }
    }
}

// ============================================================
// MARK: - Shared brand background
// ============================================================

struct AuthBackground: View {
    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            // Soft accent gradient blobs for warmth
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.18))
                        .frame(width: geo.size.width * 0.7)
                        .blur(radius: 80)
                        .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.25)
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.10))
                        .frame(width: geo.size.width * 0.8)
                        .blur(radius: 100)
                        .offset(x: geo.size.width * 0.25, y: geo.size.height * 0.4)
                }
            }
            .ignoresSafeArea()
        }
    }
}

// ============================================================
// MARK: - Brand header
// ============================================================

struct AuthBrandHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(DS.Colors.accent.opacity(0.18))
                    .frame(width: 76, height: 76)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
            }
            VStack(spacing: 4) {
                Text("CENTMOND")
                    .font(DS.Typography.largeTitle)
                    .foregroundStyle(DS.Colors.text)
                Text(subtitle)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
    }
}

// ============================================================
// MARK: - OAuth buttons
// ============================================================

struct OAuthButtons: View {
    @EnvironmentObject private var authManager: AuthManager
    @Binding var errorMessage: String?

    var body: some View {
        VStack(spacing: 12) {
            providerButton(
                title: "Continue with Google",
                icon: "globe",
                background: DS.Colors.surface,
                foreground: DS.Colors.text,
                stroke: DS.Colors.grid.opacity(0.6)
            ) {
                Task {
                    do { try await authManager.signInWithGoogle() }
                    catch { errorMessage = error.localizedDescription }
                }
            }

            providerButton(
                title: "Continue with Apple",
                icon: "applelogo",
                background: DS.Colors.text,
                foreground: DS.Colors.bg,
                stroke: .clear
            ) {
                Task {
                    do { try await authManager.signInWithApple() }
                    catch {
                        // Apple may not be configured yet — surface friendly message.
                        errorMessage = "Apple sign-in isn't available yet. Please use email or Google for now."
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func providerButton(
        title: String, icon: String,
        background: Color, foreground: Color, stroke: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(background)
            .foregroundStyle(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// ============================================================
// MARK: - Or divider
// ============================================================

struct OrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(DS.Colors.grid).frame(height: 1)
            Text("OR")
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Colors.subtext)
            Rectangle().fill(DS.Colors.grid).frame(height: 1)
        }
    }
}

// ============================================================
// MARK: - SignInView
// ============================================================

struct SignInView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showForgot = false

    let onSwitchToSignUp: () -> Void

    var body: some View {
        ZStack {
            AuthBackground()

            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 60)
                    AuthBrandHeader(title: "Welcome", subtitle: "Sign in to continue")

                    OAuthButtons(errorMessage: $errorMessage)

                    OrDivider()

                    emailForm

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    primaryButton

                    Button {
                        onSwitchToSignUp()
                    } label: {
                        HStack(spacing: 4) {
                            Text("New to Centmond?").foregroundStyle(DS.Colors.subtext)
                            Text("Create an account")
                                .fontWeight(.semibold)
                                .foregroundStyle(DS.Colors.accent)
                        }
                        .font(DS.Typography.body)
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            if isLoading { LoadingOverlay(label: "Signing in…") }
        }
        .sheet(isPresented: $showForgot) {
            ForgotPasswordSheet(prefilledEmail: email)
        }
    }

    private var emailForm: some View {
        VStack(spacing: 14) {
            authField(
                title: "Email",
                icon: "envelope.fill",
                placeholder: "your@email.com",
                text: $email,
                isSecure: false,
                keyboard: .emailAddress,
                contentType: .emailAddress
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Button("Forgot?") { showForgot = true }
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
                passwordField(
                    placeholder: "Enter your password",
                    text: $password,
                    show: $showPassword,
                    contentType: .password
                )
            }
        }
    }

    private var primaryButton: some View {
        Button { signIn() } label: {
            Text("Sign In")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(DS.Colors.accent)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isLoading || email.isEmpty || password.isEmpty)
        .opacity((email.isEmpty || password.isEmpty) ? 0.5 : 1.0)
    }

    private func signIn() {
        isLoading = true
        errorMessage = nil
        Task {
            defer { Task { @MainActor in isLoading = false } }
            do {
                try await authManager.signIn(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    password: password.trimmingCharacters(in: .whitespaces)
                )
            } catch let authError as AuthError {
                await MainActor.run { errorMessage = authError.errorDescription }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// ============================================================
// MARK: - SignUpView
// ============================================================

struct SignUpView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var showPassword = false
    @State private var showConfirm = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onSwitchToSignIn: () -> Void

    private var formValid: Bool {
        !email.isEmpty && password.count >= 6 && password == confirm
    }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 40)
                    AuthBrandHeader(title: "Sign up", subtitle: "Create your account")

                    OAuthButtons(errorMessage: $errorMessage)
                    OrDivider()

                    form

                    if !password.isEmpty { requirements }
                    if let errorMessage { errorBanner(errorMessage) }

                    primaryButton

                    Button(action: onSwitchToSignIn) {
                        HStack(spacing: 4) {
                            Text("Already have an account?").foregroundStyle(DS.Colors.subtext)
                            Text("Sign In")
                                .fontWeight(.semibold)
                                .foregroundStyle(DS.Colors.accent)
                        }
                        .font(DS.Typography.body)
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            if isLoading { LoadingOverlay(label: "Creating account…") }
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            authField(title: "Email", icon: "envelope.fill",
                      placeholder: "your@email.com", text: $email,
                      isSecure: false,
                      keyboard: .emailAddress, contentType: .emailAddress)

            VStack(alignment: .leading, spacing: 8) {
                Text("Password").font(DS.Typography.callout).foregroundStyle(DS.Colors.text)
                passwordField(placeholder: "At least 6 characters",
                              text: $password, show: $showPassword,
                              contentType: .newPassword)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password").font(DS.Typography.callout).foregroundStyle(DS.Colors.text)
                passwordField(placeholder: "Re-enter password",
                              text: $confirm, show: $showConfirm,
                              contentType: .newPassword)
            }
        }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: 6) {
            requirement(met: password.count >= 6, text: "At least 6 characters")
            requirement(met: !confirm.isEmpty && password == confirm, text: "Passwords match")
        }
    }

    private func requirement(met: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? DS.Colors.positive : DS.Colors.subtext)
            Text(text).font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
        }
    }

    private var primaryButton: some View {
        Button { signUp() } label: {
            Text("Create Account")
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .background(DS.Colors.accent)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(isLoading || !formValid)
        .opacity(formValid ? 1.0 : 0.5)
    }

    private func signUp() {
        guard password == confirm else { errorMessage = "Passwords don't match"; return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { Task { @MainActor in isLoading = false } }
            do {
                try await authManager.signUp(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    password: password.trimmingCharacters(in: .whitespaces)
                )
            } catch let authError as AuthError {
                await MainActor.run { errorMessage = authError.errorDescription }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}

// ============================================================
// MARK: - EmailConfirmationView
// ============================================================

struct EmailConfirmationView: View {
    @EnvironmentObject private var authManager: AuthManager
    @State private var isResending = false
    @State private var resendNote: String?

    var body: some View {
        ZStack {
            AuthBackground()
            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.16))
                        .frame(width: 100, height: 100)
                    Image(systemName: "envelope.badge.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
                VStack(spacing: 8) {
                    Text("Check your email")
                        .font(DS.Typography.largeTitle)
                        .foregroundStyle(DS.Colors.text)
                    Text("We sent a confirmation link to")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                    Text(authManager.pendingConfirmationEmail ?? "your email")
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(DS.Colors.text)
                    Text("Tap the link in your inbox to activate your account, then come back here to sign in.")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

                if let resendNote {
                    Text(resendNote)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                VStack(spacing: 12) {
                    Button {
                        resend()
                    } label: {
                        HStack(spacing: 8) {
                            if isResending { ProgressView().tint(.white) }
                            Text(isResending ? "Sending…" : "Resend email")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .background(DS.Colors.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isResending)

                    Button("Back to sign in") {
                        authManager.cancelPendingConfirmation()
                    }
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
    }

    private func resend() {
        isResending = true
        resendNote = nil
        Task {
            defer { Task { @MainActor in isResending = false } }
            do {
                try await authManager.resendConfirmationEmail()
                await MainActor.run { resendNote = "Email sent. Check your inbox (and spam)." }
            } catch {
                await MainActor.run { resendNote = "Could not resend right now. Try again in a minute." }
            }
        }
    }
}

// ============================================================
// MARK: - Shared field helpers + overlay
// ============================================================

@ViewBuilder
private func authField(
    title: String, icon: String, placeholder: String,
    text: Binding<String>, isSecure: Bool,
    keyboard: UIKeyboardType, contentType: UITextContentType
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(title)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.text)
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(DS.Colors.subtext)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .textContentType(contentType)
                .autocapitalization(.none)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
        )
    }
}

@ViewBuilder
private func passwordField(
    placeholder: String,
    text: Binding<String>, show: Binding<Bool>,
    contentType: UITextContentType
) -> some View {
    HStack(spacing: 12) {
        Image(systemName: "lock.fill")
            .foregroundStyle(DS.Colors.subtext)
            .frame(width: 20)
        Group {
            if show.wrappedValue {
                TextField(placeholder, text: text).textContentType(contentType)
            } else {
                SecureField(placeholder, text: text).textContentType(contentType)
            }
        }
        .autocapitalization(.none)
        .autocorrectionDisabled()
        Button {
            show.wrappedValue.toggle()
        } label: {
            Image(systemName: show.wrappedValue ? "eye.slash.fill" : "eye.fill")
                .foregroundStyle(DS.Colors.subtext)
        }
    }
    .padding(14)
    .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
    )
}

@ViewBuilder
private func errorBanner(_ message: String) -> some View {
    HStack(spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(DS.Colors.danger)
        Text(message)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Colors.danger)
        Spacer(minLength: 0)
    }
    .padding(12)
    .background(DS.Colors.danger.opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .transition(.opacity.combined(with: .move(edge: .top)))
}

private struct LoadingOverlay: View {
    let label: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().scaleEffect(1.2).tint(.white)
                Text(label)
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// ============================================================
// MARK: - Forgot Password sheet
// ============================================================

struct ForgotPasswordSheet: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let prefilledEmail: String

    @State private var email = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var sent = false

    var body: some View {
        NavigationStack {
            ZStack {
                AuthBackground()
                VStack(spacing: 24) {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(DS.Colors.accent.opacity(0.16))
                            .frame(width: 90, height: 90)
                        Image(systemName: sent ? "checkmark.circle.fill" : "key.fill")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    Text(sent ? "Check your email" : "Reset password")
                        .font(DS.Typography.largeTitle)
                        .foregroundStyle(DS.Colors.text)
                    Text(sent
                         ? "We sent a reset link to \(email). Open it to choose a new password."
                         : "Enter your email and we'll send you a reset link.")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if !sent {
                        authField(
                            title: "Email", icon: "envelope.fill",
                            placeholder: "your@email.com", text: $email,
                            isSecure: false,
                            keyboard: .emailAddress, contentType: .emailAddress
                        )
                        .padding(.horizontal, 24)

                        if let errorMessage { errorBanner(errorMessage).padding(.horizontal, 24) }

                        Button { send() } label: {
                            HStack {
                                if isLoading { ProgressView().tint(.white) }
                                Text(isLoading ? "Sending…" : "Send reset link")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        .background(DS.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .disabled(email.isEmpty || isLoading)
                        .opacity(email.isEmpty ? 0.5 : 1.0)
                        .padding(.horizontal, 24)
                    } else {
                        Button("Done") { dismiss() }
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(DS.Colors.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(DS.Colors.accent)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { if email.isEmpty { email = prefilledEmail } }
    }

    private func send() {
        isLoading = true
        errorMessage = nil
        Task {
            defer { Task { @MainActor in isLoading = false } }
            do {
                try await authManager.resetPassword(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased()
                )
                await MainActor.run { sent = true }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }
}
