import SwiftUI
import UserNotifications

// ============================================================
// MARK: - Subscription Preferences (Phase 6c)
// ============================================================
//
// Standalone settings sheet for `SubscriptionAlertScheduler`.
// Decoupled from the broader SettingsView (which currently has
// ~2k uncommitted lines from the Settings Redesign) so this can
// land cleanly. Wire-in path:
//   `NavigationLink("Subscriptions", destination: SubscriptionPreferencesView())`
// from Settings → Preferences when SettingsView lands its commit.
//
// Backed entirely by UserDefaults; the scheduler reads the same
// keys (defined on `SubscriptionAlertScheduler`) so no shared
// observable state is required. Toggling any class triggers an
// immediate `rescheduleAll` so behavior changes are visible
// without leaving the screen.
//
// ============================================================

struct SubscriptionPreferencesView: View {

    // Mirrored from UserDefaults — initial values pulled in init.
    @State private var masterEnabled: Bool
    @State private var renewalEnabled: Bool
    @State private var renewalLeadDays: Int
    @State private var trialEnabled: Bool
    @State private var trialLeadDays: Int
    @State private var priceChangeEnabled: Bool
    @State private var authStatus: UNAuthorizationStatus = .notDetermined

    @StateObject private var engine = SubscriptionEngine.shared

    private static let leadDayChoices: [Int] = [0, 1, 2, 3, 5, 7]

    init() {
        let d = UserDefaults.standard
        _masterEnabled = State(initialValue: d.object(forKey: SubscriptionAlertScheduler.masterEnabledKey) as? Bool ?? false)
        _renewalEnabled = State(initialValue: d.object(forKey: SubscriptionAlertScheduler.renewalEnabledKey) as? Bool ?? true)
        _renewalLeadDays = State(initialValue: d.object(forKey: SubscriptionAlertScheduler.renewalLeadDaysKey) as? Int ?? SubscriptionAlertScheduler.defaultRenewalLeadDays)
        _trialEnabled = State(initialValue: d.object(forKey: SubscriptionAlertScheduler.trialEnabledKey) as? Bool ?? true)
        _trialLeadDays = State(initialValue: d.object(forKey: SubscriptionAlertScheduler.trialLeadDaysKey) as? Int ?? SubscriptionAlertScheduler.defaultTrialLeadDays)
        _priceChangeEnabled = State(initialValue: d.object(forKey: SubscriptionAlertScheduler.priceChangeEnabledKey) as? Bool ?? true)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Subscription alerts", isOn: $masterEnabled)
                    .onChange(of: masterEnabled) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: SubscriptionAlertScheduler.masterEnabledKey)
                        if newValue && authStatus != .authorized {
                            SubscriptionAlertScheduler.requestAuthorization { _ in
                                refreshAuthStatus()
                                reschedule()
                            }
                        } else {
                            reschedule()
                        }
                    }
            } footer: {
                if masterEnabled && authStatus == .denied {
                    Text("Notifications are turned off for Centmond in iOS Settings. Enable them there to receive alerts.")
                        .foregroundStyle(.red)
                } else {
                    Text("Master switch. Turning this off clears all scheduled subscription alerts.")
                }
            }

            if masterEnabled {
                Section("Renewal reminders") {
                    Toggle("Notify before renewal", isOn: $renewalEnabled)
                        .onChange(of: renewalEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: SubscriptionAlertScheduler.renewalEnabledKey)
                            reschedule()
                        }

                    if renewalEnabled {
                        Picker("Lead time", selection: $renewalLeadDays) {
                            ForEach(Self.leadDayChoices, id: \.self) { d in
                                Text(leadLabel(d)).tag(d)
                            }
                        }
                        .onChange(of: renewalLeadDays) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: SubscriptionAlertScheduler.renewalLeadDaysKey)
                            reschedule()
                        }
                    }
                }

                Section("Trial endings") {
                    Toggle("Notify before trial ends", isOn: $trialEnabled)
                        .onChange(of: trialEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: SubscriptionAlertScheduler.trialEnabledKey)
                            reschedule()
                        }

                    if trialEnabled {
                        Picker("Lead time", selection: $trialLeadDays) {
                            ForEach(Self.leadDayChoices, id: \.self) { d in
                                Text(leadLabel(d)).tag(d)
                            }
                        }
                        .onChange(of: trialLeadDays) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: SubscriptionAlertScheduler.trialLeadDaysKey)
                            reschedule()
                        }
                    }
                }

                Section {
                    Toggle("Notify on price changes", isOn: $priceChangeEnabled)
                        .onChange(of: priceChangeEnabled) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: SubscriptionAlertScheduler.priceChangeEnabledKey)
                            reschedule()
                        }
                } footer: {
                    Text("Fires when the latest charge differs from the prior median by 2% or more.")
                }
            }
        }
        .navigationTitle("Subscription Alerts")
        .navigationBarTitleDisplayMode(.inline)
        .task { refreshAuthStatus() }
    }

    // MARK: - Helpers

    private func leadLabel(_ days: Int) -> String {
        switch days {
        case 0: return "On the day"
        case 1: return "1 day before"
        default: return "\(days) days before"
        }
    }

    private func refreshAuthStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authStatus = settings.authorizationStatus
            }
        }
    }

    /// Apply the current snapshot's records through the scheduler. Called
    /// after every preference toggle so the user sees the effect of the
    /// change immediately, not on the next analyze.
    private func reschedule() {
        SubscriptionAlertScheduler.rescheduleAll(records: engine.subscriptions)
    }
}
