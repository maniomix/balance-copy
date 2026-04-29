import SwiftUI
import LocalAuthentication
import UniformTypeIdentifiers
import Supabase

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
    @StateObject private var accountManager = AccountManager.shared
    @State private var showPaywall = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountFinal = false
    @State private var showSignOutConfirm = false
    @State private var showCurrencyPicker = false
    @State private var showPrivacyDetails = false
    @State private var showContactSheet = false
    @State private var showNotificationsSettings = false
    @AppStorage("notifications.enabled") private var notificationsEnabled: Bool = false
    @State private var showBackTapSetup = false
    @AppStorage("backTap.quickAdd.enabled") private var backTapQuickAddEnabled: Bool = false
    @State private var showDynamicIslandSetup = false
    @AppStorage("dynamicIsland.enabled") private var dynamicIslandEnabled: Bool = true

    
    var body: some View {
        ScrollView {
                VStack(spacing: 14) {

                    // Profile hero
                    NavigationLink {
                        ProfileView(store: $store)
                    } label: {
                        DS.Card {
                            VStack(spacing: 14) {
                                HStack(spacing: 14) {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    DS.Colors.accent,
                                                    DS.Colors.accent.opacity(0.75)
                                                ],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 60, height: 60)
                                        .overlay(
                                            Text(userInitial)
                                                .font(.system(size: 24, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(userEmail)
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(DS.Colors.text)
                                            .lineLimit(1)

                                        HStack(spacing: 6) {
                                            Text("PRO")
                                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 3)
                                                .background(
                                                    Capsule().fill(DS.Colors.accent)
                                                )
                                                .accessibilityLabel("Pro account")

                                            Text("View profile")
                                                .font(.system(size: 12))
                                                .foregroundStyle(DS.Colors.subtext)
                                        }
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundStyle(DS.Colors.subtext)
                                }

                                Divider().foregroundStyle(DS.Colors.grid)

                                HStack(spacing: 0) {
                                    profileStat(value: "\(accountManager.accounts.count)", label: "Accounts")
                                    profileStatDivider
                                    profileStat(value: "\(store.transactions.count)", label: "Transactions")
                                    profileStatDivider
                                    profileStat(value: memberSinceShort, label: "Member since")
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Pro account for \(userEmail). \(accountManager.accounts.count) accounts, \(store.transactions.count) transactions, member since \(memberSinceShort).")
                    .accessibilityHint("Opens your profile")

                    // Backup & Data
                    BackupDataSection(store: $store)
                    
                    // Preferences
                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Preferences")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)

                            Divider().foregroundStyle(DS.Colors.grid)

                            // Currency → searchable sheet
                            Button {
                                Haptics.light()
                                showCurrencyPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Currency")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                        Text("Used across budgets, accounts, and transactions")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text(CurrencyOption.lookup(selectedCurrency).symbol)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(DS.Colors.accent)
                                        Text(selectedCurrency)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(DS.Colors.text)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Currency, currently \(CurrencyOption.lookup(selectedCurrency).name)")
                            .accessibilityHint("Opens the currency picker")

                            Divider().foregroundStyle(DS.Colors.grid)

                            // Appearance — 3-segment
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Appearance")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(DS.Colors.text)

                                Picker("Theme", selection: $selectedTheme) {
                                    Text("System").tag("system")
                                    Text("Light").tag("light")
                                    Text("Dark").tag("dark")
                                }
                                .pickerStyle(.segmented)
                                .padding(4)
                                .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }

                            Divider().foregroundStyle(DS.Colors.grid)

                            // Language (follows device for now)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Language")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DS.Colors.text)
                                    Text("Follows your device language")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                Spacer()
                                Text(deviceLanguageName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            .padding(.vertical, 4)

                            Divider().foregroundStyle(DS.Colors.grid)

                            // Notifications → dedicated sheet
                            Button {
                                Haptics.light()
                                showNotificationsSettings = true
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Notifications")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                        Text(notificationsEnabled ? "On · alerts active" : "Off")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Notifications, \(notificationsEnabled ? "on" : "off")")
                            .accessibilityHint("Opens notification settings")

                            Divider().foregroundStyle(DS.Colors.grid)

                            // Categories → manager
                            NavigationLink {
                                CategoriesSettingsView(store: $store)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Categories")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                        Text(categoriesSubtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Categories, \(store.customCategoriesWithIcons.count) custom")
                            .accessibilityHint("Opens category manager")
                        }
                    }

                    // Quick Add (Back Tap)
                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(DS.Colors.accent.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(DS.Colors.accent)
                                }
                                Text("Quick Add (Back Tap)")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                                Spacer()
                                DS.BetaBadge()
                            }

                            Text("Double tap the back of your iPhone to log a transaction in seconds — without opening Centmond.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider().foregroundStyle(DS.Colors.grid)

                            Toggle(isOn: Binding(
                                get: { backTapQuickAddEnabled },
                                set: { newValue in
                                    backTapQuickAddEnabled = newValue
                                    Haptics.selection()
                                    if newValue { showBackTapSetup = true }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Enable Quick Add")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DS.Colors.text)
                                    Text(backTapQuickAddEnabled ? "On · ready for Back Tap" : "Off")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                            .tint(DS.Colors.accent)
                            .accessibilityHint("Allows the Back Tap shortcut to add transactions without opening the app")

                            Divider().foregroundStyle(DS.Colors.grid)

                            Button {
                                Haptics.light()
                                showBackTapSetup = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(DS.Colors.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Setup Guide")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                        Text("Walk through enabling and using Back Tap")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Back Tap setup guide")
                            .accessibilityHint("Opens step-by-step instructions for enabling and using Back Tap")
                        }
                    }

                    // Dynamic Island
                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(DS.Colors.accent.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "capsule.portrait.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(DS.Colors.accent)
                                }
                                Text("Dynamic Island")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                                Spacer()
                                DS.BetaBadge()
                            }

                            Text("See your budget at a glance on your iPhone's Dynamic Island while Centmond is in the background. Tap Next to swipe through Budget, Today, This Week, and Top Category.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider().foregroundStyle(DS.Colors.grid)

                            Toggle(isOn: Binding(
                                get: { dynamicIslandEnabled },
                                set: { newValue in
                                    dynamicIslandEnabled = newValue
                                    Haptics.selection()
                                    if !newValue {
                                        BudgetLiveActivityManager.shared.endAll()
                                    }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Show on background")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DS.Colors.text)
                                    Text(dynamicIslandEnabled ? "On · appears when app is backgrounded" : "Off")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                            .tint(DS.Colors.accent)
                            .accessibilityHint("Shows the budget Live Activity on the Dynamic Island and lock screen when Centmond is backgrounded")

                            Divider().foregroundStyle(DS.Colors.grid)

                            Button {
                                Haptics.light()
                                showDynamicIslandSetup = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(DS.Colors.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Setup Guide")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                        Text("Requirements, what's shown, and how to navigate")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Dynamic Island setup guide")
                            .accessibilityHint("Opens a guide explaining what the Dynamic Island shows and how to use it")
                        }
                    }

                    // Security & Privacy
                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(DS.Colors.accent)

                                Text("Security & Privacy")
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
                                        .accessibilityHidden(true)

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
                                .accessibilityLabel("App Lock")
                                .accessibilityHint("Requires \(appLockManager.biometricName) to open the app")
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

                            Divider().foregroundStyle(DS.Colors.grid)

                            // Privacy snapshot
                            Button {
                                Haptics.light()
                                showPrivacyDetails = true
                            } label: {
                                HStack(spacing: 12) {
                                    ZStack {
                                        Circle()
                                            .fill(DS.Colors.positive.opacity(0.15))
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "hand.raised.fill")
                                            .font(.system(size: 16))
                                            .foregroundStyle(DS.Colors.positive)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Privacy")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Colors.text)
                                        Text("See what's stored, synced, and kept on-device")
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(2)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Privacy details")
                            .accessibilityHint("Shows what data is stored, synced, and kept on-device")
                        }
                    }

                    // Centmond AI hub (drill-down)
                    NavigationLink {
                        AISettingsView(store: $store)
                    } label: {
                        DS.Card {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(DS.Colors.accent.opacity(0.15))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(DS.Colors.accent)
                                }

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text("Centmond AI")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(DS.Colors.text)
                                        DS.BetaBadge()
                                    }
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(AIManager.shared.status == .ready ? DS.Colors.positive : DS.Colors.warning)
                                            .frame(width: 6, height: 6)
                                        Text(aiModelStatusText)
                                            .font(.system(size: 12))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Centmond AI, \(aiModelStatusText)")
                    .accessibilityHint("Opens AI model, notifications, and permissions")

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
                                // Contact us (unified sheet)
                                Button {
                                    Haptics.light()
                                    showContactSheet = true
                                } label: {
                                    settingsRow(
                                        icon: "envelope.fill",
                                        title: "Contact us",
                                        subtitle: "Question, bug report, or feature idea",
                                        iconColor: 0x4559F5,
                                        accessory: .chevron
                                    )
                                }
                                .buttonStyle(.plain)

                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)

                                // Replay onboarding
                                Button {
                                    Haptics.light()
                                    OnboardingManager.shared.resetOnboarding()
                                    OnboardingManager.shared.startOnboarding()
                                } label: {
                                    settingsRow(
                                        icon: "play.circle.fill",
                                        title: "View Tutorial",
                                        subtitle: "Show onboarding again",
                                        iconColor: 0x2ED573,
                                        accessory: .chevron
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
                                    settingsRow(icon: "hand.raised.fill", title: "Privacy Policy", accessory: .chevron)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Terms of Service
                                NavigationLink {
                                    TermsOfServiceView()
                                } label: {
                                    settingsRow(icon: "doc.plaintext.fill", title: "Terms of Service", accessory: .chevron)
                                }
                                .buttonStyle(.plain)
                                
                                Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                                
                                // Open Source Licenses
                                NavigationLink {
                                    LicensesView()
                                } label: {
                                    settingsRow(icon: "books.vertical.fill", title: "Open Source Licenses", accessory: .chevron)
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
                    
                    // Account
                    DS.Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(DS.Colors.subtext)

                                Text("Account")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                            }

                            Divider().foregroundStyle(DS.Colors.grid)

                            Button {
                                Haptics.light()
                                showSignOutConfirm = true
                            } label: {
                                settingsRow(
                                    icon: "rectangle.portrait.and.arrow.right",
                                    title: "Sign Out",
                                    subtitle: userEmail,
                                    iconColor: 0x8E8E93,
                                    accessory: .chevron
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Sign out, \(userEmail)")
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
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Delete Account")
                            .accessibilityHint("Permanently removes your account and all your data")
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SectionHelpButton(screen: .settings)
                }
            }
            .id(refreshID)
            .sheet(isPresented: $showPaywall) {
                // Paywall removed
                EmptyView()
            }
            .sheet(isPresented: $showCurrencyPicker) {
                CurrencyPickerSheet(selection: $selectedCurrency)
            }
            .sheet(isPresented: $showPrivacyDetails) {
                PrivacySnapshotSheet()
            }
            .sheet(isPresented: $showContactSheet) {
                ContactSupportSheet()
            }
            .sheet(isPresented: $showNotificationsSettings) {
                NotificationsSettingsView(store: $store)
            }
            .sheet(isPresented: $showBackTapSetup) {
                BackTapSetupSheet()
            }
            .sheet(isPresented: $showDynamicIslandSetup) {
                DynamicIslandSetupSheet()
            }
            .alert("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task {
                        do {
                            if let userId = authManager.currentUser?.uid {
                                let currentStore = Store.load(userId: userId)
                                _ = await SyncCoordinator.shared.pushToCloud(store: currentStore, userId: userId)
                            }
                            try authManager.signOut()
                        } catch {
                            SecureLogger.error("Sign out failed", error)
                        }
                    }
                }
            } message: {
                Text("Your data stays synced. You can sign back in at any time.")
            }
            // Step 1: "Are you sure?"
            .alert("Delete your account?", isPresented: $showDeleteAccountConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Continue", role: .destructive) {
                    showDeleteAccountFinal = true
                }
            } message: {
                Text("We'll remove your transactions, budgets, goals, accounts, and profile from the cloud. You'll be signed out and can't recover this data.")
            }
            // Step 2: Final confirmation
            .alert("Last check", isPresented: $showDeleteAccountFinal) {
                Button("Keep my account", role: .cancel) {}
                Button("Delete everything", role: .destructive) {
                    Task { await performAccountDeletion() }
                }
            } message: {
                Text("This can't be undone. Tap Delete everything to confirm.")
            }
    }

    /// Calls the `delete_account()` RPC which deletes auth.users → cascades
    /// every owner_id-keyed table → wipes the user from the cloud entirely.
    /// Then clears local caches and signs out.
    private func performAccountDeletion() async {
        Haptics.warning()
        SecureLogger.info("Deleting account…")
        do {
            try await supabaseManager.client.rpc("delete_account").execute()
            SecureLogger.info("Cloud data wiped via delete_account RPC")
        } catch {
            SecureLogger.error("delete_account RPC failed", error)
            Haptics.error()
            return
        }

        // Wipe local caches that survive sign-out (UserDefaults blobs).
        AuthManager.wipeLocalUserData()

        // Force sign-out to bounce the UI back to the auth screen.
        do { try authManager.signOut() }
        catch { SecureLogger.error("Sign-out after delete failed", error) }

        Haptics.success()
    }

    private var userEmail: String {
        authManager.userEmail
    }
    
    private var userInitial: String {
        authManager.userInitial
    }

    private var memberSinceShort: String {
        guard let createdAt = authManager.currentUser?.createdAt else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MMM yyyy"
        return f.string(from: createdAt)
    }

    @ViewBuilder
    private func profileStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private var profileStatDivider: some View {
        Rectangle()
            .fill(DS.Colors.grid)
            .frame(width: 1, height: 28)
            .accessibilityHidden(true)
    }

    private var categoriesSubtitle: String {
        let count = store.customCategoriesWithIcons.count
        if count == 0 { return "Add custom categories with icon & color" }
        if count == 1 { return "1 custom category" }
        return "\(count) custom categories"
    }

    private var deviceLanguageName: String {
        let code = Locale.preferredLanguages.first ?? Locale.current.identifier
        let locale = Locale.current
        return locale.localizedString(forLanguageCode: String(code.prefix(2)))?.capitalized ?? "English"
    }

    private var appVersionLabel: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    private var aiModelStatusText: String {
        switch AIManager.shared.status {
        case .notLoaded: return AIManager.shared.isModelDownloaded ? "Not Loaded" : "Not Downloaded"
        case .loading: return "Loading..."
        case .ready: return "Gemma 4 Ready"
        case .error(let msg): return "Error: \(msg)"
        case .generating: return "Generating..."
        case .downloading(let p, _): return "Downloading \(Int(p * 100))%"
        }
    }

    // MARK: - Unified Row Helper

    enum SettingsRowAccessory {
        case chevron
        case externalLink
        case none
    }

    @ViewBuilder
    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        iconColor: Int? = nil,
        accessory: SettingsRowAccessory = .none
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconColor.map { Color(hexValue: UInt32($0)).opacity(0.15) } ?? DS.Colors.surface2)
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor.map { Color(hexValue: UInt32($0)) } ?? DS.Colors.text)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Colors.text)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }

            Spacer()

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
            case .externalLink:
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
            case .none:
                EmptyView()
            }
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
                    
                    Text(appVersionLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.subtext.opacity(0.7))
                }
                
                Divider().foregroundStyle(DS.Colors.grid)
                
                // Features
                VStack(spacing: 0) {
                    settingsRow(
                        icon: "lock.shield.fill",
                        title: "Privacy First",
                        subtitle: "Your data stays on your device",
                        iconColor: 0x2ED573
                    )
                    
                    Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                    
                    settingsRow(
                        icon: "chart.xyaxis.line",
                        title: "Smart Insights",
                        subtitle: "AI-powered financial analysis",
                        iconColor: 0x4559F5
                    )
                    
                    Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                    
                    settingsRow(
                        icon: "icloud.fill",
                        title: "Cloud Sync",
                        subtitle: "Seamless across all devices",
                        iconColor: 0x3498DB
                    )
                    
                    Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
                    
                    settingsRow(
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
    
}

// MARK: - Centmond AI Settings

struct AISettingsView: View {
    @Binding var store: Store
    @StateObject private var trustManager = AITrustManager.shared
    @State private var showAIActivity = false
    @State private var showDownloadConfirm = false
    @State private var showModelImporter = false
    @State private var showModelInfo = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                modelCard
                notificationsCard
                permissionsCard
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .navigationTitle("Centmond AI")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAIActivity) {
            AIActivityDashboard(store: $store)
        }
        .alert("About AI Model", isPresented: $showModelInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Balance uses Gemma 4 E2B, a compact on-device AI model (~3 GB). All processing happens locally on your device — your financial data never leaves your phone.\n\nFor a more powerful AI experience with larger models, try Balance on macOS.")
        }
        .alert("Download AI Model?", isPresented: $showDownloadConfirm) {
            Button("Download (\(AIManager.modelDownloadSizeLabel))", role: .none) {
                AIManager.shared.downloadModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will download the AI model (\(AIManager.modelDownloadSizeLabel)). Make sure you're connected to Wi-Fi.")
        }
        .fileImporter(
            isPresented: $showModelImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                guard url.lastPathComponent.hasSuffix(".gguf") else { return }
                Task {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    do {
                        try AIManager.shared.importModel(from: url)
                        AIManager.shared.loadModel()
                    } catch {
                        SecureLogger.error("Model import failed: \(error)")
                    }
                }
            case .failure(let error):
                SecureLogger.error("File picker failed: \(error)")
            }
        }
    }

    // MARK: Cards

    private var modelCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Text("AI Model")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)

                    Spacer()

                    HStack(spacing: 5) {
                        Circle()
                            .fill(AIManager.shared.status == .ready ? DS.Colors.positive : DS.Colors.warning)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(aiModelStatusText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.text)
                        if let size = AIManager.shared.modelFileSize {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(DS.Colors.subtext)
                                .accessibilityHidden(true)
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((AIManager.shared.status == .ready ? DS.Colors.positive : DS.Colors.warning).opacity(0.1))
                    )
                    .accessibilityElement(children: .combine)

                    Button {
                        showModelInfo = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .accessibilityLabel("About this AI model")
                }

                aiModelButtons
            }
        }
    }

    private var notificationsCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Text("AI Notifications")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                }

                Toggle(isOn: Binding(
                    get: { AIInsightEngine.shared.isMorningNotificationEnabled },
                    set: { AIInsightEngine.shared.isMorningNotificationEnabled = $0 }
                )) {
                    Label("Morning Briefing (8 AM)", systemImage: "sunrise.fill")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.text)
                }
                .tint(DS.Colors.accent)

                Toggle(isOn: Binding(
                    get: { AIInsightEngine.shared.isWeeklyReviewEnabled },
                    set: { AIInsightEngine.shared.isWeeklyReviewEnabled = $0 }
                )) {
                    Label("Weekly Review (Sun 7 PM)", systemImage: "calendar.badge.clock")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.text)
                }
                .tint(DS.Colors.accent)

                Divider().foregroundStyle(DS.Colors.grid)

                Button {
                    showAIActivity = true
                } label: {
                    HStack {
                        Label("AI Activity Dashboard", systemImage: "clock.arrow.circlepath")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    private var permissionsCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                    Text("AI Permissions")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                }

                Text("Decide what the AI can do on its own, and what it should always check with you first.")
                    .font(.footnote)
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                trustSectionHeader(
                    title: "Runs without asking",
                    subtitle: "Small, safe tweaks the AI can apply instantly.",
                    icon: "bolt.fill",
                    tint: DS.Colors.positive
                )
                trustPreferenceToggle(
                    "Auto-categorize transactions",
                    description: "Pick a category when you add a new transaction.",
                    icon: "tag.fill",
                    binding: trustPrefBinding(\.allowAutoCategorizaton)
                )
                trustPreferenceToggle(
                    "Auto-tag notes & labels",
                    description: "Fill in tags and notes based on the merchant or amount.",
                    icon: "text.badge.checkmark",
                    binding: trustPrefBinding(\.allowAutoTagging)
                )
                trustPreferenceToggle(
                    "Clean up merchant names",
                    description: "Rewrite noisy bank strings like “SQ* NETFLIX 12345” into “Netflix”.",
                    icon: "sparkles",
                    binding: trustPrefBinding(\.allowAutoMerchantCleanup)
                )

                trustSectionHeader(
                    title: "Always asks first",
                    subtitle: "Bigger changes the AI only does after you tap to confirm.",
                    icon: "hand.raised.fill",
                    tint: DS.Colors.warning
                )
                trustPreferenceToggle(
                    "Budget changes",
                    description: "Raising, lowering, or moving budget amounts between categories.",
                    icon: "chart.pie.fill",
                    binding: trustPrefBinding(\.requireConfirmBudgetChanges)
                )
                trustPreferenceToggle(
                    "Recurring setup",
                    description: "Creating or editing a repeating bill, salary, or subscription.",
                    icon: "repeat",
                    binding: trustPrefBinding(\.requireConfirmRecurringSetup)
                )
                trustPreferenceToggle(
                    "Goal changes",
                    description: "Adding to a goal, changing its target, or marking it complete.",
                    icon: "target",
                    binding: trustPrefBinding(\.requireConfirmGoalChanges)
                )

                trustSectionHeader(
                    title: "Never allowed",
                    subtitle: "Safety rails the AI will always respect — even in autopilot modes.",
                    icon: "lock.shield.fill",
                    tint: DS.Colors.danger
                )
                trustPreferenceToggle(
                    "Block destructive actions",
                    description: "Never let the AI delete transactions, budgets, or goals on its own.",
                    icon: "xmark.shield.fill",
                    binding: trustPrefBinding(\.neverAutoDestructive)
                )
                trustPreferenceToggle(
                    "Block large auto-amounts",
                    description: "Anything over a high-value threshold always waits for your approval.",
                    icon: "dollarsign.circle.fill",
                    binding: trustPrefBinding(\.neverAutoLargeAmounts)
                )
            }
        }
    }

    // MARK: Model buttons

    @ViewBuilder
    private var aiModelButtons: some View {
        if case .downloading(let progress, let bytes) = AIManager.shared.status {
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .tint(DS.Colors.accent)
                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) / \(AIManager.modelDownloadSizeLabel) · \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(DS.Colors.subtext)
                        .contentTransition(.numericText())
                    Spacer()
                    Button("Cancel") { AIManager.shared.cancelDownload() }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.danger)
                }
            }
        } else if !AIManager.shared.isModelDownloaded {
            VStack(spacing: 8) {
                Button {
                    showDownloadConfirm = true
                } label: {
                    Label("Download Model (\(AIManager.modelDownloadSizeLabel))", systemImage: "arrow.down.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                Button {
                    showModelImporter = true
                } label: {
                    Label("Import from Files", systemImage: "folder.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Colors.accent.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        } else {
            VStack(spacing: 8) {
                if AIManager.shared.status != .ready {
                    Button {
                        AIManager.shared.loadModel()
                    } label: {
                        Label("Load Model", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .disabled(AIManager.shared.status == .loading)
                }
                Button {
                    AIManager.shared.deleteModel()
                } label: {
                    Label("Delete Model", systemImage: "trash")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DS.Colors.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    // MARK: Trust helpers

    @ViewBuilder
    private func trustPreferenceToggle(
        _ title: String,
        description: String? = nil,
        icon: String,
        binding: Binding<Bool>
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 22, height: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)
                if let description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: binding)
                .tint(DS.Colors.accent)
                .labelsHidden()
                .padding(.top, 2)
                .accessibilityLabel(title)
                .accessibilityHint(description ?? "")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func trustSectionHeader(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
            }
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    private func trustPrefBinding(_ keyPath: WritableKeyPath<AIUserTrustPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { trustManager.preferences[keyPath: keyPath] },
            set: { trustManager.preferences[keyPath: keyPath] = $0 }
        )
    }

    private var aiModelStatusText: String {
        switch AIManager.shared.status {
        case .notLoaded: return AIManager.shared.isModelDownloaded ? "Not Loaded" : "Not Downloaded"
        case .loading: return "Loading..."
        case .ready: return "Gemma 4 Ready"
        case .error(let msg): return "Error: \(msg)"
        case .generating: return "Generating..."
        case .downloading(let p, _): return "Downloading \(Int(p * 100))%"
        }
    }
}

// MARK: - Currency Picker

struct CurrencyOption: Identifiable, Hashable {
    let code: String
    let symbol: String
    let name: String
    var id: String { code }

    // Keep in sync with `CurrencyFormatter.SupportedCurrency`.
    // Anything listed here must also exist there, or formatting falls back to EUR.
    static let all: [CurrencyOption] = [
        .init(code: "USD", symbol: "$",    name: "US Dollar"),
        .init(code: "EUR", symbol: "€",    name: "Euro"),
        .init(code: "GBP", symbol: "£",    name: "British Pound"),
        .init(code: "JPY", symbol: "¥",    name: "Japanese Yen"),
        .init(code: "CAD", symbol: "$",    name: "Canadian Dollar"),
        .init(code: "AUD", symbol: "$",    name: "Australian Dollar"),
        .init(code: "CHF", symbol: "CHF",  name: "Swiss Franc"),
        .init(code: "CNY", symbol: "¥",    name: "Chinese Yuan"),
        .init(code: "INR", symbol: "₹",    name: "Indian Rupee"),
        .init(code: "KRW", symbol: "₩",    name: "South Korean Won"),
        .init(code: "SEK", symbol: "kr",   name: "Swedish Krona"),
        .init(code: "NOK", symbol: "kr",   name: "Norwegian Krone"),
        .init(code: "DKK", symbol: "kr",   name: "Danish Krone"),
        .init(code: "NZD", symbol: "$",    name: "New Zealand Dollar"),
        .init(code: "SGD", symbol: "$",    name: "Singapore Dollar"),
        .init(code: "HKD", symbol: "$",    name: "Hong Kong Dollar"),
        .init(code: "MXN", symbol: "$",    name: "Mexican Peso"),
        .init(code: "BRL", symbol: "R$",   name: "Brazilian Real"),
        .init(code: "ZAR", symbol: "R",    name: "South African Rand"),
        .init(code: "TRY", symbol: "₺",    name: "Turkish Lira"),
        .init(code: "RUB", symbol: "₽",    name: "Russian Ruble"),
        .init(code: "AED", symbol: "د.إ",  name: "UAE Dirham"),
        .init(code: "SAR", symbol: "﷼",    name: "Saudi Riyal"),
        .init(code: "IRR", symbol: "﷼",    name: "Iranian Rial"),
        .init(code: "PLN", symbol: "zł",   name: "Polish Złoty"),
    ]

    static func lookup(_ code: String) -> CurrencyOption {
        all.first(where: { $0.code == code }) ?? all[0]
    }
}

struct CurrencyPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [CurrencyOption] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return CurrencyOption.all }
        return CurrencyOption.all.filter {
            $0.code.lowercased().contains(q) || $0.name.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { opt in
                    Button {
                        selection = opt.code
                        Haptics.selection()
                        dismiss()
                    } label: {
                        HStack(spacing: 14) {
                            Text(opt.symbol)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DS.Colors.accent)
                                .frame(width: 32, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(opt.code)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DS.Colors.text)
                                Text(opt.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(DS.Colors.subtext)
                            }

                            Spacer()

                            if opt.code == selection {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search currencies")
            .navigationTitle("Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Privacy Snapshot

struct PrivacySnapshotSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "hand.raised.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(DS.Colors.positive)
                                Text("Your data, your rules")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                            }

                            Text("Here's exactly where each kind of data lives and what happens to it. No ads. No tracking. No sale of personal data.")
                                .font(.system(size: 13))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            privacySectionHeader("Stays on your device", tint: DS.Colors.positive, icon: "iphone")
                            privacyBullet("Conversations with Centmond AI (Gemma runs locally; no chats leave your phone).")
                            privacyBullet("Biometric unlock — Face ID / Touch ID credentials never leave the Secure Enclave.")
                            privacyBullet("AI learning data (merchant tags, approval patterns) stored only in app memory.")
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            privacySectionHeader("Synced to your Centmond cloud", tint: DS.Colors.accent, icon: "icloud.fill")
                            privacyBullet("Transactions, accounts, budgets, goals, and recurring items — encrypted in transit.")
                            privacyBullet("User profile (email, display name, avatar).")
                            privacyBullet("Only you can read your data with your credentials.")
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            privacySectionHeader("Never collected", tint: DS.Colors.danger, icon: "nosign")
                            privacyBullet("No advertising identifiers, no third-party ad SDKs.")
                            privacyBullet("No contact list, photos, or location access.")
                            privacyBullet("No sale or sharing of personal data, ever.")
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your rights")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                            Text("Export all your data from Settings → Backup & Data. Delete your account to permanently erase every record from the cloud.")
                                .font(.system(size: 13))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                            NavigationLink {
                                PrivacyPolicyView()
                            } label: {
                                HStack {
                                    Text("Read the full Privacy Policy")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DS.Colors.accent)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Colors.accent)
                                }
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
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func privacySectionHeader(_ title: String, tint: Color, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
        }
    }

    @ViewBuilder
    private func privacyBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(DS.Colors.subtext)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Contact Support

struct ContactSupportSheet: View {
    @Environment(\.dismiss) private var dismiss

    enum Topic: String, CaseIterable, Identifiable {
        case support = "Support"
        case bug     = "Bug"
        case feature = "Feature"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .support: return "questionmark.circle.fill"
            case .bug:     return "ladybug.fill"
            case .feature: return "lightbulb.fill"
            }
        }

        var tint: Color {
            switch self {
            case .support: return DS.Colors.accent
            case .bug:     return DS.Colors.danger
            case .feature: return DS.Colors.warning
            }
        }

        var placeholder: String {
            switch self {
            case .support: return "What do you need help with?"
            case .bug:     return "What went wrong? What were you doing at the time?"
            case .feature: return "What would you like to see?"
            }
        }

        fileprivate var subjectPrefix: String {
            switch self {
            case .support: return "Centmond App Support"
            case .bug:     return "Bug Report - Centmond"
            case .feature: return "Feature Request - Centmond"
            }
        }
    }

    @State private var topic: Topic = .support
    @State private var message: String = ""

    private let recipient = "centmond.support@gmail.com"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var attachedMetadata: String {
        """
        --
        Device: \(UIDevice.current.model)
        iOS: \(UIDevice.current.systemVersion)
        App: \(appVersion) (\(appBuild))
        """
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("What's this about?")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)

                            Picker("Topic", selection: $topic) {
                                ForEach(Topic.allCases) { t in
                                    Text(t.rawValue).tag(t)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(4)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(topic.tint.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: topic.icon)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(topic.tint)
                                }
                                .accessibilityHidden(true)
                                Text("Your message")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                            }

                            ZStack(alignment: .topLeading) {
                                if message.isEmpty {
                                    Text(topic.placeholder)
                                        .font(.system(size: 14))
                                        .foregroundStyle(DS.Colors.subtext.opacity(0.7))
                                        .padding(.horizontal, 12)
                                        .padding(.top, 12)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                                TextEditor(text: $message)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Colors.text)
                                    .scrollContentBackground(.hidden)
                                    .padding(8)
                                    .frame(minHeight: 140)
                                    .accessibilityLabel("Message")
                                    .accessibilityHint(topic.placeholder)
                            }
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if topic == .bug {
                        DS.Card {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Image(systemName: "info.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DS.Colors.subtext)
                                    Text("We'll include this to help diagnose")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                                Text(attachedMetadata)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    Button {
                        openMail()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                            Text("Open in Mail")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            (canSend ? DS.Colors.accent : DS.Colors.accent.opacity(0.4)),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                    }
                    .disabled(!canSend)

                    Text("We reply from \(recipient).")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Colors.subtext)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Contact us")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func openMail() {
        let body: String
        switch topic {
        case .bug:
            body = "\(message)\n\n\(attachedMetadata)"
        default:
            body = message
        }

        let subject = "\(topic.subjectPrefix) v\(appVersion)"

        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = recipient
        comps.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]

        if let url = comps.url {
            UIApplication.shared.open(url)
            Haptics.light()
            dismiss()
        }
    }
}


