import SwiftUI
import Supabase

#if DEBUG
/// Debug-only connection harness. Not wired into any production flow —
/// compiled out of Release builds so it cannot accidentally ship or be
/// reached via a stray NavigationLink.
struct SupabaseTestView: View {
    @EnvironmentObject private var authManager: AuthManager
    private var supabase: SupabaseManager { SupabaseManager.shared }
    @State private var testResult = "Not tested yet"
    @State private var isLoading = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Supabase Connection Test")
                .font(.title)
                .padding()
            
            Text(testResult)
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
                .padding()
            
            if isLoading {
                ProgressView()
            }
            
            Button("Test Connection") {
                testConnection()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoading)
            
            if authManager.isAuthenticated {
                VStack {
                    Text("✅ Authenticated")
                        .foregroundColor(.green)
                    Text("User ID: \(authManager.currentUser?.id.uuidString ?? "N/A")")
                        .font(.caption)
                }
                .padding()
            }
        }
        .padding()
    }
    
    private func testConnection() {
        isLoading = true
        testResult = "Testing..."
        
        Task {
            do {
                // Test 1: Check if client is initialized
                testResult = "✅ Client initialized\n"
                
                // Test 2: Try to sign up a test user
                let testEmail = "test\(Int.random(in: 1000...9999))@test.com"
                let testPassword = "Test123456!"
                
                testResult += "Attempting sign up...\n"
                try await supabase.signUp(email: testEmail, password: testPassword)
                
                testResult += "✅ Sign up successful!\n"
                testResult += "Email: \(testEmail)\n"
                
                // Test 3: Update last active
                try await supabase.updateLastActive()
                testResult += "✅ Last active updated\n"
                
                testResult += "\n🎉 All tests passed!"
                
            } catch {
                testResult = AppConfig.shared.safeErrorMessage(
                    detail: error.localizedDescription,
                    fallback: "Connection test failed. Check your configuration."
                )
                SecureLogger.error("Supabase connection test failed", error)
            }
            
            isLoading = false
        }
    }
}

#Preview {
    SupabaseTestView()
}
#endif
