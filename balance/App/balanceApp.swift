import SwiftUI
import SwiftData
import UIKit

@main
struct balanceApp: App {
    @StateObject private var supabaseManager = SupabaseManager.shared
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var appLockManager = AppLockManager.shared
    @Environment(\.scenePhase) private var scenePhase

    let chatContainer: ModelContainer = {
        let schema = Schema([ChatSession.self, ChatMessageRecord.self])
        // Pin the chat store to the app's own Application Support directory.
        // Without this, SwiftData's default `ModelConfiguration(named:)` picks up
        // the App Group shared container (widget target's group entitlement) and
        // tries to write to `/AppGroup/<uuid>/Library/Application Support/`,
        // which the main app sandbox can't create.
        let fm = FileManager.default
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fm.temporaryDirectory
        let url = appSupport.appendingPathComponent("CentmondChat.store")
        let config = ModelConfiguration(schema: schema, url: url)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create chat ModelContainer: \(error)")
        }
    }()

    init() {
        // If a previous run was force-quit, the system kept its Live Activity
        // alive. Tear it down on launch so a closed app never has an island.
        BudgetLiveActivityManager.shared.endAll()

        // Best-effort end on graceful termination — semaphore-blocked so we
        // actually wait for Activity.end() to complete (within 2s budget).
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            print("🔴 [balanceApp] willTerminate fired — ending Live Activities")
            BudgetLiveActivityManager.shared.endAllBlocking()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabaseManager)
                .environmentObject(authManager)
                .environmentObject(appLockManager)
                .onOpenURL { url in
                    // OAuth (Google / Apple) redirects land here as
                    // `centmond://auth-callback?...`. Hand off to AuthManager
                    // which finalizes the Supabase session.
                    authManager.handleOpenURL(url)
                }
        }
        .modelContainer(chatContainer)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            // Detect a stale session — e.g. user deleted on another device
            // while this device was offline. Will sign out if the profile row
            // is gone; ignores transient errors.
            Task { await AuthManager.shared.validateSessionStillValid() }
            BudgetLiveActivityManager.shared.endAll()
            return
        case .background:
            // Honor the user's Settings → Dynamic Island toggle.
            guard UserDefaults.standard.object(forKey: "dynamicIsland.enabled") as? Bool ?? true else { return }
            let userId = AuthManager.shared.currentUser?.uid
            let store = Store.load(userId: userId)
            // Only start if there's actually a budget set, otherwise the
            // activity has nothing useful to show.
            guard store.budget(for: store.selectedMonth) > 0 else { return }
            BudgetLiveActivityManager.shared.start(store: store)
        default:
            break
        }
    }
}
