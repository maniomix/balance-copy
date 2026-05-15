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
        // Surface missing Supabase / AI proxy config early. Logs to SecureLogger
        // in release; without this a misconfigured release build silently boots
        // with empty credentials and fails on every network call.
        AppConfig.shared.validate()

        // User-requested: "after fully closing the app dynamic island also
        // should be killed". cleanupOrphans nukes ANY in-flight activity on
        // launch — safety net for hard force-quits where willTerminate
        // didn't fire. .active scenePhase will create a fresh one.
        //
        // Activity.request can't be called from init() — iOS 17.2+ throws
        // ActivityAuthorizationError.visibility before the scene is active.
        BudgetLiveActivityManager.shared.cleanupOrphans()

        // Graceful-quit cleanup. iOS gives ~5s on termination; we use 2s
        // of that to block waiting for Activity.end() to complete.
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
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
            Task { await AuthManager.shared.validateSessionStillValid() }
            guard liveActivityEnabled() else {
                BudgetLiveActivityManager.shared.endAll()
                return
            }
            // Defer heavy work — let iOS finish the morph-into-app animation
            // before we burn main-actor cycles on Store.load + state rebuild.
            // resetToFirstPage: true → every app foreground snaps back to
            // the Budget page (user-requested).
            Task { @MainActor in
                let store = currentStore()
                BudgetLiveActivityManager.shared.ensureStarted(store: store)
                BudgetLiveActivityManager.shared.refresh(store: store, resetToFirstPage: true)
            }
        case .background:
            // Intentionally no start/refresh here. iOS 17.2+ throws
            // `ActivityAuthorizationError.visibility` for `Activity.request`
            // calls from background — start is gated to `.active` only.
            // Persistent activities (already alive from a prior `.active`)
            // morph correctly on the way out without any action from us.
            break
        default:
            break
        }
    }

    private func liveActivityEnabled() -> Bool {
        UserDefaults.standard.object(forKey: "dynamicIsland.enabled") as? Bool ?? true
    }

    private func currentStore() -> Store {
        Store.load(userId: AuthManager.shared.currentUser?.uid)
    }
}
