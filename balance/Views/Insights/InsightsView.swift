import SwiftUI
import UserNotifications

// MARK: - Insights

struct InsightsView: View {
    @Binding var store: Store
    let goToBudget: () -> Void

    @State private var showAdvancedCharts: Bool = false

    @AppStorage("notifications.enabled") private var notificationsEnabled: Bool = false

    @State private var shareURL: URL? = nil
    @State private var showReportExport = false
    @State private var showAIChat = false
    @State private var exportError: String? = nil
    @State private var selectedInsight: AIInsight? = nil
    @StateObject private var insightEngine = AIInsightEngine.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if store.budgetTotal <= 0 {
                        InsightsEmptyCard(state: .noBudget, onCTA: goToBudget)
                    } else if Analytics.monthTransactions(store: store).isEmpty {
                        InsightsEmptyCard(state: .noData, onCTA: goToBudget)
                    } else {
                        // MARK: This month
                        DS.SectionHeader(title: "This month", icon: "calendar")
                            .padding(.horizontal, 4)

                        UnderstandingCard(store: store)

                        QuickActionsCard(store: store)

                        // MARK: AI Advisor
                        if !insightEngine.insights.isEmpty {
                            DS.SectionHeader(title: "AI Advisor", icon: "sparkles")
                                .padding(.horizontal, 4)
                                .padding(.top, 4)

                            AIInsightsSectionCard(
                                insights: insightEngine.insights,
                                onAskAI: { showAIChat = true },
                                onSelect: { selectedInsight = $0 }
                            )
                        }

                        // MARK: Tools
                        DS.SectionHeader(title: "Tools", icon: "wrench.and.screwdriver")
                            .padding(.horizontal, 4)
                            .padding(.top, 4)

                        AnalyticsEntryCard(
                            onOpen: { showAdvancedCharts = true }
                        )

                        ExportCard(
                            onExcel: { exportMonth(format: .excel) },
                            onCSV: { exportMonth(format: .csv) },
                            onPDF: { showReportExport = true }
                        )

                        if let exportError {
                            Text(exportError)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .navigationTitle("Insights")
            .onAppear {
                insightEngine.refresh(store: store)
            }
            .onChange(of: store) { _, _ in
                guard notificationsEnabled else { return }
                Task { await Notifications.evaluateSmartRules(store: store) }
            }
            .sheet(item: $shareURL) { url in
                ShareSheet(items: [url])
                    .ignoresSafeArea()
            }
            .sheet(isPresented: $showAdvancedCharts) {
                AdvancedChartsView(store: $store)
            }
            .sheet(isPresented: $showReportExport) {
                ReportExportView(store: $store)
            }
            .sheet(isPresented: $showAIChat) {
                AIChatView(store: $store)
            }
            .sheet(item: $selectedInsight) { insight in
                AIInsightDetailSheet(insight: insight)
            }
        }
    }

    private func exportMonth(format: InsightsExportFormat) {
        do {
            let url = try InsightsExporter.exportMonth(store: store, format: format)
            Haptics.exportSuccess()
            AnalyticsManager.shared.track(.exportUsed(format: format.fileExtension))
            self.shareURL = url
        } catch {
            Haptics.error()
            self.exportError = AppConfig.shared.safeErrorMessage(
                detail: "Export failed: \(error.localizedDescription)",
                fallback: "Export failed. Please try again."
            )
        }
    }
}

// MARK: - Helper Views

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
