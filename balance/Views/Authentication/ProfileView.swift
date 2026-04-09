import SwiftUI
import PhotosUI
import Supabase
// TEST COMMENT - Claude edit works ✅
struct ProfileView: View {
    @Binding var store: Store
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    @State private var selectedImage: PhotosPickerItem?
    @State private var profileImage: Image?
    @State private var profileImageData: Data?
    @State private var showEditName = false
    @State private var displayName = ""
    @State private var isSaving = false
    
    private var user: Supabase.User? {
        authManager.currentUser
    }
    
    private var userEmail: String {
        user?.email ?? "No email"
    }
    
    private var memberSince: String {
        guard let createdAt = user?.createdAt else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: createdAt)
    }
    
    private var totalTransactions: Int {
        store.transactions.count
    }
    
    private var totalSpentAllTime: Int {
        store.transactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    
    private var totalIncomeAllTime: Int {
        store.transactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    statsRow
                    subscriptionCard
                    accountInfoSection
                    actionsSection
                    signOutButton

                    Spacer(minLength: 30)
                }
                .padding()
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadProfile()
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                if let profileImage {
                    profileImage
                        .resizable()
                        .scaledToFill()
                        .frame(width: 90, height: 90)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.15), .white.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ), lineWidth: 1
                            )
                        )
                } else {
                    Circle()
                        .fill(DS.Colors.surface)
                        .frame(width: 90, height: 90)
                        .overlay(
                            Text(initials)
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.accent)
                        )
                        .overlay(Circle().stroke(DS.Colors.grid, lineWidth: 1))
                }
                
                PhotosPicker(selection: $selectedImage, matching: .images) {
                    ZStack {
                        Circle()
                            .fill(DS.Colors.accent)
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "camera.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 2, y: 2)
                }
            }
            
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName.isEmpty ? "User" : displayName)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    
                    Button { showEditName = true } label: {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                
                Text(userEmail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)
                
                Text("Member since \(memberSince)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext.opacity(0.7))
            }
            
            if isSaving {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Syncing...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
        .padding(.vertical, 8)
        .onChange(of: selectedImage) { _, newItem in
            loadAndSavePhoto(newItem)
        }
        .alert("Edit Display Name", isPresented: $showEditName) {
            TextField("Your name", text: $displayName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { }
            Button("Save") { saveProfile() }
        } message: {
            Text("Syncs across all your devices")
        }
    }
    
    // MARK: - Stats
    
    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: "\(totalTransactions)", label: "Transactions")
            statCard(value: DS.Format.money(totalSpentAllTime), label: "Total Spent")
            statCard(value: DS.Format.money(totalIncomeAllTime), label: "Total Income")
        }
    }
    
    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
        )
    }
    
    // MARK: - Subscription Status
    
    private var subscriptionCard: some View {
        let manager = SubscriptionManager.shared
        let isPro = manager.isPro
        
        let planLabel: String = {
            switch manager.currentPlan {
            case "monthly": return "Monthly"
            case "yearly": return "Yearly"
            default: return "Free"
            }
        }()
        
        let priceLabel: String = {
            switch manager.currentPlan {
            case "monthly": return "$4.99/mo"
            case "yearly": return "$28.99/yr"
            default: return "$0"
            }
        }()
        
        let renewalLabel: String = {
            guard isPro, let end = manager.currentPeriodEnd else {
                if manager.status == .trial, let trialEnd = manager.trialEndDate {
                    let fmt = DateFormatter()
                    fmt.dateFormat = "MMM d, yyyy"
                    return "Trial ends \(fmt.string(from: trialEnd))"
                }
                return "No active plan"
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "MMM d, yyyy"
            return "Renews \(fmt.string(from: end))"
        }()
        
        return VStack(alignment: .leading, spacing: 10) {
            Text("Subscription")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            
            VStack(spacing: 0) {
                // Top: Plan name + badge
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(isPro ? DS.Colors.accent : DS.Colors.surface2)
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: isPro ? "crown.fill" : "lock.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isPro ? .white : DS.Colors.subtext)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(isPro ? "Centmond Pro" : "Free Plan")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(DS.Colors.text)
                        
                        Text(planLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    
                    Spacer()
                    
                    Text(isPro ? "PRO" : "FREE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isPro ? .white : DS.Colors.subtext)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isPro ? DS.Colors.accent : DS.Colors.surface2)
                        .clipShape(Capsule())
                }
                .padding(14)
                
                if isPro || manager.status == .trial {
                    // Divider
                    Rectangle()
                        .fill(DS.Colors.grid)
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                    
                    // Bottom: Details
                    HStack {
                        // Renewal
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manager.status == .trial ? "Trial" : "Renewal")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                            Text(renewalLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Colors.text)
                        }
                        
                        Spacer()
                        
                        // Price
                        if manager.status == .active {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Billed")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                                Text(priceLabel)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(DS.Colors.text)
                            }
                        }
                        
                        if manager.status == .trial {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Days left")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                                Text("\(manager.trialDaysRemaining)")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                } else {
                    // Free user info
                    Rectangle()
                        .fill(DS.Colors.grid)
                        .frame(height: 0.5)
                        .padding(.horizontal, 14)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Transactions")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                            Text("\(store.transactions.count) / \(SubscriptionManager.freeTransactionLimit)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Colors.text)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Remaining")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Colors.subtext)
                            Text("\(max(0, SubscriptionManager.freeTransactionLimit - store.transactions.count))")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    store.transactions.count >= SubscriptionManager.freeTransactionLimit - 10
                                    ? DS.Colors.danger : DS.Colors.text
                                )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Account Info
    
    private var accountInfoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            
            VStack(spacing: 0) {
                infoRow(icon: "envelope.fill", title: "Email", value: userEmail, color: DS.Colors.accent)
                rowDivider
                infoRow(icon: "calendar", title: "Member Since", value: memberSince, color: DS.Colors.positive)
                rowDivider
                infoRow(icon: "repeat", title: "Recurring", value: "\(store.recurringTransactions.filter { $0.isActive }.count) active", color: DS.Colors.warning)
            }
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Actions
    
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Security")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            
            VStack(spacing: 0) {
                NavigationLink {
                    ChangePasswordView()
                } label: {
                    actionRow(icon: "lock.fill", title: "Change Password", color: DS.Colors.accent)
                }
                
                rowDivider
                
                NavigationLink {
                    // TODO
                } label: {
                    actionRow(icon: "square.and.arrow.up", title: "Export Data", color: DS.Colors.positive)
                }
            }
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DS.Colors.grid.opacity(0.5), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Sign Out
    
    private var signOutButton: some View {
        Button {
            Haptics.warning()
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
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                Text("Sign Out")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.danger.opacity(0.5))
            }
            .foregroundStyle(DS.Colors.danger)
            .padding(14)
            .background(DS.Colors.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Colors.danger.opacity(0.1), lineWidth: 0.8)
            )
        }
        .padding(.top, 8)
    }
    
    // MARK: - Shared Components
    
    private var rowDivider: some View {
        Divider().foregroundStyle(DS.Colors.grid).padding(.leading, 44)
    }
    
    private func infoRow(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    private func actionRow(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.text)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    // MARK: - Profile Sync
    
    private var initials: String {
        if !displayName.isEmpty {
            let parts = displayName.split(separator: " ")
            if parts.count >= 2 {
                return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
            }
            return String(displayName.prefix(2)).uppercased()
        }
        return String(userEmail.prefix(1)).uppercased()
    }
    
    private func loadProfile() {
        guard let userId = user?.id.uuidString else { return }
        
        // Local first
        if let savedName = UserDefaults.standard.string(forKey: "profile_name_\(userId)") {
            displayName = savedName
        }
        if let savedData = UserDefaults.standard.data(forKey: "profile_image_\(userId)"),
           let uiImage = UIImage(data: savedData) {
            profileImageData = savedData
            profileImage = Image(uiImage: uiImage)
        }
        
        // Then cloud
        Task { await loadFromCloud(userId: userId) }
    }
    
    private func loadFromCloud(userId: String) async {
        do {
            struct ProfileDTO: Codable {
                let display_name: String?
                let profile_image: String?
            }
            
            let response: [ProfileDTO] = try await supabaseManager.client.database
                .from("users")
                .select("display_name, profile_image")
                .eq("id", value: userId)
                .execute()
                .value
            
            if let profile = response.first {
                await MainActor.run {
                    if let name = profile.display_name, !name.isEmpty, name != "User" {
                        displayName = name
                        UserDefaults.standard.set(name, forKey: "profile_name_\(userId)")
                    }
                    if let base64 = profile.profile_image, !base64.isEmpty,
                       let data = Data(base64Encoded: base64),
                       let uiImage = UIImage(data: data) {
                        profileImageData = data
                        profileImage = Image(uiImage: uiImage)
                        UserDefaults.standard.set(data, forKey: "profile_image_\(userId)")
                    }
                }
            }
        } catch {
            SecureLogger.warning("Cloud profile load failed")
        }
    }
    
    private func saveProfile() {
        guard let userId = user?.id.uuidString else { return }
        
        UserDefaults.standard.set(displayName, forKey: "profile_name_\(userId)")
        
        isSaving = true
        Task {
            do {
                var data: [String: String] = ["display_name": displayName]
                
                if let imageData = profileImageData {
                    data["profile_image"] = imageData.base64EncodedString()
                }
                
                try await supabaseManager.client.database
                    .from("users")
                    .update(data)
                    .eq("id", value: userId)
                    .execute()
                
                await MainActor.run { isSaving = false }
                SecureLogger.info("Profile synced")
            } catch {
                await MainActor.run { isSaving = false }
                SecureLogger.error("Profile sync failed", error)
            }
        }
    }
    
    private func loadAndSavePhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data) {
                let resized = resizeImage(uiImage, maxDimension: 300)
                guard let compressed = resized.jpegData(compressionQuality: 0.6) else { return }
                
                await MainActor.run {
                    profileImageData = compressed
                    profileImage = Image(uiImage: resized)
                    if let userId = user?.id.uuidString {
                        UserDefaults.standard.set(compressed, forKey: "profile_image_\(userId)")
                    }
                }
                saveProfile()
            }
        }
    }
    
    private func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxDimension / size.width, maxDimension / size.height)
        if ratio >= 1 { return image }
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Glass Card Modifier

private extension View {
    func glassCard() -> some View {
        self
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
            )
    }
}

// MARK: - Change Password View

struct ChangePasswordView: View {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showSuccess = false
    @State private var isLoading = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Change Your Password")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    
                    Divider().foregroundStyle(DS.Colors.grid)
                    
                    fieldSection("New Password") {
                        SecureField("At least 6 characters", text: $newPassword)
                            .font(DS.Typography.body)
                            .padding(12)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            .textInputAutocapitalization(.never)
                    }
                    
                    fieldSection("Confirm Password") {
                        SecureField("Re-enter password", text: $confirmPassword)
                            .font(DS.Typography.body)
                            .padding(12)
                            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            
                            .textInputAutocapitalization(.never)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        reqRow(met: newPassword.count >= 6, text: "At least 6 characters")
                        reqRow(met: newPassword == confirmPassword && !newPassword.isEmpty, text: "Passwords match")
                    }
                    
                    if showError {
                        Text(errorMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Colors.danger)
                    }
                    
                    Button { changePassword() } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            else {
                                Image(systemName: "lock.rotation")
                                Text("Change Password")
                            }
                        }
                    }
                    .buttonStyle(DS.PrimaryButton())
                    .disabled(!isFormValid || isLoading)
                    .opacity(isFormValid ? 1 : 0.5)
                }
                .padding(16)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
            }
            .padding()
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Change Password")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Success", isPresented: $showSuccess) {
            Button("OK") { dismiss() }
        } message: {
            Text("Your password has been changed.")
        }
    }
    
    private func fieldSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
            content()
        }
    }
    
    private func reqRow(met: Bool, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? DS.Colors.positive : DS.Colors.subtext)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
        }
    }
    
    private var isFormValid: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }
    
    private func changePassword() {
        guard isFormValid else { return }
        isLoading = true
        showError = false
        
        Task {
            do {
                try await authManager.changePassword(newPassword: newPassword)
                await MainActor.run { isLoading = false; showSuccess = true }
            } catch let authError as AuthError {
                await MainActor.run {
                    isLoading = false
                    errorMessage = authError.errorDescription ?? "Could not change password."
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = AppConfig.shared.safeErrorMessage(
                        detail: error.localizedDescription,
                        fallback: "Could not change password. Please try again."
                    )
                    showError = true
                }
            }
        }
    }
}
