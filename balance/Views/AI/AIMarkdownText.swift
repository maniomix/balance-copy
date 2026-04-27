import SwiftUI
import Flow

// ============================================================
// MARK: - AI Markdown Text
// ============================================================
//
// Rich text renderer for AI chat responses.
// Parses markdown into styled blocks: headers, bullets, numbers,
// code blocks, dividers — with colored $amounts, %percentages,
// and inline **bold** / *italic* / `code`.
//
// ============================================================

struct AIMarkdownText: View {
    let text: String
    let role: AIMessage.Role
    @Environment(\.colorScheme) private var colorScheme

    private var isUser: Bool { role == .user }

    var body: some View {
        let blocks = parseBlocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                blockView(block, index: idx, total: blocks.count)
            }
        }
    }

    // MARK: - Block Views

    @ViewBuilder
    private func blockView(_ block: Block, index: Int, total: Int) -> some View {
        switch block {
        case .paragraph(let text):
            styledText(text)
                .padding(.bottom, 4)

        case .bullet(let text):
            bulletView(text)

        case .numbered(let num, let text):
            HStack(alignment: .top, spacing: 8) {
                Text("\(num)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(isUser ? .white.opacity(0.8) : DS.Colors.accent)
                    .frame(width: 20, height: 20)
                    .background(
                        Circle()
                            .fill(isUser ? .white.opacity(0.15) : DS.Colors.accent.opacity(0.15))
                    )
                    .padding(.top, 2)
                styledText(text)
            }
            .padding(.leading, 2)
            .padding(.vertical, 4)

        case .header(let text):
            headerView(text)

        case .tipHeader(let title, let body):
            tipHeaderView(title: title, body: body)

        case .divider:
            Rectangle()
                .fill(isUser ? .white.opacity(0.2) : DS.Colors.subtext.opacity(0.2))
                .frame(height: 1)
                .padding(.vertical, 6)

        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(isUser ? .white.opacity(0.9) : DS.Colors.text.opacity(0.9))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isUser
                              ? Color.white.opacity(0.1)
                              : (colorScheme == .dark
                                 ? Color.white.opacity(0.06)
                                 : Color.black.opacity(0.04)))
                )
                .padding(.vertical, 2)

        case .spacer:
            Spacer().frame(height: 4)
        }
    }

    // MARK: - Header View

    private func headerView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isUser ? .white : DS.Colors.text)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Tip/Section Header with Body (e.g. "**Dining Out Reduction**: You spent...")

    private func tipHeaderView(title: String, body: String) -> some View {
        // Strip leading bullet from title if present (added upstream by bullet parser)
        let cleanedTitle = title
            .replacingOccurrences(of: "^[•\\-*]\\s*", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)

        return HStack(alignment: .top, spacing: 10) {
            // Accent bar — visual anchor on the left
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(isUser ? Color.white.opacity(0.5) : DS.Colors.accent)
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                // Title — colored, bold, prominent
                if let catMatch = matchCategory(cleanedTitle) {
                    HStack(spacing: 6) {
                        Image(systemName: catMatch.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(catMatch.title)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(catMatch.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(catMatch.tint.opacity(0.15))
                    )
                } else {
                    Text(cleanedTitle)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(isUser ? .white : DS.Colors.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Body — indented under title with breathing room
                styledText(body)
            }
        }
        .padding(.vertical, 6)
    }

    /// Match a title string against known categories.
    /// Strips leading "• " and checks both title and storageKey.
    /// Phase 5: also matches user-defined custom categories from `CategoryRegistry`.
    private func matchCategory(_ title: String) -> Category? {
        let cleaned = title
            .replacingOccurrences(of: "•", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // Custom first — user-defined names take precedence over built-in synonyms
        for name in CategoryRegistry.shared.customNames {
            if cleaned == name.lowercased() { return .custom(name) }
        }
        for cat in Category.allCases {
            if cleaned == cat.title.lowercased() || cleaned == cat.storageKey {
                return cat
            }
        }
        // Partial match (e.g. "Dining Out" → .dining, "Coffee Shop" → custom Coffee)
        for name in CategoryRegistry.shared.customNames {
            if cleaned.hasPrefix(name.lowercased()) { return .custom(name) }
        }
        for cat in Category.allCases {
            if cleaned.hasPrefix(cat.title.lowercased()) {
                return cat
            }
        }
        return nil
    }

    // MARK: - Bullet View (with optional category capsule)

    private func bulletView(_ text: String) -> some View {
        // Check if bullet text starts with a category name (e.g. "Dining: ..." or "Shopping — ...")
        let catAndBody = extractCategoryFromBullet(text)

        return Group {
            if let (cat, body) = catAndBody {
                let catIcon = CategoryRegistry.shared.icon(for: cat)
                let catTint = CategoryRegistry.shared.tint(for: cat)
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: catIcon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(cat.title)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(catTint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(catTint.opacity(0.15))
                    )
                    .padding(.top, 1)
                }
                .padding(.leading, 4)
                .padding(.vertical, 2)

                if !body.isEmpty {
                    styledText(body)
                        .padding(.leading, 12)
                        .padding(.bottom, 4)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(isUser ? .white.opacity(0.7) : DS.Colors.accent)
                        .frame(width: 6, height: 6)
                        .padding(.top, 7)
                    styledText(text)
                }
                .padding(.leading, 4)
                .padding(.vertical, 4)
            }
        }
    }

    /// Try to extract a category name from the beginning of bullet text.
    /// Handles patterns like "Dining: ...", "Groceries — ...", "Shopping ..."
    /// Phase 5: tries user-defined customs first so longer custom names like
    /// "Coffee Shops" win over the prefix-match against "Coffee" mapped to
    /// dining via aliases.
    private func extractCategoryFromBullet(_ text: String) -> (Category, String)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)

        // Custom names first (sorted longest-first so "Coffee Shop" wins over "Coffee")
        let customs = CategoryRegistry.shared.customNames
            .sorted { $0.count > $1.count }
        for name in customs {
            if trimmed.lowercased().hasPrefix(name.lowercased()) {
                let afterCat = String(trimmed.dropFirst(name.count))
                    .trimmingCharacters(in: .whitespaces)
                if afterCat.isEmpty ||
                   afterCat.hasPrefix(":") || afterCat.hasPrefix("—") ||
                   afterCat.hasPrefix("-") || afterCat.hasPrefix(",") {
                    let body = afterCat
                        .replacingOccurrences(of: "^[:—\\-,]\\s*", with: "", options: .regularExpression)
                    return (.custom(name), body)
                }
            }
        }

        for cat in Category.allCases {
            let catName = cat.title
            if trimmed.lowercased().hasPrefix(catName.lowercased()) {
                let afterCat = String(trimmed.dropFirst(catName.count)).trimmingCharacters(in: .whitespaces)
                // Must be followed by separator (: — - ,) or end
                if afterCat.isEmpty ||
                   afterCat.hasPrefix(":") || afterCat.hasPrefix("—") ||
                   afterCat.hasPrefix("-") || afterCat.hasPrefix(",") {
                    let body = afterCat
                        .replacingOccurrences(of: "^[:—\\-,]\\s*", with: "", options: .regularExpression)
                    return (cat, body)
                }
            }
        }
        return nil
    }

    // MARK: - Inline Styled Text

    private func styledText(_ text: String) -> some View {
        let tokens = tokenizeInline(text)
        let hasCapsule = tokens.contains { token in
            if case .plain = token.kind { return false } else { return true }
        }
        return Group {
            if hasCapsule {
                HFlow(spacing: 4) {
                    ForEach(Array(tokens.enumerated()), id: \.offset) { _, t in
                        inlineTokenView(t)
                    }
                }
            } else {
                Text(parseInline(text))
                    .font(.system(size: 15))
                    .foregroundStyle(isUser ? .white : DS.Colors.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Inline Tokenization (for capsule rendering)

    private struct InlineTokenEntry {
        enum Kind {
            case plain(AttributedString)
            case amount(String)
            case percent(String)
            case category(Category)
        }
        let kind: Kind
        let leading: String
        let trailing: String
    }

    private func tokenizeInline(_ text: String) -> [InlineTokenEntry] {
        let stripSet: Set<Character> = ["(", ")", "[", "]", "{", "}", ",", ".", ";", ":", "\"", "'", "!", "?", "،", "؛"]
        // Split by whitespace, keep words
        let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var out: [InlineTokenEntry] = []
        for w in words {
            var core = w
            var leading = ""
            var trailing = ""
            while let f = core.first, stripSet.contains(f) {
                leading.append(f)
                core.removeFirst()
            }
            while let l = core.last, stripSet.contains(l) {
                trailing = String(l) + trailing
                core.removeLast()
            }
            // Strip surrounding ** for single-word bold; bold attribute is applied below
            var isBold = false
            if core.hasPrefix("**") && core.hasSuffix("**") && core.count > 4 {
                core = String(core.dropFirst(2).dropLast(2))
                isBold = true
            }

            if isPercentToken(core) {
                out.append(.init(kind: .percent(core), leading: leading, trailing: trailing))
            } else if isAmountToken(core) {
                out.append(.init(kind: .amount(core), leading: leading, trailing: trailing))
            } else if let cat = matchCategoryWord(core) {
                out.append(.init(kind: .category(cat), leading: leading, trailing: trailing))
            } else {
                // Regular word — reattach leading/trailing, run inline markdown parse
                let full = leading + (isBold ? "**\(core)**" : core) + trailing
                out.append(.init(kind: .plain(parseInline(full)), leading: "", trailing: ""))
            }
        }
        return out
    }

    private func isAmountToken(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        // Must contain a currency symbol (prefix or suffix) and digits
        let currencyChars: Set<Character> = ["$", "€", "£", "¥", "₽", "₺", "₹", "₩"]
        let hasCurrency = s.contains(where: { currencyChars.contains($0) })
        guard hasCurrency else { return false }
        let digits = s.filter { $0.isNumber }
        guard !digits.isEmpty else { return false }
        // Rest must be digits, currency, comma, dot, minus
        for c in s {
            if !(c.isNumber || currencyChars.contains(c) || c == "," || c == "." || c == "-") {
                return false
            }
        }
        return true
    }

    private func isPercentToken(_ s: String) -> Bool {
        guard s.hasSuffix("%"), s.count > 1 else { return false }
        let body = s.dropLast()
        for c in body {
            if !(c.isNumber || c == "." || c == "," || c == "-") { return false }
        }
        return body.contains(where: { $0.isNumber })
    }

    private func matchCategoryWord(_ s: String) -> Category? {
        let lower = s.lowercased()
        guard lower.count >= 4 else { return nil }
        // Phase 5: custom categories first so "Coffee" → .custom("Coffee")
        // not nothing (custom isn't in `Category.allCases`).
        for name in CategoryRegistry.shared.customNames {
            if lower == name.lowercased() { return .custom(name) }
        }
        for cat in Category.allCases {
            if case .other = cat { continue }  // "other" collides with common English
            if lower == cat.title.lowercased() || lower == cat.storageKey.lowercased() {
                return cat
            }
        }
        return nil
    }

    @ViewBuilder
    private func inlineTokenView(_ t: InlineTokenEntry) -> some View {
        HStack(spacing: 0) {
            if !t.leading.isEmpty {
                Text(t.leading)
                    .font(.system(size: 15))
                    .foregroundStyle(isUser ? .white : DS.Colors.text)
            }
            switch t.kind {
            case .plain(let attr):
                Text(attr)
                    .font(.system(size: 15))
                    .foregroundStyle(isUser ? .white : DS.Colors.text)
                    .lineSpacing(3)
            case .amount(let s):
                amountCapsule(s)
            case .percent(let s):
                percentCapsule(s)
            case .category(let cat):
                categoryCapsule(cat)
            }
            if !t.trailing.isEmpty {
                Text(t.trailing)
                    .font(.system(size: 15))
                    .foregroundStyle(isUser ? .white : DS.Colors.text)
            }
        }
    }

    private func amountCapsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(isUser ? .white : DS.Colors.positive)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((isUser ? Color.white : DS.Colors.positive).opacity(isUser ? 0.18 : 0.14))
            )
            .overlay(
                Capsule().stroke((isUser ? Color.white : DS.Colors.positive).opacity(isUser ? 0.28 : 0.22), lineWidth: 0.5)
            )
    }

    private func percentCapsule(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(isUser ? .white : DS.Colors.warning)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill((isUser ? Color.white : DS.Colors.warning).opacity(isUser ? 0.18 : 0.14))
            )
            .overlay(
                Capsule().stroke((isUser ? Color.white : DS.Colors.warning).opacity(isUser ? 0.28 : 0.22), lineWidth: 0.5)
            )
    }

    private func categoryCapsule(_ cat: Category) -> some View {
        let icon = CategoryRegistry.shared.icon(for: cat)
        let tint = CategoryRegistry.shared.tint(for: cat)
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(cat.title)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(isUser ? .white : tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(
            Capsule().fill((isUser ? Color.white : tint).opacity(isUser ? 0.18 : 0.15))
        )
    }

    // MARK: - Block Parsing

    private enum Block {
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case header(String)
        case tipHeader(title: String, body: String)
        case divider
        case codeBlock(String)
        case spacer
    }

    private func parseBlocks(_ text: String) -> [Block] {
        // Pre-clean: remove stray single dashes on their own line
        let cleaned = text.components(separatedBy: "\n").filter { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            if s == "-" || s == "–" || s == "—" || s == "*" || s == "•" { return false }
            return true
        }.joined(separator: "\n")

        let lines = cleaned.components(separatedBy: "\n")
        var blocks: [Block] = []
        var inCodeBlock = false
        var codeLines: [String] = []
        var paragraphBuffer = ""

        func flushParagraph() {
            let trimmed = paragraphBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.paragraph(trimmed))
            }
            paragraphBuffer = ""
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code block toggle
            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    flushParagraph()
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            // Divider (3+ repeated chars)
            if trimmed.count >= 3 && Set(trimmed).count == 1 && ["-", "=", "*", "─", "━"].contains(String(trimmed.first!)) {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // Header (## prefix)
            if let match = trimmed.range(of: "^#{1,3}\\s+", options: .regularExpression) {
                flushParagraph()
                let headerText = String(trimmed[match.upperBound...])
                blocks.append(.header(headerText))
                continue
            }

            // Bold-only line as header (e.g. "**Tips:**" or "**Saving Tips based on...**")
            if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && trimmed.count > 4 {
                let inner = String(trimmed.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                    .trimmingCharacters(in: .whitespaces)
                if inner.count < 60 {
                    flushParagraph()
                    blocks.append(.header(inner))
                    continue
                }
            }

            // Bold line ending with colon as header ("**Tips:**")
            if trimmed.hasPrefix("**"),
               let endBold = trimmed.range(of: "**", range: trimmed.index(trimmed.startIndex, offsetBy: 2)..<trimmed.endIndex) {
                let boldContent = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<endBold.lowerBound])
                let afterBold = String(trimmed[endBold.upperBound...]).trimmingCharacters(in: .whitespaces)

                // "**Title:** rest of text" → tipHeader
                if afterBold.hasPrefix(":") || boldContent.hasSuffix(":") {
                    flushParagraph()
                    let title = boldContent.trimmingCharacters(in: CharacterSet(charactersIn: ":")).trimmingCharacters(in: .whitespaces)
                    let body = afterBold.hasPrefix(":") ?
                        String(afterBold.dropFirst()).trimmingCharacters(in: .whitespaces) :
                        afterBold
                    if body.isEmpty {
                        blocks.append(.header(title))
                    } else {
                        blocks.append(.tipHeader(title: title, body: body))
                    }
                    continue
                }
            }

            // Bullet point (-, *, •) — but NOT a single dash alone
            if let match = trimmed.range(of: "^[-*•]\\s+", options: .regularExpression), trimmed.count > 2 {
                flushParagraph()
                let bulletText = String(trimmed[match.upperBound...])

                // Check if bullet starts with **bold**: pattern (tip format)
                if bulletText.hasPrefix("**"),
                   let endBold = bulletText.range(of: "**", range: bulletText.index(bulletText.startIndex, offsetBy: 2)..<bulletText.endIndex) {
                    let boldPart = String(bulletText[bulletText.index(bulletText.startIndex, offsetBy: 2)..<endBold.lowerBound])
                    let rest = String(bulletText[endBold.upperBound...]).trimmingCharacters(in: .whitespaces)
                    let cleanRest = rest.hasPrefix(":") ? String(rest.dropFirst()).trimmingCharacters(in: .whitespaces) : rest

                    if !cleanRest.isEmpty {
                        blocks.append(.bullet(""))  // marker for indent
                        blocks.removeLast()
                        // Render as tip with colored title
                        let tipBlock = Block.tipHeader(
                            title: "• " + boldPart.trimmingCharacters(in: CharacterSet(charactersIn: ":")),
                            body: cleanRest
                        )
                        blocks.append(tipBlock)
                        continue
                    }
                }

                blocks.append(.bullet(bulletText))
                continue
            }

            // Numbered list (1., 2., etc.)
            if let match = trimmed.range(of: "^(\\d+)\\.\\s+", options: .regularExpression) {
                flushParagraph()
                let numPart = trimmed[trimmed.startIndex..<match.upperBound]
                    .trimmingCharacters(in: .whitespaces)
                let num = Int(numPart.replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)) ?? 1
                let listText = String(trimmed[match.upperBound...])
                blocks.append(.numbered(num, listText))
                continue
            }

            // Empty line = paragraph break
            if trimmed.isEmpty {
                flushParagraph()
                blocks.append(.spacer)
                continue
            }

            // Regular text — accumulate into paragraph
            if !paragraphBuffer.isEmpty {
                paragraphBuffer += " "
            }
            paragraphBuffer += trimmed
        }

        // Flush remaining
        flushParagraph()
        if inCodeBlock && !codeLines.isEmpty {
            blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
        }

        // Remove trailing spacers
        while blocks.last.map({ if case .spacer = $0 { return true } else { return false } }) == true {
            blocks.removeLast()
        }

        return blocks
    }

    // MARK: - Inline Markdown Parsing

    private func parseInline(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // **bold**
            if remaining.hasPrefix("**") {
                let afterStars = remaining.index(remaining.startIndex, offsetBy: 2)
                if afterStars < remaining.endIndex,
                   let endRange = remaining[afterStars...].range(of: "**") {
                    let boldText = String(remaining[afterStars..<endRange.lowerBound])
                    var attr = AttributedString(boldText)
                    attr.font = .system(size: 15, weight: .bold)
                    if !isUser {
                        attr.foregroundColor = UIColor(DS.Colors.text)
                    }
                    result += attr
                    remaining = remaining[endRange.upperBound...]
                    continue
                }
            }

            // *italic*
            if remaining.hasPrefix("*") && !remaining.hasPrefix("**") {
                let afterStar = remaining.index(after: remaining.startIndex)
                if afterStar < remaining.endIndex,
                   let endRange = remaining[afterStar...].range(of: "*") {
                    let italicText = String(remaining[afterStar..<endRange.lowerBound])
                    var attr = AttributedString(italicText)
                    attr.font = .system(size: 15).italic()
                    result += attr
                    remaining = remaining[endRange.upperBound...]
                    continue
                }
            }

            // `code`
            if remaining.hasPrefix("`") && !remaining.hasPrefix("```") {
                let afterTick = remaining.index(after: remaining.startIndex)
                if afterTick < remaining.endIndex,
                   let endRange = remaining[afterTick...].range(of: "`") {
                    let codeText = String(remaining[afterTick..<endRange.lowerBound])
                    var attr = AttributedString(" \(codeText) ")
                    attr.font = .system(size: 13, weight: .medium, design: .monospaced)
                    attr.backgroundColor = isUser
                        ? UIColor.white.withAlphaComponent(0.15)
                        : UIColor(DS.Colors.accent.opacity(0.12))
                    if !isUser {
                        attr.foregroundColor = UIColor(DS.Colors.accent)
                    }
                    result += attr
                    remaining = remaining[endRange.upperBound...]
                    continue
                }
            }

            // $amount — colored + monospaced
            if remaining.hasPrefix("$") {
                var amountEnd = remaining.index(after: remaining.startIndex)
                while amountEnd < remaining.endIndex &&
                      (remaining[amountEnd].isNumber || remaining[amountEnd] == "." || remaining[amountEnd] == ",") {
                    amountEnd = remaining.index(after: amountEnd)
                }
                let amountStr = String(remaining[remaining.startIndex..<amountEnd])
                if amountStr.count > 1 {
                    var attr = AttributedString(amountStr)
                    attr.font = .system(size: 15, weight: .bold, design: .monospaced)
                    if !isUser {
                        attr.foregroundColor = UIColor(DS.Colors.positive)
                    }
                    result += attr
                    remaining = remaining[amountEnd...]
                    continue
                }
            }

            // Percentage — colored
            if remaining.first?.isNumber == true {
                var numEnd = remaining.startIndex
                while numEnd < remaining.endIndex &&
                      (remaining[numEnd].isNumber || remaining[numEnd] == ".") {
                    numEnd = remaining.index(after: numEnd)
                }
                if numEnd < remaining.endIndex && remaining[numEnd] == "%" {
                    let pctEnd = remaining.index(after: numEnd)
                    let pctStr = String(remaining[remaining.startIndex..<pctEnd])
                    var attr = AttributedString(pctStr)
                    attr.font = .system(size: 15, weight: .bold)
                    if !isUser {
                        attr.foregroundColor = UIColor(DS.Colors.warning)
                    }
                    result += attr
                    remaining = remaining[pctEnd...]
                    continue
                }
            }

            // Regular character
            result += AttributedString(String(remaining.first!))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
    }
}
