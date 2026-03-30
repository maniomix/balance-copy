import SwiftUI

// MARK: - Privacy Policy

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Privacy Policy")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .padding(.bottom, 8)

                Text("Last updated: February 10, 2026")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.subtext)

                privacySection(
                    title: "Your Privacy Matters",
                    content: "Centmond is designed with privacy at its core. All your financial data is stored locally on your device and optionally synced to your private iCloud account. We never have access to your financial information."
                )

                privacySection(
                    title: "Data Collection",
                    content: "We do not collect, transmit, or sell any of your personal or financial data. The app operates entirely offline with optional iCloud sync that only you can access."
                )

                privacySection(
                    title: "Analytics",
                    content: "Centmond does not use any third-party analytics or tracking tools. Your usage patterns remain completely private."
                )

                privacySection(
                    title: "Security",
                    content: "Your data is encrypted both on device and during iCloud sync using Apple's industry-standard encryption. Only you have the keys to access your information."
                )

                privacySection(
                    title: "Your Rights",
                    content: "You have full control over your data. You can export, delete, or backup all your financial information at any time directly from the app."
                )

                Divider().foregroundStyle(DS.Colors.grid)

                Text("For questions about privacy, contact centmond.support@gmail.com")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.subtext)
            }
            .padding(20)
        }
        .background(DS.Colors.bg)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacySection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Colors.text)

            Text(content)
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Terms of Service

struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Terms of Service")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .padding(.bottom, 8)

                Text("Last updated: February 10, 2026")
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Colors.subtext)

                termsSection(
                    title: "1. Acceptance of Terms",
                    content: "By using Centmond, you agree to these Terms of Service. If you do not agree, please do not use the app."
                )

                termsSection(
                    title: "2. Use of Service",
                    content: "Centmond is provided as-is for personal financial management. You are responsible for the accuracy of data you enter and for maintaining backups of your information."
                )

                termsSection(
                    title: "3. Disclaimer",
                    content: "Centmond is a tool to help you manage your finances. It does not provide financial advice. Always consult with a qualified financial advisor for important financial decisions."
                )

                termsSection(
                    title: "4. Limitation of Liability",
                    content: "Centmond is not liable for any financial losses, damages, or decisions made based on information in Centmond. Use the app at your own discretion."
                )

                termsSection(
                    title: "5. Changes to Terms",
                    content: "We may update these terms from time to time. Continued use of the app after changes constitutes acceptance of new terms."
                )

                termsSection(
                    title: "6. Contact",
                    content: "For questions about these terms, contact us at centmond.support@gmail.com"
                )

                Divider().foregroundStyle(DS.Colors.grid)

                Text("\u{00A9} 2026 Centmond. All rights reserved.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)
            }
            .padding(20)
        }
        .background(DS.Colors.bg)
        .navigationTitle("Terms")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func termsSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Colors.text)

            Text(content)
                .font(.system(size: 14))
                .foregroundStyle(DS.Colors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Licenses

struct LicensesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                LicenseCard(
                    name: "ZIPFoundation",
                    license: "MIT License",
                    copyright: "Copyright \u{00A9} 2017-2024 Thomas Zoechling",
                    text: """
                    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

                    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

                    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                    """
                )

                LicenseCard(
                    name: "SF Symbols",
                    license: "Apple License",
                    copyright: "Copyright \u{00A9} 2024 Apple Inc.",
                    text: """
                    SF Symbols are used in accordance with Apple's Human Interface Guidelines and are licensed for use in applications running on Apple platforms.

                    The SF Symbols are provided for use in designing your app's user interface and may only be used to develop, test, and publish apps in Apple's app stores.
                    """
                )

                LicenseCard(
                    name: "SwiftUI",
                    license: "Apple License",
                    copyright: "Copyright \u{00A9} 2024 Apple Inc.",
                    text: """
                    SwiftUI is a framework provided by Apple Inc. for building user interfaces across all Apple platforms using Swift.

                    Licensed under the Apple Developer Agreement.
                    """
                )

                LicenseCard(
                    name: "Swift Charts",
                    license: "Apple License",
                    copyright: "Copyright \u{00A9} 2024 Apple Inc.",
                    text: """
                    Swift Charts is a framework provided by Apple Inc. for creating charts and data visualizations in SwiftUI.

                    Licensed under the Apple Developer Agreement.
                    """
                )

                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("App License")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)

                        Divider().foregroundStyle(DS.Colors.grid)

                        Text("""
                        Centmond is proprietary software developed by Mani. All rights reserved.

                        This application and its content are protected by copyright and other intellectual property laws. You may not reverse engineer, decompile, or disassemble this application.

                        Your data is stored locally on your device and is never transmitted to external servers (except when using the optional AI analysis feature).
                        """)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .navigationTitle("Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - License Card

struct LicenseCard: View {
    let name: String
    let license: String
    let copyright: String
    let text: String

    @State private var isExpanded = false

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name)
                                .font(DS.Typography.body.weight(.semibold))
                                .foregroundStyle(DS.Colors.text)

                            Text(license)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().foregroundStyle(DS.Colors.grid)

                    Text(copyright)
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Colors.text)

                    Text(text)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - AI Analysis Models

struct AIAnalysisPayload: Codable {
    struct DayTotal: Codable { let day: Int; let amount: Int }
    struct CategoryTotal: Codable { let name: String; let amount: Int }

    let month: String
    let budget: Int
    let totalSpent: Int
    let remaining: Int
    let dailyAvg: Int
    let daily: [DayTotal]
    let categories: [CategoryTotal]

    static func from(store: Store) -> AIAnalysisPayload {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: store.selectedMonth)
        let year = comps.year ?? 0
        let monthNum = comps.month ?? 0
        let monthStr = String(format: "%04d-%02d", year, monthNum)

        let summary = Analytics.monthSummary(store: store)
        let points = Analytics.dailySpendPoints(store: store)
        let breakdown = Analytics.categoryBreakdown(store: store)

        let daily = points.map { DayTotal(day: $0.day, amount: $0.amount) }
        let cats = breakdown.map { CategoryTotal(name: $0.category.title, amount: $0.total) }

        return AIAnalysisPayload(
            month: monthStr,
            budget: store.budgetTotal,
            totalSpent: summary.totalSpent,
            remaining: summary.remaining,
            dailyAvg: summary.dailyAvg,
            daily: daily,
            categories: cats
        )
    }
}

struct AIAnalysisResult: Codable {
    let summary: String
    let insights: [String]
    let actions: [String]
    let riskLevel: String

    var riskLevelLevel: Level {
        switch riskLevel.lowercased() {
        case "ok": return .ok
        case "watch": return .watch
        case "risk": return .risk
        default: return .watch
        }
    }
}
