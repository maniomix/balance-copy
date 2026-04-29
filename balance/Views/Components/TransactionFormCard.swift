import SwiftUI

// MARK: - Insight Row

struct InsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(insight.level.color.opacity(0.18))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: insight.level.icon)
                        .foregroundStyle(insight.level.color)
                        .font(.system(size: 14, weight: .semibold))
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(insight.title)
                    .font(DS.Typography.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(insight.detail)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Month Picker

struct MonthPicker: View {
    @Binding var selectedMonth: Date
    @State private var showMonthYearPicker = false

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.monthChanged()
                selectedMonth = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
                AnalyticsManager.shared.track(.monthSwitched)
            } label: {
                Image(systemName: "chevron.left")
                    .foregroundStyle(DS.Colors.subtext)
                    .padding(8)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                Haptics.soft()
                selectedMonth = Date()
                AnalyticsManager.shared.track(.monthSwitched)
            } label: {
                Text("This month")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        Haptics.medium()
                        showMonthYearPicker = true
                    }
            )

            Button {
                Haptics.monthChanged()
                selectedMonth = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) ?? selectedMonth
                AnalyticsManager.shared.track(.monthSwitched)
            } label: {
                Image(systemName: "chevron.right")
                    .foregroundStyle(DS.Colors.subtext)
                    .padding(8)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .sheet(isPresented: $showMonthYearPicker) {
            MonthYearPickerSheet(selectedDate: $selectedMonth)
        }
    }
}

