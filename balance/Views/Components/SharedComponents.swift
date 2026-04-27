import SwiftUI

// MARK: - Category Total Row

struct CategoryTotalRow: View {
    let category: Category
    let spent: Int

    var body: some View {
        HStack {
            Text(category.title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.text)
            Spacer()
            Text(DS.Format.money(spent))
                .font(DS.Typography.number)
                .foregroundStyle(DS.Colors.text)
        }
        .padding(12)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Category Cap Row

struct CategoryCapRow: View {
    let category: Category
    let spent: Int
    let cap: Int

    private var usedRatioRaw: Double {
        cap > 0 ? Double(spent) / Double(cap) : 0
    }

    private var barRatio: Double {
        min(1, max(0, usedRatioRaw))
    }

    private var levelColor: Color {
        if usedRatioRaw >= 1.0 { return DS.Colors.danger }
        if usedRatioRaw >= 0.90 { return DS.Colors.warning }
        return DS.Colors.positive
    }

    var body: some View {
        let remaining = cap - spent

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(category.title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.text)

                Spacer()

                Text(DS.Format.money(spent))
                    .font(DS.Typography.number)
                    .foregroundStyle(DS.Colors.text)
            }

            HStack {
                Text("Category cap")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                Spacer()

                Text("\(DS.Format.percent(usedRatioRaw)) used")
                    .font(DS.Typography.caption)
                    .foregroundStyle(usedRatioRaw >= 0.90 ? levelColor : DS.Colors.subtext)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Colors.surface)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [DS.Colors.surface2, levelColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * barRatio)
                        .animation(.spring(response: 0.45, dampingFraction: 0.9), value: barRatio)
                }
            }
            .frame(height: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(levelColor.opacity(0.3), lineWidth: 1)
            )

            HStack {
                Text("Cap: \(DS.Format.money(cap))")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                Spacer()

                if remaining >= 0 {
                    Text("Remaining: \(DS.Format.money(remaining))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                } else {
                    Text("Over: \(DS.Format.money(abs(remaining)))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.danger)
                }
            }
        }
        .padding(12)
        .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - KPI

struct KPI: View {
    let title: String
    let value: String
    var isNegative: Bool = false
    var isPositive: Bool = false

    var body: some View {
        DS.Card(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                Text(value)
                    .font(DS.Typography.number)
                    .foregroundStyle(
                        isNegative ? DS.Colors.danger :
                        isPositive ? DS.Colors.positive :
                        DS.Colors.text
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isNegative ? DS.Colors.danger.opacity(0.5) :
                    isPositive ? DS.Colors.positive.opacity(0.4) :
                    Color.clear,
                    lineWidth: 2
                )
        )
    }
}

// MARK: - Transaction Row

struct TransactionRow: View {
    let t: Transaction

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                if t.type == .income {
                    Circle()
                        .fill(DS.Colors.positive.opacity(0.12))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(DS.Colors.positive)
                                .font(.system(size: 16, weight: .semibold))
                        )
                } else {
                    Circle()
                        .fill(CategoryRegistry.shared.tint(for: t.category).opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay(
                            categoryIcon
                        )
                }

                if t.attachmentData != nil || t.attachmentType != nil {
                    Circle()
                        .fill(DS.Colors.surface2)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "paperclip")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Colors.subtext)
                        )
                        .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(t.type == .income ? "Income" : t.category.title)
                        .font(DS.Typography.body)
                        .foregroundStyle(t.type == .income ? .green : DS.Colors.text)

                    Image(systemName: t.paymentMethod.icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(t.paymentMethod.tint)
                        .padding(3)
                        .background(
                            Circle()
                                .fill(t.paymentMethod.tint.opacity(0.15))
                        )

                    if HouseholdManager.shared.isSplitTransaction(t.id) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .padding(3)
                            .background(
                                Circle()
                                    .fill(DS.Colors.accent.opacity(0.12))
                            )
                    }

                    if t.isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Colors.warning)
                            .padding(3)
                            .background(
                                Circle()
                                    .fill(DS.Colors.warning.opacity(0.12))
                            )
                    }

                    if t.attachmentData != nil {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }

                Text(t.note.isEmpty ? "\u{2014}" : t.note)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .lineLimit(1)
            }

            Spacer()

            Text(
                t.type == .expense ?
                AttributedString("-") + DS.Format.moneyAttributed(t.amount) :
                AttributedString("+") + DS.Format.moneyAttributed(t.amount)
            )
            .font(DS.Typography.number)
            .foregroundStyle(t.type == .income ? DS.Colors.positive : DS.Colors.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(t.isFlagged ? DS.Colors.warning.opacity(0.06) : t.type == .income ? DS.Colors.positive.opacity(0.04) : DS.Colors.surface)
        )
        .shadow(color: t.isFlagged ? DS.Colors.warning.opacity(0.10) : .black.opacity(0.04), radius: 8, x: 0, y: 3)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryIcon: some View {
        Image(systemName: CategoryRegistry.shared.icon(for: t.category))
            .foregroundStyle(CategoryRegistry.shared.tint(for: t.category))
            .font(.system(size: 14, weight: .semibold))
    }
}
