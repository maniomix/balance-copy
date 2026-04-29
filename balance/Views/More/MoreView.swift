import SwiftUI

// MARK: - More Tab

struct MoreView: View {
    @Binding var store: Store
    @Binding var selectedTab: Tab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    NavigationLink { AccountsListView(store: $store) } label: {
                        moreRowLabel(icon: "building.columns", title: "Accounts", subtitle: "Net worth & balances", color: DS.Colors.accent)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { GoalsOverviewView(store: $store) } label: {
                        moreRowLabel(icon: "flag.fill", title: "Goals", subtitle: "Savings targets & progress", color: DS.Colors.positive)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { SubscriptionsOverviewView(store: $store) } label: {
                        moreRowLabel(icon: "creditcard.and.123", title: "Subscriptions", subtitle: "Recurring charges & alerts", color: Color(hexValue: 0xFF9F0A))
                    }
                    .buttonStyle(.plain)

                    NavigationLink { HouseholdOverviewView(store: $store) } label: {
                        moreRowLabel(icon: "person.2.fill", title: "Household", subtitle: "Shared finance & split expenses", color: DS.Colors.accent)
                    }
                    .buttonStyle(.plain)

                    NavigationLink { MonthlyBriefingScreen(store: $store) } label: {
                        moreRowLabel(icon: "doc.text.magnifyingglass", title: "Monthly Briefing", subtitle: "Your financial summary & insights", color: Color(hexValue: 0x5856D6))
                    }
                    .buttonStyle(.plain)

                    Divider().foregroundStyle(DS.Colors.grid).padding(.vertical, 4)

                    NavigationLink { SettingsView(store: $store) } label: {
                        moreRowLabel(icon: "gearshape.fill", title: "Settings", subtitle: "Account, backup & preferences", color: DS.Colors.subtext)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SectionHelpButton(screen: .more)
                }
            }
        }
    }

    private func moreRowLabel(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Colors.subtext)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
        }
        .padding(12)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
