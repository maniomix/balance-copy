import SwiftUI
import Charts
import Supabase

// MARK: - Account Detail View

struct AccountDetailView: View {
    
    let account: Account
    
    @StateObject private var accountManager = AccountManager.shared
    @State private var balanceHistory: [AccountBalanceSnapshot] = []
    @State private var showEditSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                balanceCard
                if !balanceHistory.isEmpty { balanceChartCard }
                detailsCard
                actionsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
                    .foregroundStyle(DS.Colors.accent)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditAccountView(mode: .edit(account))
        }
        .task { await loadHistory() }
    }
    
    private var balanceCard: some View {
        DS.Card {
            VStack(spacing: 12) {
                Image(systemName: account.type.iconName)
                    .font(.title2)
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 50, height: 50)
                    .background(DS.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
                Text("Current Balance")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                
                Text(fmtCurrency(account.currentBalance))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                if let converted = convertedBalanceText {
                    Text(converted)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                }

                Text(account.type.isAsset ? "Asset" : "Liability")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(account.type.isAsset ? DS.Colors.positive : DS.Colors.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        (account.type.isAsset ? DS.Colors.positive : DS.Colors.danger).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                
                if account.type == .creditCard, let limit = account.creditLimit, limit > 0 {
                    creditBar(used: abs(account.currentBalance), limit: limit)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private func creditBar(used: Double, limit: Double) -> some View {
        let ratio = min(used / limit, 1.0)
        let color: Color = ratio > 0.75 ? DS.Colors.danger : (ratio > 0.5 ? DS.Colors.warning : DS.Colors.positive)
        return VStack(spacing: 6) {
            HStack {
                Text("Credit Used").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                Spacer()
                Text("\(Int(ratio * 100))%").font(DS.Typography.caption.weight(.semibold)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(DS.Colors.grid).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: geo.size.width * ratio, height: 5)
                }
            }.frame(height: 5)
            HStack {
                Text("\(fmtCurrency(used)) used").font(.system(size: 10)).foregroundStyle(DS.Colors.subtext)
                Spacer()
                Text("\(fmtCurrency(limit)) limit").font(.system(size: 10)).foregroundStyle(DS.Colors.subtext)
            }
        }.padding(.top, 8)
    }
    
    private var balanceChartCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Balance History").font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                if #available(iOS 16.0, *) {
                    Chart(balanceHistory) { s in
                        LineMark(x: .value("Date", s.snapshotDate), y: .value("Balance", s.balance))
                            .interpolationMethod(.catmullRom).foregroundStyle(DS.Colors.accent)
                        AreaMark(x: .value("Date", s.snapshotDate), y: .value("Balance", s.balance))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(LinearGradient(colors: [DS.Colors.accent.opacity(0.2), DS.Colors.accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    }
                    .chartYAxis { AxisMarks(position: .leading) { v in AxisValueLabel { if let a = v.as(Double.self) { Text(fmtCompact(a)).font(.system(size: 10)).foregroundStyle(DS.Colors.subtext) } } } }
                    .chartXAxis { AxisMarks(values: .stride(by: .month)) { v in AxisValueLabel { if let d = v.as(Date.self) { Text(d, format: .dateTime.month(.abbreviated)).font(.system(size: 10)).foregroundStyle(DS.Colors.subtext) } } } }
                    .frame(height: 170)
                }
            }
        }
    }
    
    private var detailsCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 0) {
                Text("Details").font(DS.Typography.section).foregroundStyle(DS.Colors.text).padding(.bottom, 10)
                row("Type", account.type.displayName)
                if let inst = account.institutionName, !inst.isEmpty { Divider().padding(.vertical, 6); row("Institution", inst) }
                Divider().padding(.vertical, 6); row("Currency", account.currency)
                if let rate = account.interestRate { Divider().padding(.vertical, 6); row("Interest Rate", String(format: "%.2f%%", rate)) }
                Divider().padding(.vertical, 6); row("Created", account.createdAt.formatted(date: .abbreviated, time: .omitted))
                Divider().padding(.vertical, 6); row("Updated", account.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
    
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(DS.Typography.body).foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value).font(DS.Typography.body.weight(.medium)).foregroundStyle(DS.Colors.text)
        }
    }
    
    private var actionsCard: some View {
        Button {
            Task { _ = await accountManager.archiveAccount(account) }
        } label: {
            HStack { Image(systemName: "archivebox"); Text("Archive Account") }
                .font(DS.Typography.body.weight(.medium))
                .foregroundStyle(DS.Colors.warning)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(DS.Colors.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
    
    private func loadHistory() async {
        do {
            let snapshots: [AccountBalanceSnapshot] = try await SupabaseManager.shared.client
                .from("account_balance_snapshots").select()
                .eq("account_id", value: account.id.uuidString)
                .order("snapshot_date", ascending: true).execute().value
            balanceHistory = snapshots
        } catch { print("❌ Balance history: \(error)") }
    }
    
    private func fmtCurrency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = account.currency; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var convertedBalanceText: String? {
        CurrencyConverter.shared.convertedDisplayText(account.currentBalance, from: account.currency)
    }
    
    private func fmtCompact(_ value: Double) -> String {
        let s = DS.Format.currencySymbol(); let a = abs(value)
        if a >= 1_000_000 { return String(format: "%@%.1fM", s, value / 1_000_000) }
        if a >= 1_000 { return String(format: "%@%.0fK", s, value / 1_000) }
        return String(format: "%@%.0f", s, value)
    }
}
