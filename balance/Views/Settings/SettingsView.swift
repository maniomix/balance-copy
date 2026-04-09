import SwiftUI
import LocalAuthentication

// MARK: - Settings

struct SettingsView: View {
    @Binding var store: Store
    @AppStorage("app.currency") private var selectedCurrency: String = "EUR"
    @AppStorage("app.theme") private var selectedTheme: String = "light"
    @State private var refreshID = UUID()
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var supabaseManager: SupabaseManager
   
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var appLockManager = AppLockManager.shared
    @State private var showPaywall = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountFinal = false

    
    var body: some View {
        ScrollView {
                VStack(spacing: 14) {

                    // Profile Card
                    NavigationLink {
                        ProfileView(store: $store)
                    } label: {
                        DS.Card {
                            HStack(spacing: 12) {
                                // Avatar
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                DS.Colors.accent,
                                                DS.Colors.accent.opacity(0.8)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text(userInitial)
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(userEmail)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(DS.Colors.text)
                                    
                                    Text("View Profile")
                                        .font(.system(size: 13))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Backup & Data
                    BackupDataSection(store: $store)
                    
                    // App Settings
                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("App Settings")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                            
                            Divider().foregroundStyle(DS.Colors.grid)
                            
                            // Currency
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Currency")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                
                                Picker("Currency", selection: $selectedCurrency) {
                                    Text("EUR (€)").tag("EUR")
                                    Text("USD ($)").tag("USD")
                                    Text("GBP (£)").tag("GBP")
                                    Text("JPY (¥)").tag("JPY")
                                    Text("CAD ($)").tag("CAD")
                                }
                                .pickerStyle(.menu)
                                .tint(DS.Colors.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            
                            Divider().foregroundStyle(DS.Colors.grid)
                            
                            // Theme
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Appearance")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                
                                Picker("Theme", selection: $selectedTheme) {
                                    Text("Dark").tag("dark")
                                    Text("Light").tag("light")
                                }
                                .pickerStyle(.segmented)
                                .padding(4)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            
                            Text("Choose your preferred appearance")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }

                    // Security & Privacy
                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(DS.Colors.accent)

                                Text("Security")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                            }

                            Divider().foregroundStyle(DS.Colors.grid)

                            // App Lock Toggle
                            if appLockManager.isBiometricAvailable {
                                Toggle(isOn: Binding(
                                    get: { appLockManager.isEnabled },
                                    set: { newValue in
                                        appLockManager.isEnabled = newValue
                                        Haptics.selection()
                                    }
                                )) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(DS.Colors.accent.opacity(0.15))
                                                .frame(width: 36, height: 36)

                                            Image(systemName: appLockManager.biometricType == .faceID ? "faceid" : "touchid")
                                                .font(.system(size: 16))
                                                .foregroundStyle(DS.Colors.accent)
                                        }

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("App Lock")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(DS.Colors.text)

                                            Text("Require \(appLockManager.biometricName) to open")
                                                .font(.system(size: 12))
                                                .foregroundStyle(DS.Colors.subtext)
                                        }
                                    }
                                }
                                .tint(DS.Colors.accent)
                            } else {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(DS.Colors.surface2)
                                            .frame(width: 36, height: 36)

                                        Image(systemName: "lock.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("App Lock")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.subtext)

                                        Text("Biometric authentication not available")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                }
                            }
                        }
                    }

                    // Developer Info
                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Developer")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                            
                            Divider().foregroundStyle(DS.Colors.grid)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Developed by")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                    Spacer()
                                    Text("Centmond")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                }
                                
                                HStack {
                                    Text("Version")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                    Spacer()
                                    Text("1.0.0")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                }
                                
                                HStack {
                                    Text("Build")
                                        .font(DS.Typography.caption)
                                        .foregroundStyle(DS.Colors.subtext)
                                    Spacer()
                                    Text("2026.01")
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                }
                            }
                        }
                    }
                    
                    aboutCard
                    
                    // Help & Support
                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "questionmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                
                                Text("Help & Support")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                            }
                            
                            Divider().foregroundStyle(DS.Colors.grid)
                            
                            VStack(spacing: 0) {
                                // Contact Support
                                Button {
                                    if let url = URL(string: "mailto:centmond.support@gmail.com?subject=Centmond%20App%20Support") {
                                        UIApplication.shared.open(url)
                                        Haptics.light()
                                    }
                                } label: {
                                    supportRow(
                                        icon: "envelope.fill",
                                        title: "Contact Support",
                                        subtitle: "centmond.support@gmail.com",
                                        iconColor: 0x4559F5
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Report Bug
                                Button {
                                    if let url = URL(string: "mailto:centmond.support@gmail.com?subject=Bug%20Report%20-%20Centmond%20v1.0.0&body=Device:%20\(UIDevice.current.model)%0AiOS:%20\(UIDevice.current.systemVersion)%0AApp%20Version:%201.0.0%0ABuild:%202026.01%0A%0ADescribe%20the%20issue:%0A") {
                                        UIApplication.shared.open(url)
                                        Haptics.light()
                                    }
                                } label: {
                                    supportRow(
                                        icon: "ladybug.fill",
                                        title: "Report a Bug",
                                        subtitle: "Help us improve",
                                        iconColor: 0xFF3B30
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Feature Request
                                Button {
                                    if let url = URL(string: "mailto:centmond.support@gmail.com?subject=Feature%20Request%20-%20Centmond&body=I%20would%20love%20to%20see:%0A") {
                                        UIApplication.shared.open(url)
                                        Haptics.light()
                                    }
                                } label: {
                                    supportRow(
                                        icon: "lightbulb.fill",
                                        title: "Request Feature",
                                        subtitle: "Share your ideas",
                                        iconColor: 0xFF9F0A
                                    )
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Show Onboarding
                                Button {
                                    Haptics.light()
                                    OnboardingManager.shared.resetOnboarding()
                                    OnboardingManager.shared.startOnboarding()
                                } label: {
                                    supportRow(
                                        icon: "play.circle.fill",
                                        title: "View Tutorial",
                                        subtitle: "Show onboarding again",
                                        iconColor: 0x2ED573
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    
                    // Legal & Licenses
                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(DS.Colors.subtext)
                                
                                Text("Legal")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                            }
                            
                            Divider().foregroundStyle(DS.Colors.grid)
                            
                            VStack(spacing: 0) {
                                // Privacy Policy
                                NavigationLink {
                                    PrivacyPolicyView()
                                } label: {
                                    legalRow(icon: "hand.raised.fill", title: "Privacy Policy")
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Terms of Service
                                NavigationLink {
                                    TermsOfServiceView()
                                } label: {
                                    legalRow(icon: "doc.plaintext.fill", title: "Terms of Service")
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Open Source Licenses
                                NavigationLink {
                                    LicensesView()
                                } label: {
                                    legalRow(icon: "books.vertical.fill", title: "Open Source Licenses")
                                }
                                .buttonStyle(.plain)
                            }
                            
                            Divider().foregroundStyle(DS.Colors.grid)
                            
                            // Copyright Footer
                            VStack(spacing: 6) {
                                Text("© 2026 Centmond")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Colors.text)
                                
                                Text("All rights reserved")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                        }
                    }
                    
                    // Danger Zone
                    DS.Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(DS.Colors.danger)

                                Text("Danger Zone")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.danger)
                            }

                            Divider().foregroundStyle(DS.Colors.grid)

                            Button(role: .destructive) {
                                Haptics.warning()
                                showDeleteAccountConfirm = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(DS.Colors.danger.opacity(0.15))
                                            .frame(width: 36, height: 36)

                                        Image(systemName: "person.crop.circle.badge.minus")
                                            .font(.system(size: 16))
                                            .foregroundStyle(DS.Colors.danger)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Delete Account")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.danger)

                                        Text("Permanently remove all your data")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Settings")
            .id(refreshID)
            .sheet(isPresented: $showPaywall) {
                // Paywall removed
                EmptyView()
            }
            // Step 1: "Are you sure?"
            .alert("Delete Account?", isPresented: $showDeleteAccountConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    showDeleteAccountFinal = true
                }
            } message: {
                Text("This will permanently delete your account and all associated data. This action cannot be undone.")
            }
            // Step 2: Final confirmation
            .alert("This is irreversible", isPresented: $showDeleteAccountFinal) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    // TODO: Implement actual account deletion once the new
                    // database is in place. This should:
                    // 1. Delete all user data from Supabase (transactions,
                    //    budgets, categories, recurring, user profile row)
                    // 2. Call supabase.client.auth.admin.deleteUser or an
                    //    RPC that handles cascade deletion server-side
                    // 3. Clear local UserDefaults + keychain
                    // 4. Sign out and reset to launch screen
                    SecureLogger.info("Delete account requested — not yet implemented (database migration pending)")
                    Haptics.error()
                }
            } message: {
                Text("Are you absolutely sure? All transactions, budgets, goals, and account data will be permanently erased.")
            }
    }

    private var userEmail: String {
        authManager.userEmail
    }
    
    private var userInitial: String {
        authManager.userInitial
    }
    
    // Helper for support rows
    private func supportRow(icon: String, title: String, subtitle: String, iconColor: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hexValue: UInt32(iconColor)).opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hexValue: UInt32(iconColor)))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Colors.text)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
            }
            
            Spacer()
            
            Image(systemName: "arrow.up.right")
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.vertical, 8)
    }
    
    // Helper for legal rows
    private func legalRow(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(DS.Colors.surface2)
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Colors.text)
            }
            
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Colors.text)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.vertical, 8)
    }

    private var aboutCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DS.Colors.text)
                    
                    Text("About")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                }
                
                Divider().foregroundStyle(DS.Colors.grid)
                
                // App Info
                VStack(alignment: .leading, spacing: 6) {
                    Text("Centmond")
                        .font(.custom("Pacifico-Regular", size: 20))
                        .foregroundStyle(DS.Colors.text)
                    
                    Text("Personal Finance Manager")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.Colors.subtext)
                    
                    Text("v1.0.0 (2026.01)")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.subtext.opacity(0.7))
                }
                
                Divider().foregroundStyle(DS.Colors.grid)
                
                // Features
                VStack(spacing: 0) {
                    aboutRow(
                        icon: "lock.shield.fill",
                        title: "Privacy First",
                        subtitle: "Your data stays on your device",
                        iconColor: 0x2ED573
                    )
                    
                    Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                    
                    aboutRow(
                        icon: "chart.xyaxis.line",
                        title: "Smart Insights",
                        subtitle: "AI-powered financial analysis",
                        iconColor: 0x4559F5
                    )
                    
                    Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                    
                    aboutRow(
                        icon: "icloud.fill",
                        title: "Cloud Sync",
                        subtitle: "Seamless across all devices",
                        iconColor: 0x3498DB
                    )
                    
                    Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                    
                    aboutRow(
                        icon: "arrow.down.doc.fill",
                        title: "Import & Export",
                        subtitle: "CSV, Excel, and more",
                        iconColor: 0xFF9F0A
                    )
                }
                
                Divider().foregroundStyle(DS.Colors.grid)
                
                // Copyright
                VStack(spacing: 6) {
                    Text("Developed by Mani")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.text)
                    
                    Text("Made with ❤️ for financial freedom")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
        }
    }
    
    // Helper for about rows
    private func aboutRow(icon: String, title: String, subtitle: String, iconColor: Int) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hexValue: UInt32(iconColor)).opacity(0.15))
                    .frame(width: 36, height: 36)
                
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hexValue: UInt32(iconColor)))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Colors.text)
                
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
}
