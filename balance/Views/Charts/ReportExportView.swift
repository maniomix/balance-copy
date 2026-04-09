import SwiftUI

// ============================================================
// MARK: - Report Export View
// ============================================================
//
// Full-featured report export flow:
//   1. Choose report type
//   2. Choose date range
//   3. Generate PDF
//   4. Share via iOS share sheet
// ============================================================

struct ReportExportView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ReportType = .monthlySummary
    @State private var startDate: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
    }()
    @State private var endDate: Date = Date()
    @State private var isGenerating = false
    @State private var shareURL: URL? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        reportTypePicker
                        dateRangeSection
                        reportPreview
                        generateButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Export Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            .sheet(item: $shareURL) { url in
                ShareSheetWrapper(items: [url])
                    .ignoresSafeArea()
            }
            .trackScreen("export_report")
            .alert("Export Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Report Type Picker

    private var reportTypePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Report Type")
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)

            VStack(spacing: 8) {
                ForEach(ReportType.allCases) { type in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            selectedType = type
                            adjustDatesForType(type)
                        }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedType == type ? DS.Colors.accent.opacity(0.15) : DS.Colors.surface2)
                                    .frame(width: 40, height: 40)

                                Image(systemName: type.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(selectedType == type ? DS.Colors.accent : DS.Colors.subtext)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(type.displayName)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)

                                Text(type.description)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if selectedType == type {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(DS.Colors.accent)
                            }
                        }
                        .padding(10)
                        .background(
                            selectedType == type ? DS.Colors.accent.opacity(0.05) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    selectedType == type ? DS.Colors.accent.opacity(0.3) : DS.Colors.grid.opacity(0.3),
                                    lineWidth: selectedType == type ? 1.5 : 0.5
                                )
                        )
                    }
                }
            }
        }
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Date Range")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if selectedType == .netWorth {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Colors.accent)
                        Text("Net worth report uses current balances")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                } else {
                    // Quick presets
                    HStack(spacing: 8) {
                        datePreset("This Month", preset: .thisMonth)
                        datePreset("Last Month", preset: .lastMonth)
                        datePreset("Last 3 Months", preset: .last3Months)
                        if selectedType == .annualSummary {
                            datePreset("This Year", preset: .thisYear)
                        }
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("From")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                            DatePicker("", selection: $startDate, displayedComponents: .date)
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("To")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                            DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }

    private enum DatePreset {
        case thisMonth, lastMonth, last3Months, thisYear
    }

    private func datePreset(_ label: String, preset: DatePreset) -> some View {
        Button {
            let cal = Calendar.current
            switch preset {
            case .thisMonth:
                startDate = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
                endDate = Date()
            case .lastMonth:
                let firstOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
                startDate = cal.date(byAdding: .month, value: -1, to: firstOfThisMonth)!
                endDate = cal.date(byAdding: .day, value: -1, to: firstOfThisMonth)!
            case .last3Months:
                startDate = cal.date(byAdding: .month, value: -3, to: Date())!
                endDate = Date()
            case .thisYear:
                var comps = cal.dateComponents([.year], from: Date())
                comps.month = 1
                comps.day = 1
                startDate = cal.date(from: comps)!
                endDate = Date()
            }
            Haptics.light()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(DS.Colors.accent.opacity(0.1), in: Capsule())
        }
    }

    // MARK: - Preview

    private var reportPreview: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("Report Preview")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 14) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(DS.Colors.accent.opacity(0.6))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedType.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)

                        Text(previewDescription)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)

                        let txCount = relevantTransactionCount
                        Text("\(txCount) transaction\(txCount == 1 ? "" : "s") in range")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    private var previewDescription: String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "MMM d, yyyy"
        if selectedType == .netWorth {
            return "As of \(dateFmt.string(from: Date()))"
        }
        return "\(dateFmt.string(from: startDate)) – \(dateFmt.string(from: endDate))"
    }

    private var relevantTransactionCount: Int {
        if selectedType == .netWorth { return 0 }
        return store.transactions.filter { $0.date >= startDate && $0.date <= endDate }.count
    }

    // MARK: - Generate Button

    private var generateButton: some View {
        Button {
            generateReport()
        } label: {
            HStack(spacing: 10) {
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isGenerating ? "Generating…" : "Generate & Share PDF")
            }
        }
        .buttonStyle(DS.PrimaryButton())
        .disabled(isGenerating)
        .opacity(isGenerating ? 0.7 : 1)
    }

    // MARK: - Generation

    private func generateReport() {
        isGenerating = true
        Haptics.medium()

        // Capture everything on MainActor before detaching
        let reportType = selectedType
        let reportStore = store
        let reportStart = startDate
        let reportEnd = endDate
        let accounts = AccountManager.shared.accounts
        let netWorth = AccountManager.shared.netWorth

        Task.detached(priority: .userInitiated) {
            let data = PDFReportGenerator.generate(
                type: reportType,
                store: reportStore,
                startDate: reportStart,
                endDate: reportEnd,
                accounts: accounts,
                netWorth: netWorth
            )

            let dateFmt = DateFormatter()
            dateFmt.dateFormat = "yyyy-MM-dd"
            let filename = "Centmond_\(reportType.displayName.replacingOccurrences(of: " ", with: "_"))_\(dateFmt.string(from: reportStart)).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

            do {
                try data.write(to: url, options: .atomic)

                await MainActor.run {
                    isGenerating = false
                    shareURL = url
                    Haptics.success()
                    AnalyticsManager.shared.track(.exportUsed(format: "pdf_report"))
                }
            } catch {
                await MainActor.run {
                    isGenerating = false
                    errorMessage = AppConfig.shared.safeErrorMessage(
                        detail: "Failed to save PDF: \(error.localizedDescription)",
                        fallback: "Failed to save PDF. Please try again."
                    )
                    Haptics.error()
                }
            }
        }
    }

    // MARK: - Helpers

    private func adjustDatesForType(_ type: ReportType) {
        let cal = Calendar.current
        switch type {
        case .monthlySummary:
            startDate = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
            endDate = Date()
        case .annualSummary:
            var comps = cal.dateComponents([.year], from: Date())
            comps.month = 1; comps.day = 1
            startDate = cal.date(from: comps)!
            endDate = Date()
        case .categorySpending, .cashFlow:
            startDate = cal.date(byAdding: .month, value: -3, to: Date())!
            endDate = Date()
        case .netWorth:
            break // no date range needed
        }
    }
}

// MARK: - Share Sheet Wrapper

private struct ShareSheetWrapper: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
