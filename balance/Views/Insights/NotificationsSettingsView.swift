import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss

    @AppStorage("notifications.enabled") private var notificationsEnabled: Bool = false
    @State private var notifDetail: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Notifications")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)
                                Spacer()
                                Toggle("", isOn: $notificationsEnabled)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: DS.Colors.accent))
                            }

                            Text("Get alerts about your spending")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Colors.subtext)

                            if let notifDetail {
                                DS.StatusLine(
                                    title: "Notification status",
                                    detail: notifDetail,
                                    level: notificationsEnabled ? .ok : .watch
                                )
                            }

                            Button {
                                Task { await sendTestNotification() }
                            } label: {
                                HStack {
                                    Image(systemName: "bell.badge")
                                    Text("Send Test")
                                }
                            }
                            .buttonStyle(DS.PrimaryButton())
                            .disabled(!notificationsEnabled)

                            Text("Make sure notifications work")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: notificationsEnabled) { _, newVal in
                if newVal {
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await requestNotificationPermissionIfNeeded()
                        await Notifications.syncAll(store: store)
                    }
                } else {
                    notifDetail = "Notifications are turned off in the app."
                    Notifications.cancelAll()
                }
            }
            .onAppear {
                UNUserNotificationCenter.current().delegate = NotificationCenterDelegate.shared
                if notificationsEnabled {
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                        await Notifications.syncAll(store: store)
                    }
                }
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await MainActor.run {
                notifDetail = "Enabled. You can send a test notification now."
            }
            await Notifications.syncAll(store: store)
        case .denied:
            await MainActor.run {
                notificationsEnabled = false
                notifDetail = "Notifications are blocked in iOS Settings for this app. Enable them in Settings → Notifications."
            }
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
                await MainActor.run {
                    if granted {
                        notifDetail = "Permission granted. Tap 'Send test notification'."
                    } else {
                        notificationsEnabled = false
                        notifDetail = "Permission not granted. Toggle stayed off."
                    }
                }
                if granted {
                    await Notifications.syncAll(store: store)
                }
            } catch {
                await MainActor.run {
                    notificationsEnabled = false
                    notifDetail = AppConfig.shared.safeErrorMessage(
                        detail: "Couldn't request permission: \(error.localizedDescription)",
                        fallback: "Couldn't request notification permission."
                    )
                }
            }
        @unknown default:
            await MainActor.run {
                notifDetail = "Unknown notification status."
            }
        }
    }

    private func sendTestNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        guard notificationsEnabled else {
            await MainActor.run { notifDetail = "Turn notifications on first." }
            return
        }

        guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
            await MainActor.run {
                notificationsEnabled = false
                notifDetail = "Notifications are not authorized. Please enable them in iOS Settings."
            }
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: ["balance.test.notification"])

        let content = UNMutableNotificationContent()
        content.title = "Centmond — Test"
        content.body = "This is a test notification. If you see this, notifications are working."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let req = UNNotificationRequest(identifier: "balance.test.notification", content: content, trigger: trigger)

        do {
            try await center.add(req)
            await MainActor.run {
                notifDetail = "Test notification scheduled (in ~3 seconds)."
            }
        } catch {
            await MainActor.run {
                notifDetail = AppConfig.shared.safeErrorMessage(
                    detail: "Failed to schedule notification: \(error.localizedDescription)",
                    fallback: "Failed to schedule notification."
                )
            }
        }
    }
}
