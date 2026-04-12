import SwiftUI

// ============================================================
// MARK: - AI Scenario View
// ============================================================

struct AIScenarioView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = AIScenarioEngine.shared

    @State private var selectedScenario: ScenarioType = .saveMore
    @State private var amount: String = "100"
    @State private var categoryName: String = "Dining"
    @State private var cutPercent: Double = 20

    enum ScenarioType: String, CaseIterable, Identifiable {
        case saveMore = "Save More"
        case cutCategory = "Cut Category"
        case changeBudget = "Change Budget"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .saveMore: return "arrow.up.circle.fill"
            case .cutCategory: return "scissors"
            case .changeBudget: return "chart.pie.fill"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Scenario type picker
                    Picker("Scenario", selection: $selectedScenario) {
                        ForEach(ScenarioType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Input fields
                    DS.Card {
                        VStack(alignment: .leading, spacing: 12) {
                            inputFields
                            runButton
                        }
                    }

                    // Results
                    if let result = engine.lastResult {
                        resultsView(result)
                    }
                }
                .padding()
            }
            .background(DS.Colors.bg)
            .navigationTitle("What If...?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    // MARK: - Input Fields

    @ViewBuilder
    private var inputFields: some View {
        switch selectedScenario {
        case .saveMore:
            VStack(alignment: .leading, spacing: 4) {
                Text("How much more per month?")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                HStack {
                    Text("$")
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("100", text: $amount)
                        .keyboardType(.numberPad)
                        .font(DS.Typography.title)
                }
            }

        case .cutCategory:
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Category")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("Dining", text: $categoryName)
                        .font(DS.Typography.body)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cut by \(Int(cutPercent))%")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Slider(value: $cutPercent, in: 10...50, step: 5)
                        .tint(DS.Colors.accent)
                }
            }

        case .changeBudget:
            VStack(alignment: .leading, spacing: 4) {
                Text("New monthly budget")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                HStack {
                    Text("$")
                        .foregroundStyle(DS.Colors.subtext)
                    TextField("2000", text: $amount)
                        .keyboardType(.numberPad)
                        .font(DS.Typography.title)
                }
            }
        }
    }

    // MARK: - Run Button

    private var runButton: some View {
        Button {
            runScenario()
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text("Simulate")
            }
            .font(DS.Typography.callout)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Results

    private func resultsView(_ result: ScenarioResult) -> some View {
        VStack(spacing: 12) {
            DS.Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: selectedScenario.icon)
                            .foregroundStyle(DS.Colors.accent)
                        Text(result.title)
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                    }

                    ForEach(result.impacts) { impact in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(impact.area)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                                HStack(spacing: 8) {
                                    Text(impact.currentValue)
                                        .font(DS.Typography.body)
                                        .foregroundStyle(DS.Colors.text)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.Colors.subtext)
                                    Text(impact.projectedValue)
                                        .font(DS.Typography.body)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(impact.isPositive ? DS.Colors.positive : DS.Colors.danger)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            // Recommendation
            DS.Card {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(DS.Colors.warning)
                    Text(result.recommendation)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.text)
                }
            }
        }
    }

    // MARK: - Actions

    private func runScenario() {
        let cents = Int((Double(amount) ?? 0) * 100)

        switch selectedScenario {
        case .saveMore:
            _ = engine.simulateSaveMore(amount: cents, store: store)
        case .cutCategory:
            _ = engine.simulateCutCategory(category: categoryName, percentCut: Int(cutPercent), store: store)
        case .changeBudget:
            _ = engine.simulateBudgetChange(newBudget: cents, store: store)
        }
    }
}
