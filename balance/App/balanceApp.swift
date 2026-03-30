import SwiftUI

@main
struct balanceApp: App {
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var appLockManager = AppLockManager.shared

    init() {
        // Setup app on launch
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabaseManager)
                .environmentObject(authManager)
                .environmentObject(appLockManager)
        }
    }
}
