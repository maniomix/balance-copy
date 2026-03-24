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
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()
            
            // Centered Content
            ScrollView {
                VStack {
                    Spacer()
                    
                    // Main Content
                    VStack(spacing: 32) {
                        // Logo & Title
                        logoSection
                        
                        // Login Form
                        loginForm
                        
                        // OR Divider
                        orDivider
                        
                        // Social Login
                        socialButtons
                        
                        // Sign Up Link
                        signUpLink
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
                .frame(minHeight: UIScreen.main.bounds.height - 100)
            }
            
            // Loading Overlay
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
            // App Icon
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(width: 70, height: 70)
                
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color(uiColor: .label))
            }
            
            Text("CENTMOND")
                .font(.custom("Pacifico-Regular", size: 30))
                .foregroundStyle(Color(uiColor: .label))
            
            Text("Welcome back")
                .font(.system(size: 15))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }
    
    // MARK: - Login Form
    
    private var loginForm: some View {
        VStack(spacing: 16) {
            // Email Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 20)
                    
                    TextField("your@email.com", text: $email)
                        .font(.system(size: 16))
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .textContentType(.emailAddress)
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(uiColor: .separator), lineWidth: 1)
                )
            }
            
            // Password Field
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Password")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(uiColor: .label))
                    
                    Spacer()
                    
                    Button {
                        resetEmail = email
                        showForgotPassword = true
                    } label: {
                        Text("Forgot?")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 20)
                    
                    if showPassword {
                        TextField("Enter your password", text: $password)
                            .font(.system(size: 16))
                            .textContentType(.password)
                    } else {
                        SecureField("Enter your password", text: $password)
                            .font(.system(size: 16))
                            .textContentType(.password)
                    }
                    
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                    }
                }
                .padding(14)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(uiColor: .separator), lineWidth: 1)
                )
            }
            
            // Error Message
            if let errorMessage = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                    
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                    
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
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(uiColor: .label))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .cornerRadius(12)
            }
            .disabled(isLoading || email.isEmpty || password.isEmpty)
            .opacity((email.isEmpty || password.isEmpty) ? 0.5 : 1.0)
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 15, y: 5)
    }
    
    // MARK: - OR Divider
    
    private var orDivider: some View {
        HStack {
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
            
            Text("OR")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
                .padding(.horizontal, 12)
            
            Rectangle()
                .fill(Color(uiColor: .separator))
                .frame(height: 1)
        }
    }
    
    // MARK: - Social Buttons
    
    private var socialButtons: some View {
        Button {
            signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "g.circle.fill")
                    .font(.system(size: 20))
                
                Text("Continue with Google")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color(uiColor: .secondarySystemBackground))
            .foregroundStyle(Color(uiColor: .label))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(uiColor: .separator), lineWidth: 1)
            )
        }
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
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                Text("Sign Up")
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.accent)
            }
            .font(.system(size: 15))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial)
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
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func signInWithGoogle() {
        print("🔵 Google Sign In - Coming soon")
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
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                
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
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(Color(uiColor: .label))
                        
                        Text("Enter your email and we'll send you a link to reset your password")
                            .font(.system(size: 14))
                            .foregroundStyle(Color(uiColor: .secondaryLabel))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color(uiColor: .label))
                        
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color(uiColor: .secondaryLabel))
                                .frame(width: 20)
                            
                            TextField("your@email.com", text: $email)
                                .font(.system(size: 16))
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .textContentType(.emailAddress)
                        }
                        .padding(14)
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(uiColor: .separator), lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 24)
                    
                    // Error Message
                    if let errorMessage = errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.red)
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
                                    .font(.system(size: 17, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(DS.Colors.accent)
                        .foregroundStyle(.white)
                        .cornerRadius(12)
                    }
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
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    UltimateLoginView(onSignUp: {})
        .environmentObject(AuthManager.shared)
}
