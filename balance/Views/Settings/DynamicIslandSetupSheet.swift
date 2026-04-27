import SwiftUI

struct DynamicIslandSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("Requirements", icon: "checkmark.seal.fill", tint: DS.Colors.positive)

                            requirementRow(
                                icon: "iphone.gen3",
                                title: "iPhone 14 Pro or newer",
                                body: "The Dynamic Island only exists on Pro models from iPhone 14 onward. On older iPhones you'll still get the lock-screen card."
                            )
                            requirementRow(
                                icon: "chart.pie.fill",
                                title: "A monthly budget set",
                                body: "Open Centmond, set a budget for the month you're tracking. The activity won't appear without one."
                            )
                            requirementRow(
                                icon: "switch.2",
                                title: "Toggle enabled above",
                                body: "If you turned it off, no activity will start when you background the app.",
                                isLast: true
                            )
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("How to use it", icon: "hand.tap.fill", tint: DS.Colors.accent)

                            useRow(
                                icon: "1.circle.fill",
                                title: "Background the app",
                                body: "Swipe up to home or switch to another app. The Dynamic Island appears with your budget."
                            )
                            useRow(
                                icon: "2.circle.fill",
                                title: "Glance for the quick read",
                                body: "Compact mode shows the budget icon and your remaining amount."
                            )
                            useRow(
                                icon: "3.circle.fill",
                                title: "Long-press for details",
                                body: "Touch and hold the island to expand the detail view with progress bar and totals."
                            )
                            useRow(
                                icon: "4.circle.fill",
                                title: "Tap Next to switch pages",
                                body: "The expanded view rotates through 4 information pages. Use the Next ›  button on the right.",
                                isLast: true
                            )
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("The 4 pages", icon: "rectangle.stack.fill", tint: DS.Colors.warning)

                            pageRow(icon: "chart.pie.fill",   tint: DS.Colors.accent,   title: "Budget",       body: "Remaining (or amount over), progress bar, days left, spent vs total.")
                            pageRow(icon: "sun.max.fill",     tint: DS.Colors.warning,  title: "Today",        body: "Spent today and how many transactions you logged.")
                            pageRow(icon: "calendar",         tint: DS.Colors.positive, title: "This Week",    body: "Total for the last 7 days plus a daily average.")
                            pageRow(icon: "trophy.fill",      tint: DS.Colors.danger,   title: "Top Category", body: "Biggest spending category this month.", isLast: true)
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Tips", icon: "lightbulb.fill", tint: DS.Colors.warning)

                            bullet("The activity follows the month you're browsing in the app — not always the calendar month.")
                            bullet("Color goes green → orange (≥85%) → red (over budget).")
                            bullet("Auto-ends when you reopen Centmond. Backgrounding starts a fresh one.")
                            bullet("Adding a transaction via Back Tap automatically refreshes the numbers.")
                        }
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Dynamic Island")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Capsule()
                    .fill(LinearGradient(
                        colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 110, height: 38)
                HStack(spacing: 10) {
                    Image(systemName: "chart.pie.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("€420")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
            }
            VStack(spacing: 4) {
                Text("Budget on your Dynamic Island")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.text)
                Text("Glanceable spending info while Centmond is in the background.")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: - Subviews

    private func sectionTitle(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text(title)
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
        }
    }

    private func requirementRow(icon: String, title: String, body: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(DS.Colors.positive)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 4)
    }

    private func useRow(icon: String, title: String, body: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 4)
    }

    private func pageRow(icon: String, tint: Color, title: String, body: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, isLast ? 0 : 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(DS.Colors.warning)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(DS.Colors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
