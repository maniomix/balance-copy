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
                        
                        // Sign Up Form
                        signUpForm
                        
                        // Sign In Link
                        signInLink
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
            
            Text("Create your account")
                .font(.system(size: 15))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
    }
    
    // MARK: - Sign Up Form
    
    private var signUpForm: some View {
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
                Text("Password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 20)
                    
                    if showPassword {
                        TextField("At least 6 characters", text: $password)
                            .font(.system(size: 16))
                            .textContentType(.newPassword)
                    } else {
                        SecureField("At least 6 characters", text: $password)
                            .font(.system(size: 16))
                            .textContentType(.newPassword)
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
            
            // Confirm Password Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirm Password")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(uiColor: .label))
                
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(uiColor: .secondaryLabel))
                        .frame(width: 20)
                    
                    if showConfirmPassword {
                        TextField("Re-enter password", text: $confirmPassword)
                            .font(.system(size: 16))
                            .textContentType(.newPassword)
                    } else {
                        SecureField("Re-enter password", text: $confirmPassword)
                            .font(.system(size: 16))
                            .textContentType(.newPassword)
                    }
                    
                    Button {
                        showConfirmPassword.toggle()
                    } label: {
                        Image(systemName: showConfirmPassword ? "eye.slash.fill" : "eye.fill")
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
            
            // Password Requirements
            if !password.isEmpty {
                passwordValidation
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
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color(uiColor: .label))
                .foregroundStyle(Color(uiColor: .systemBackground))
                .cornerRadius(12)
            }
            .disabled(isLoading || !isFormValid)
            .opacity(isFormValid ? 1.0 : 0.5)
        }
        .padding(24)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 15, y: 5)
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
                .foregroundStyle(met ? .green : Color(uiColor: .tertiaryLabel))
            
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
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
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                Text("Sign In")
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
                
                Text("Creating account...")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
            }
            .padding(28)
            .background(.ultraThinMaterial)
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
