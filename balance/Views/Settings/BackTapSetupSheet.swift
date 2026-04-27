import SwiftUI

struct BackTapSetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    DS.Card {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionTitle("Step 1 — Create the shortcut", icon: "square.stack.3d.up.fill", tint: DS.Colors.accent)

                            Text("Back Tap can only run shortcuts you've saved. We need to wrap Quick Add Transaction in a shortcut first.")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)

                            stepRow(
                                number: 1,
                                title: "Open the Shortcuts app",
                                body: "Tap the button below to jump there."
                            )
                            stepRow(
                                number: 2,
                                title: "Tap the + button (top right)",
                                body: "On the Shortcuts tab — not Gallery, not Automation."
                            )
                            stepRow(
                                number: 3,
                                title: "Tap Add Action",
                                body: "Then search “Quick Add Transaction” or “Centmond”."
                            )
                            stepRow(
                                number: 4,
                                title: "Pick Quick Add Transaction",
                                body: "Centmond's icon will be next to it."
                            )
                            stepRow(
                                number: 5,
                                title: "Tap Done (top right)",
                                body: "The shortcut is saved to your library.",
                                isLast: true
                            )

                            Button {
                                openShortcutsApp()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.stack.3d.up.fill")
                                    Text("Open Shortcuts App")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 16) {
                            sectionTitle("Step 2 — Assign it to Back Tap", icon: "iphone.gen3", tint: DS.Colors.accent)

                            stepRow(
                                number: 1,
                                title: "Open the Settings app",
                                body: "Tap the button below."
                            )
                            stepRow(
                                number: 2,
                                title: "Accessibility → Touch",
                                body: "Scroll to the Physical and Motor section."
                            )
                            stepRow(
                                number: 3,
                                title: "Scroll down to Back Tap",
                                body: "Near the bottom of the Touch screen."
                            )
                            stepRow(
                                number: 4,
                                title: "Pick Double Tap or Triple Tap",
                                body: "Whichever feels right for you."
                            )
                            stepRow(
                                number: 5,
                                title: "Scroll to the Shortcuts section",
                                body: "Past System, Accessibility, and Scroll Gestures — your saved shortcut appears at the bottom."
                            )
                            stepRow(
                                number: 6,
                                title: "Tap your Quick Add shortcut",
                                body: "Done — Back Tap is wired up.",
                                isLast: true
                            )

                            Button {
                                openIOSSettings()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "gearshape.fill")
                                    Text("Open Settings App")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 14) {
                            sectionTitle("How to use it", icon: "hand.tap.fill", tint: DS.Colors.positive)

                            useRow(
                                icon: "1.circle.fill",
                                title: "Double tap the back of your iPhone",
                                body: "Anywhere — even with the screen locked."
                            )
                            useRow(
                                icon: "2.circle.fill",
                                title: "Type the amount",
                                body: "iOS shows a small dialog. Enter how much was spent."
                            )
                            useRow(
                                icon: "3.circle.fill",
                                title: "Pick a category",
                                body: "Tap one from the dropdown."
                            )
                            useRow(
                                icon: "4.circle.fill",
                                title: "Confirm",
                                body: "A confirmation card shows the saved transaction. Centmond never opens.",
                                isLast: true
                            )
                        }
                    }

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("Tips", icon: "lightbulb.fill", tint: DS.Colors.warning)

                            bullet("Back Tap only sees shortcuts you've saved in the Shortcuts app — that's why Step 1 is required.")
                            bullet("Date defaults to today — leave it blank for fastest entry.")
                            bullet("All entries save as card expenses. Edit details later in the app.")
                            bullet("You can also trigger it by saying \u{201C}Hey Siri, quick add transaction in Centmond\u{201D}.")
                        }
                    }

                    Color.clear.frame(height: 24)
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Back Tap Setup")
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
                Circle()
                    .fill(LinearGradient(colors: [DS.Colors.accent, DS.Colors.accent.opacity(0.65)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(spacing: 4) {
                Text("Quick Add with Back Tap")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.text)
                Text("Add a transaction in 5 seconds without opening Centmond.")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.subtext)
                    .multilineTextAlignment(.center)
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

    private func stepRow(number: Int, title: String, body: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.15))
                        .frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.accent)
                }
                if !isLast {
                    Rectangle()
                        .fill(DS.Colors.grid)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
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
            .padding(.bottom, isLast ? 0 : 14)
            Spacer(minLength: 0)
        }
    }

    private func useRow(icon: String, title: String, body: String, isLast: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22))
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

    // MARK: - Settings deep link

    private func openIOSSettings() {
        // Try the (undocumented) prefs root first; fall back to the app's own
        // settings page if iOS blocks it.
        if let prefs = URL(string: "App-Prefs:"), UIApplication.shared.canOpenURL(prefs) {
            UIApplication.shared.open(prefs)
            return
        }
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func openShortcutsApp() {
        if let url = URL(string: "shortcuts://create-shortcut"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        if let url = URL(string: "shortcuts://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
