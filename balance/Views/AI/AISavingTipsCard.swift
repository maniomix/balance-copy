import SwiftUI

// ============================================================
// MARK: - AI Saving Tips Card
// ============================================================
//
// Rich grid card shown when the AI returns advice or spending
// analysis. Displays per-category spending, budget comparison,
// progress bars, and AI-generated tips.
//
// ============================================================

struct AISavingTipsCard: View {
    let title: String
    let entries: [CategoryEntry]

    @Environment(\.colorScheme) private var colorScheme

    struct CategoryEntry: Identifiable {
        let id = UUID()
        let category: Category
        let spentCents: Int
        let budgetCents: Int        // 0 = no budget set
        let tip: String
        let customIcon: String?     // override icon for custom categories
        let customColor: Color?     // override color for custom categories
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // ── Header ──
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Colors.text)
                Spacer()
                HStack(spacing: 4) {
                    Text("Centmond AI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                    Image(systemName: "sparkle")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Colors.accent)
                }
            }

            // ── Category Grid ──
            let columns = [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ]

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(entries) { entry in
                    categoryCard(entry)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DS.Colors.accent.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Category Card

    private func categoryCard(_ entry: CategoryEntry) -> some View {
        let icon = entry.customIcon ?? CategoryRegistry.shared.icon(for: entry.category)
        let color = entry.customColor ?? CategoryRegistry.shared.tint(for: entry.category)
        let isOverBudget = entry.budgetCents > 0 && entry.spentCents > entry.budgetCents
        let statusColor: Color = {
            guard entry.budgetCents > 0 else { return color }
            let ratio = Double(entry.spentCents) / Double(entry.budgetCents)
            if ratio > 1.0 { return DS.Colors.danger }
            if ratio > 0.8 { return DS.Colors.warning }
            return DS.Colors.positive
        }()

        return VStack(alignment: .leading, spacing: 6) {
            // Row 1: Icon + Name + Status dot
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(entry.category.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 2)
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            // Row 2: Amount + budget
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(fmtCents(entry.spentCents))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isOverBudget ? DS.Colors.danger : color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if entry.budgetCents > 0 {
                    Text("/ \(fmtCentsShort(entry.budgetCents))")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }

            // Row 3: Progress bar
            progressBar(spent: entry.spentCents, budget: entry.budgetCents, color: color, statusColor: statusColor)

            // Row 4: Tip text (fixed 2-line area for consistent card height)
            Text(entry.tip.isEmpty ? " " : entry.tip)
                .font(.system(size: 11))
                .foregroundStyle(entry.tip.isEmpty ? .clear : DS.Colors.subtext)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 28)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(colorScheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Progress Bar

    private func progressBar(spent: Int, budget: Int, color: Color, statusColor: Color) -> some View {
        GeometryReader { geo in
            let ratio: CGFloat = budget > 0
                ? min(CGFloat(spent) / CGFloat(budget), 1.0)
                : 0.65  // decorative bar if no budget
            let barColor = budget > 0 ? statusColor : color

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor.opacity(0.15))
                    .frame(height: 5)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor)
                    .frame(width: geo.size.width * ratio, height: 5)
            }
        }
        .frame(height: 5)
    }

    // MARK: - Formatting

    private func fmtCents(_ cents: Int) -> String {
        let d = Double(cents) / 100.0
        if d >= 1000 {
            return String(format: "$%.0f", d)
        }
        if d == d.rounded() && d >= 1 {
            return String(format: "$%.0f", d)
        }
        return String(format: "$%.2f", d)
    }

    private func fmtCentsShort(_ cents: Int) -> String {
        let d = Double(cents) / 100.0
        if d >= 1000 {
            return String(format: "$%.0fk", d / 1000)
        }
        return String(format: "$%.0f", d)
    }
}

// ============================================================
// MARK: - Factory: Build from Store + AI Text
// ============================================================

extension AISavingTipsCard {
    /// Build a saving tips card from the current store data and optional AI tips text.
    /// `tipsText` is the AI's analysisText — we try to match tips to categories.
    static func build(
        store: Store,
        title: String = "Saving Tips",
        tipsText: String? = nil,
        topN: Int = 6
    ) -> AISavingTipsCard? {
        let cal = Calendar.current
        let month = store.selectedMonth

        // Gather spending per category for current month
        let monthExpenses = store.transactions.filter {
            cal.isDate($0.date, equalTo: month, toGranularity: .month) && $0.type == .expense && !$0.isTransfer
        }

        var spendingByCategory: [String: Int] = [:]
        for tx in monthExpenses {
            let key = tx.category.storageKey
            spendingByCategory[key, default: 0] += tx.amount
        }

        guard !spendingByCategory.isEmpty else { return nil }

        // Sort by spending (highest first) and take top N
        let sorted = spendingByCategory.sorted { $0.value > $1.value }.prefix(topN)

        // Parse AI tips text into per-category tips
        let parsedTips = parseTips(from: tipsText, categories: sorted.map { $0.key })

        // Build entries
        var entries: [CategoryEntry] = []
        for (key, spent) in sorted {
            guard let cat = Category(storageKey: key) else { continue }
            let budget = store.categoryBudget(for: cat, month: month)
            let tip = parsedTips[key] ?? ""

            // Get custom icon/color if applicable
            var customIcon: String? = nil
            var customColor: Color? = nil
            if case .custom(let name) = cat,
               let customModel = store.customCategoriesWithIcons.first(where: { $0.name == name }) {
                customIcon = customModel.icon
                customColor = customModel.color
            }

            entries.append(CategoryEntry(
                category: cat,
                spentCents: spent,
                budgetCents: budget,
                tip: tip,
                customIcon: customIcon,
                customColor: customColor
            ))
        }

        guard !entries.isEmpty else { return nil }
        return AISavingTipsCard(title: title, entries: entries)
    }

    /// Extract per-category tips from AI analysis text.
    /// Splits text into paragraphs/sections and matches each to at most one category.
    private static func parseTips(from text: String?, categories: [String]) -> [String: String] {
        guard let text = text, !text.isEmpty else { return [:] }
        var result: [String: String] = [:]

        // Build category name lookup
        let catNames: [(key: String, name: String)] = categories.compactMap { key in
            guard let cat = Category(storageKey: key) else { return nil }
            return (key, cat.title.lowercased())
        }

        // Split into paragraphs (double newline) then sentences
        let paragraphs = text.components(separatedBy: "\n\n")
        for para in paragraphs {
            let sentences = para.components(separatedBy: "\n")
                .flatMap { line -> [String] in
                    // Split "sentence. Next sentence" but keep as-is if it's a bullet
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*") {
                        return [trimmed]
                    }
                    return trimmed.components(separatedBy: ". ").map {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .filter { !$0.isEmpty }

            for sentence in sentences {
                let lower = sentence.lowercased()

                // Find which category this sentence is about (first match wins)
                for (key, name) in catNames {
                    guard result[key] == nil else { continue }  // already have a tip for this category
                    guard lower.contains(name) else { continue }

                    // Extract a clean tip
                    var tip = sentence
                    // Remove markdown bullets
                    tip = tip.replacingOccurrences(of: "^[-•*]\\s*", with: "", options: .regularExpression)
                    // Remove markdown bold markers
                    tip = tip.replacingOccurrences(of: "**", with: "")
                    // Remove "CategoryName: " prefix
                    if let colonRange = tip.range(of: ":") {
                        let before = tip[tip.startIndex..<colonRange.lowerBound]
                            .trimmingCharacters(in: .whitespaces).lowercased()
                        if before == name || before.hasSuffix(name) {
                            tip = String(tip[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        }
                    }
                    tip = tip.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Only use meaningful tips — skip raw data repeats
                    let lowerTip = tip.lowercased()
                    let isJustData = lowerTip.hasPrefix("spending") && lowerTip.contains("$")
                        && !lowerTip.contains("try") && !lowerTip.contains("reduce")
                        && !lowerTip.contains("consider") && !lowerTip.contains("save")
                    if tip.count > 15 && !isJustData {
                        // Cap length for card display
                        if tip.count > 100 {
                            tip = String(tip.prefix(97)) + "…"
                        }
                        result[key] = tip
                        break  // This sentence belongs to this category, move to next sentence
                    }
                }
            }
        }

        return result
    }
}
