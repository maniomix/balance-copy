import Foundation

// ============================================================
// MARK: - AI Intent Router (Phase 1: Intent Layer)
// ============================================================
//
// Rule-based pre-LLM classifier. Runs BEFORE sending to Gemma.
//
// Key differences from v1:
//   - Scores ALL plausible interpretations, not just the first match
//   - Detects ambiguity when multiple intents are close in confidence
//   - Returns structured IntentClassification with clarification path
//   - Higher-level IntentType categories (not action-level)
//
// Pure regex/keyword — instant, offline, deterministic.
//
// ============================================================

enum AIIntentRouter {

    // MARK: - Public API

    /// Classify user input into an IntentClassification.
    static func classify(_ text: String) -> IntentClassification {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizePersianDigits(lower)
        let entities = extractEntities(normalized)
        let isMulti = detectMultiIntent(normalized)

        // Score all interpretations
        var interpretations = scoreAll(normalized, entities: entities)

        // Sort by confidence descending
        interpretations.sort { $0.confidence > $1.confidence }

        // If nothing matched, fall back
        if interpretations.isEmpty {
            interpretations = [Interpretation(
                intentType: .askQuestion, domain: .general,
                confidence: 0.2, reason: "No pattern matched"
            )]
        }

        let primary = interpretations[0]
        let secondary = interpretations.count > 1 ? interpretations[1] : nil

        // Determine ambiguity
        let ambiguityGap = primary.confidence - (secondary?.confidence ?? 0)
        let isAmbiguous = secondary != nil
            && ambiguityGap < 0.15
            && secondary!.confidence >= 0.4

        // Build clarification if ambiguous or too vague
        let clarification: ClarificationResult?
        if isAmbiguous {
            let topInterpretations = Array(interpretations.prefix(3))
            clarification = buildAmbiguityClarification(
                input: normalized, interpretations: topInterpretations, entities: entities
            )
        } else if primary.confidence < 0.4 {
            clarification = ClarificationResult(
                question: "I'm not sure what you'd like to do. Could you be more specific?",
                interpretations: Array(interpretations.prefix(3)),
                missingFields: ["intent"]
            )
        } else {
            clarification = nil
        }

        let contextHint = resolveContextHint(primary: primary, secondary: secondary)

        return IntentClassification(
            primary: primary,
            secondary: secondary,
            allInterpretations: interpretations,
            clarificationNeeded: clarification != nil,
            clarification: clarification,
            extractedEntities: entities,
            isMultiIntent: isMulti,
            contextHint: contextHint
        )
    }

    /// Returns a canned response if the intent can be handled without LLM.
    static func shortCircuitResponse(for result: IntentClassification) -> String? {
        guard result.confidence >= 0.8, !result.clarificationNeeded else { return nil }

        switch result.intentType {
        case .onboarding:
            if isGreeting(result) {
                return ["Hi! How can I help with your finances today?",
                        "Hello! Ready to help you manage your money.",
                        "Hey! What would you like to do?"].randomElement()
            }
            return """
                I can help you with:
                • Add expenses and income
                • Set and check budgets
                • Create savings goals
                • Split expenses with others
                • Manage subscriptions
                • Analyze your spending patterns
                • Compare months and forecast trends
                • Daily financial briefings

                Just tell me what you need in English or Farsi!
                """

        case .correctPreviousAction:
            if result.extractedEntities["isUndo"] == "true" {
                return ["Got it — cancelled!",
                        "No problem, skipped!",
                        "Alright, never mind!"].randomElement()
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Score All Interpretations

    /// Scores every plausible interpretation of the input.
    /// This is the core of the ambiguity-aware design.
    private static func scoreAll(_ text: String, entities: [String: String]) -> [Interpretation] {
        var results: [Interpretation] = []

        // ── Correction / Undo ──
        results.append(contentsOf: scoreCorrection(text, entities: entities))

        // ── Onboarding (greeting, thanks, help) ──
        results.append(contentsOf: scoreOnboarding(text))

        // ── Add Data (expense, income, contribution, subscription, recurring) ──
        results.append(contentsOf: scoreAddData(text, entities: entities))

        // ── Edit Data ──
        results.append(contentsOf: scoreEditData(text))

        // ── Delete Data ──
        results.append(contentsOf: scoreDeleteData(text))

        // ── Analysis (spending breakdown, daily briefing) ──
        results.append(contentsOf: scoreAnalyze(text))

        // ── Forecast ──
        results.append(contentsOf: scoreForecast(text))

        // ── Compare ──
        results.append(contentsOf: scoreCompare(text))

        // ── Plan (budget advice, restructure) ──
        results.append(contentsOf: scorePlan(text, entities: entities))

        // ── Automate (recurring, rules) ──
        results.append(contentsOf: scoreAutomate(text))

        // ── Review Items (cleanup, categorize) ──
        results.append(contentsOf: scoreReviewItems(text))

        // ── Monthly Close ──
        results.append(contentsOf: scoreMonthlyClose(text))

        // ── Ask Question (generic question) ──
        results.append(contentsOf: scoreAskQuestion(text))

        // Filter out zero-confidence
        return results.filter { $0.confidence > 0 }
    }

    // MARK: - Scoring Functions

    private static func scoreCorrection(_ text: String, entities: [String: String]) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: undoPatterns) {
            results.append(Interpretation(
                intentType: .correctPreviousAction, domain: .general,
                confidence: 0.95, reason: "Explicit undo/cancel request"
            ))
        }
        if matchesAny(text, patterns: correctionPatterns) {
            results.append(Interpretation(
                intentType: .correctPreviousAction, domain: .transactions,
                confidence: 0.9, reason: "Correction of previous action"
            ))
        }

        return results
    }

    private static func scoreOnboarding(_ text: String) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: greetingPatterns) && text.count < 30 {
            results.append(Interpretation(
                intentType: .onboarding, domain: .none,
                confidence: 0.95, reason: "Greeting detected"
            ))
        }
        if matchesAny(text, patterns: thanksPatterns) && text.count < 40 {
            results.append(Interpretation(
                intentType: .onboarding, domain: .none,
                confidence: 0.9, reason: "Thanks detected"
            ))
        }
        if matchesAny(text, patterns: helpPatterns) {
            results.append(Interpretation(
                intentType: .onboarding, domain: .none,
                confidence: 0.9, reason: "Help/capabilities request"
            ))
        }

        return results
    }

    private static func scoreAddData(_ text: String, entities: [String: String]) -> [Interpretation] {
        var results: [Interpretation] = []
        let hasAmount = entities["amount"] != nil

        // ── Transaction (expense) ──
        if matchesAny(text, patterns: addExpensePatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .transactions,
                confidence: hasAmount ? 0.85 : 0.65,
                reason: "Expense keywords detected",
                suggestedActionHint: "add_transaction"
            ))
        }

        // ── Transaction (income) ──
        if matchesAny(text, patterns: addIncomePatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .transactions,
                confidence: hasAmount ? 0.85 : 0.65,
                reason: "Income keywords detected",
                suggestedActionHint: "add_transaction_income"
            ))
        }

        // ── Split expense ──
        if matchesAny(text, patterns: splitPatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .transactions,
                confidence: 0.85, reason: "Split keywords detected",
                suggestedActionHint: "split_transaction"
            ))
        }

        // ── Goal contribution ──
        if matchesAny(text, patterns: addContributionPatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .goals,
                confidence: 0.8, reason: "Goal contribution keywords",
                suggestedActionHint: "add_contribution"
            ))
        }

        // ── Create goal ──
        if matchesAny(text, patterns: createGoalPatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .goals,
                confidence: 0.8, reason: "Goal creation keywords",
                suggestedActionHint: "create_goal"
            ))
        }

        // ── Subscription ──
        if matchesAny(text, patterns: addSubscriptionPatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .subscriptions,
                confidence: 0.8, reason: "Subscription keywords",
                suggestedActionHint: "add_subscription"
            ))
        }

        // ── Budget set ──
        if matchesAny(text, patterns: setBudgetPatterns) {
            // Budget setting is addData for the budget domain,
            // but can also be interpreted as plan
            results.append(Interpretation(
                intentType: .addData, domain: .budget,
                confidence: 0.8, reason: "Budget set keywords",
                suggestedActionHint: "set_budget"
            ))
        }

        // ── Ambiguous "put X into Y" pattern ──
        // This is the critical ambiguity case. "Put 200 into travel" could mean:
        //   - Add $200 expense in travel category (transaction)
        //   - Contribute $200 to a travel goal (goal)
        //   - Set travel budget to $200 (budget)
        if matchesAny(text, patterns: ambiguousPutIntoPatterns) && hasAmount {
            let target = extractTarget(text)
            // Add competing interpretations if not already captured with high confidence
            let existingDomains = Set(results.map(\.domain))

            if !existingDomains.contains(.transactions) {
                results.append(Interpretation(
                    intentType: .addData, domain: .transactions,
                    confidence: 0.55, reason: "Could be a transaction for '\(target)'",
                    suggestedActionHint: "add_transaction"
                ))
            }
            if !existingDomains.contains(.goals) {
                results.append(Interpretation(
                    intentType: .addData, domain: .goals,
                    confidence: 0.55, reason: "Could be a goal contribution to '\(target)'",
                    suggestedActionHint: "add_contribution"
                ))
            }
            if !existingDomains.contains(.budget) {
                results.append(Interpretation(
                    intentType: .addData, domain: .budget,
                    confidence: 0.50, reason: "Could be setting budget for '\(target)'",
                    suggestedActionHint: "set_category_budget"
                ))
            }
        }

        // ── Ambiguous "set aside X for Y" pattern ──
        if matchesAny(text, patterns: ambiguousSetAsidePatterns) && hasAmount {
            let target = extractTarget(text)
            if !results.contains(where: { $0.domain == .goals && $0.confidence > 0.7 }) {
                results.append(Interpretation(
                    intentType: .addData, domain: .goals,
                    confidence: 0.55, reason: "Could be saving for '\(target)'",
                    suggestedActionHint: "add_contribution"
                ))
            }
            if !results.contains(where: { $0.domain == .budget && $0.confidence > 0.7 }) {
                results.append(Interpretation(
                    intentType: .addData, domain: .budget,
                    confidence: 0.50, reason: "Could be a budget allocation for '\(target)'",
                    suggestedActionHint: "set_category_budget"
                ))
            }
        }

        // ── Bare amount pattern ("$50 lunch") ──
        if results.isEmpty && matchesAny(text, patterns: bareAmountPatterns) {
            results.append(Interpretation(
                intentType: .addData, domain: .transactions,
                confidence: 0.7, reason: "Bare amount with possible category",
                suggestedActionHint: "add_transaction"
            ))
        }

        return results
    }

    private static func scoreEditData(_ text: String) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: editTransactionPatterns) {
            results.append(Interpretation(
                intentType: .editData, domain: .transactions,
                confidence: 0.85, reason: "Edit/change keywords with transaction context"
            ))
        }
        if matchesAny(text, patterns: updateBalancePatterns) {
            results.append(Interpretation(
                intentType: .editData, domain: .accounts,
                confidence: 0.8, reason: "Balance update keywords"
            ))
        }

        return results
    }

    private static func scoreDeleteData(_ text: String) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: deleteTransactionPatterns) {
            results.append(Interpretation(
                intentType: .deleteData, domain: .transactions,
                confidence: 0.85, reason: "Delete/remove keywords"
            ))
        }
        if matchesAny(text, patterns: cancelSubscriptionPatterns) {
            results.append(Interpretation(
                intentType: .deleteData, domain: .subscriptions,
                confidence: 0.85, reason: "Cancel subscription keywords"
            ))
        }

        return results
    }

    private static func scoreAnalyze(_ text: String) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: dailyBriefingPatterns) {
            results.append(Interpretation(
                intentType: .analyze, domain: .general,
                confidence: 0.85, reason: "Briefing/overview request"
            ))
        }
        if matchesAny(text, patterns: spendingPatterns) {
            results.append(Interpretation(
                intentType: .analyze, domain: .transactions,
                confidence: 0.8, reason: "Spending analysis keywords"
            ))
        }
        if matchesAny(text, patterns: checkBudgetPatterns) {
            results.append(Interpretation(
                intentType: .analyze, domain: .budget,
                confidence: 0.8, reason: "Budget status check"
            ))
        }
        if matchesAny(text, patterns: checkGoalsPatterns) {
            results.append(Interpretation(
                intentType: .analyze, domain: .goals,
                confidence: 0.8, reason: "Goal progress check"
            ))
        }
        if matchesAny(text, patterns: checkAccountsPatterns) {
            results.append(Interpretation(
                intentType: .analyze, domain: .accounts,
                confidence: 0.8, reason: "Account balance check"
            ))
        }

        return results
    }

    private static func scoreForecast(_ text: String) -> [Interpretation] {
        guard matchesAny(text, patterns: forecastPatterns) else { return [] }
        return [Interpretation(
            intentType: .forecast, domain: .general,
            confidence: 0.8, reason: "Forecast/prediction keywords"
        )]
    }

    private static func scoreCompare(_ text: String) -> [Interpretation] {
        guard matchesAny(text, patterns: comparisonPatterns) else { return [] }
        return [Interpretation(
            intentType: .compare, domain: .general,
            confidence: 0.8, reason: "Comparison keywords"
        )]
    }

    private static func scorePlan(_ text: String, entities: [String: String]) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: planPatterns) {
            results.append(Interpretation(
                intentType: .plan, domain: .budget,
                confidence: 0.75, reason: "Planning/restructuring keywords"
            ))
        }
        if matchesAny(text, patterns: advicePatterns) {
            results.append(Interpretation(
                intentType: .plan, domain: .general,
                confidence: 0.75, reason: "Advice/suggestion keywords"
            ))
        }

        return results
    }

    private static func scoreAutomate(_ text: String) -> [Interpretation] {
        guard matchesAny(text, patterns: automatePatterns) else { return [] }
        return [Interpretation(
            intentType: .automate, domain: .subscriptions,
            confidence: 0.8, reason: "Automation/recurring keywords"
        )]
    }

    private static func scoreReviewItems(_ text: String) -> [Interpretation] {
        var results: [Interpretation] = []

        if matchesAny(text, patterns: reviewPatterns) {
            results.append(Interpretation(
                intentType: .reviewItems, domain: .transactions,
                confidence: 0.75, reason: "Review/cleanup keywords"
            ))
        }

        // "fix this month" is ambiguous between review and monthly close
        if matchesAny(text, patterns: ambiguousFixPatterns) {
            results.append(Interpretation(
                intentType: .reviewItems, domain: .transactions,
                confidence: 0.5, reason: "Could be transaction cleanup"
            ))
            results.append(Interpretation(
                intentType: .monthlyClose, domain: .general,
                confidence: 0.45, reason: "Could be month-end review"
            ))
            results.append(Interpretation(
                intentType: .analyze, domain: .general,
                confidence: 0.40, reason: "Could be analysis of this month"
            ))
        }

        return results
    }

    private static func scoreMonthlyClose(_ text: String) -> [Interpretation] {
        guard matchesAny(text, patterns: monthlyClosePatterns) else { return [] }
        return [Interpretation(
            intentType: .monthlyClose, domain: .general,
            confidence: 0.8, reason: "Month-end/close keywords"
        )]
    }

    private static func scoreAskQuestion(_ text: String) -> [Interpretation] {
        // Generic question detection — only if nothing else matched well
        if matchesAny(text, patterns: questionPatterns) {
            return [Interpretation(
                intentType: .askQuestion, domain: .general,
                confidence: 0.5, reason: "Question structure detected"
            )]
        }
        return []
    }

    // MARK: - Ambiguity Clarification Builder

    private static func buildAmbiguityClarification(
        input: String,
        interpretations: [Interpretation],
        entities: [String: String]
    ) -> ClarificationResult {
        // Build a practical, short question from the competing interpretations
        let domains = Set(interpretations.map(\.domain))
        let types = Set(interpretations.map(\.intentType))

        let question: String
        let missing: [String]

        if types.count == 1 && types.first == .addData && domains.count > 1 {
            // Same action type, different domains: "put 200 into travel"
            let options = interpretations.compactMap { interp -> String? in
                switch interp.domain {
                case .transactions:  return "record a transaction"
                case .goals:         return "contribute to a goal"
                case .budget:        return "set a category budget"
                case .subscriptions: return "add a subscription"
                default: return nil
                }
            }
            let joined = options.joined(separator: ", or ")
            question = "Do you want to \(joined)?"
            missing = ["target_type"]

        } else if types.contains(.reviewItems) && types.contains(.monthlyClose) {
            question = "Do you want me to review your transactions, or do a full month-end close?"
            missing = ["scope"]

        } else if types.contains(.reviewItems) && types.contains(.analyze) {
            question = "Should I clean up your data, or just show you an analysis?"
            missing = ["scope"]

        } else {
            // Generic ambiguity
            let optionStrings = interpretations.prefix(3).map { $0.reason }
            question = "I see a few possibilities: \(optionStrings.joined(separator: "; ")). Which did you mean?"
            missing = ["intent"]
        }

        return ClarificationResult(
            question: question,
            interpretations: interpretations,
            missingFields: missing
        )
    }

    // MARK: - Context Hint Resolution

    private static func resolveContextHint(
        primary: Interpretation,
        secondary: Interpretation?
    ) -> IntentClassification.ContextHint {
        // If ambiguous across domains, load full context
        if let sec = secondary, sec.domain != primary.domain, sec.confidence > 0.4 {
            return .full
        }

        switch primary.domain {
        case .transactions: return .transactionsOnly
        case .budget:       return .budgetOnly
        case .goals:        return .goalsOnly
        case .subscriptions: return .subscriptionsOnly
        case .accounts:     return .accountsOnly
        case .general:
            switch primary.intentType {
            case .analyze, .forecast, .compare, .monthlyClose, .plan:
                return .full
            case .onboarding:
                return .minimal
            default:
                return .full
            }
        case .none:
            return primary.intentType == .onboarding ? .none : .minimal
        }
    }

    // MARK: - Helper: isGreeting

    private static func isGreeting(_ result: IntentClassification) -> Bool {
        result.intentType == .onboarding
        && result.extractedEntities["subtype"] == "greeting"
    }

    // MARK: - Multi-intent Detection

    private static func detectMultiIntent(_ text: String) -> Bool {
        let conjunctions = [
            "\\band\\b", "\\balso\\b", "\\bthen\\b", "\\bplus\\b",
            "\\bو\\b", "\\bهمچنین\\b", "\\bبعدش\\b",
            ",\\s*(add|set|create|delete|split|cancel|log)",
            ",\\s*(بزن|اضافه|حذف|تقسیم|بودجه|لغو)"
        ]
        for pattern in conjunctions {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    // MARK: - Entity Extraction

    private static func extractEntities(_ text: String) -> [String: String] {
        var entities: [String: String] = [:]

        // Amount extraction
        if let amount = extractAmount(text) {
            entities["amount"] = amount
        }

        // Target extraction (for "put X into Y", "save for Y")
        let target = extractTarget(text)
        if !target.isEmpty {
            entities["target"] = target
        }

        // Subtype markers for onboarding
        if matchesAny(text, patterns: greetingPatterns) {
            entities["subtype"] = "greeting"
        } else if matchesAny(text, patterns: thanksPatterns) {
            entities["subtype"] = "thanks"
        }

        // Undo marker
        if matchesAny(text, patterns: undoPatterns) {
            entities["isUndo"] = "true"
        }

        return entities
    }

    /// Extract a dollar/numeric amount from text. Returns the string value.
    private static func extractAmount(_ text: String) -> String? {
        // "5k" / "5K" → 5000
        let kPattern = "\\b(\\d+)[kK]\\b"
        if let regex = try? NSRegularExpression(pattern: kPattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text),
           let num = Int(text[r]) {
            return String(num * 1000)
        }

        // "$50", "€50", "50 dollars", "50€", "50 تومان"
        let currencyPattern = "(?:[$€£¥₹﷼]\\s?)(\\d+(?:[,.]\\d{1,2})?)|(\\d+(?:[,.]\\d{1,2})?)\\s*(?:[$€£¥₹﷼]|dollar|euro|تومان|تومن|ریال)"
        if let regex = try? NSRegularExpression(pattern: currencyPattern, options: [.caseInsensitive]),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            for i in 1...2 {
                let range = match.range(at: i)
                if range.location != NSNotFound, let r = Range(range, in: text) {
                    return String(text[r]).replacingOccurrences(of: ",", with: "")
                }
            }
        }

        // Farsi multipliers: "50 هزار" → 50000, "2 میلیون" → 2000000
        let farsiMultiplier = "(\\d+)\\s*(هزار|میلیون)"
        if let regex = try? NSRegularExpression(pattern: farsiMultiplier),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let nr = Range(match.range(at: 1), in: text),
           let mr = Range(match.range(at: 2), in: text),
           let num = Int(text[nr]) {
            let mult = text[mr]
            return String(mult.contains("میلیون") ? num * 1_000_000 : num * 1000)
        }

        // Bare number ("add 50 for lunch")
        let bareNumber = "\\b(\\d+(?:\\.\\d{1,2})?)\\b"
        if let regex = try? NSRegularExpression(pattern: bareNumber),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text) {
            return String(text[r])
        }

        return nil
    }

    /// Extract the target of "put X into Y" / "save for Y" / "set aside X for Y".
    private static func extractTarget(_ text: String) -> String {
        let patterns = [
            "(?:into|for|towards|to|به|برای|بابت)\\s+(\\w+(?:\\s+\\w+)?)",
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let r = Range(match.range(at: 1), in: text) {
                let target = String(text[r])
                // Filter out noise words
                let noise: Set = ["it", "that", "this", "the", "a", "my", "آن", "این"]
                if !noise.contains(target.lowercased()) {
                    return target
                }
            }
        }
        return ""
    }

    // MARK: - Pattern Matching

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                return true
            }
        }
        return false
    }

    /// Normalize Persian/Arabic digits to ASCII digits.
    private static func normalizePersianDigits(_ text: String) -> String {
        var result = text
        let persianDigits: [(Character, Character)] = [
            ("۰", "0"), ("۱", "1"), ("۲", "2"), ("۳", "3"), ("۴", "4"),
            ("۵", "5"), ("۶", "6"), ("۷", "7"), ("۸", "8"), ("۹", "9"),
            ("٠", "0"), ("١", "1"), ("٢", "2"), ("٣", "3"), ("٤", "4"),
            ("٥", "5"), ("٦", "6"), ("٧", "7"), ("٨", "8"), ("٩", "9")
        ]
        for (persian, ascii) in persianDigits {
            result = result.replacingOccurrences(of: String(persian), with: String(ascii))
        }
        return result
    }

    // ================================================================
    // MARK: - Pattern Lists
    // ================================================================

    // ── Correction & Undo ──

    private static let undoPatterns = [
        "^(undo|cancel that|never mind|forget it|skip|بیخیال|ولش|فراموشش کن)$",
        "^(cancel|لغو|نه ولش|بیخیالش)$",
        "\\b(undo|cancel that|never mind)\\b",
        "\\b(بیخیال|ولش|فراموشش کن)\\b"
    ]

    private static let correctionPatterns = [
        "\\b(no i meant|i meant|not \\d+|wrong|اشتباه|نه منظورم)\\b",
        "\\b(change it to|actually|correction|should be|تغییرش بده)\\b",
        "\\b(make it|instead of|نه \\d+)\\b.*\\b(not|بجاش)\\b",
        "\\b(اشتباه زدم|درستش کن|عوضش کن)\\b"
    ]

    // ── Greetings / Thanks / Help ──

    private static let greetingPatterns = [
        "^(hi|hello|hey|yo|sup|سلام|هلو|درود|hallo|guten tag)\\b",
        "^(good morning|good evening|good afternoon|صبح بخیر|شب بخیر|عصر بخیر)",
        "^(سلام خوبی|سلام چطوری)$"
    ]

    private static let thanksPatterns = [
        "\\b(thanks|thank you|thx|ty|ممنون|مرسی|دمت گرم|دستت درد نکنه|ممنونم|danke)\\b",
        "^(thanks|مرسی|ممنون)!?$"
    ]

    private static let helpPatterns = [
        "\\b(help|what can you do|چیکار میتونی|راهنما|کمک|چه کارایی)\\b",
        "\\b(capabilities|features|commands|hilfe|امکانات)\\b",
        "\\b(what do you do|how do you work|چیکارا بلدی)\\b"
    ]

    // ── Daily Briefing / Overview ──

    private static let dailyBriefingPatterns = [
        "\\b(how am i doing|daily summary|daily briefing|overview|brief me)\\b",
        "\\b(وضعم چطوره|خلاصه روز|خلاصه|وضعیتم|وضعیت کلی)\\b",
        "\\b(month summary|monthly report|گزارش ماهانه|خلاصه ماه)\\b",
        "^(summary|overview|briefing|خلاصه|وضعیت)$",
        "\\b(چطوریم|کجاییم|وضع مالی|روند مالی)\\b"
    ]

    // ── Split ──

    private static let splitPatterns = [
        "\\b(split|divide|share|تقسیم|نصف)\\b.*(with|با|expense|cost|هزینه)",
        "\\b(split|تقسیم|نصف کن)\\b",
        "\\b(با.*نصف|نصفش کن)\\b",
        "\\b(share.*(cost|bill|expense)|go halves)\\b",
        "\\b(تقسیم.*کن|قسمت کن)\\b"
    ]

    // ── Transactions ──

    private static let addExpensePatterns = [
        "\\b(add|spent|bought|paid|خرید|خریدم|هزینه|پرداخت|دادم)\\b",
        "\\b(expense|purchase|bezahlt|ausgabe|charge|cost)\\b",
        "\\b(بزن|ثبت|اضافه کن|رد کن|وارد کن|لاگ)\\b",
        "\\b(log|record|enter)\\b.*\\b(expense|transaction|payment)\\b",
        "\\b(زدم|گرفتم|رفتم)\\b.*\\b(خرج|خرید|هزینه|تومن|دلار)\\b",
        "\\b(pay|paid for|پرداختم|حساب کردم)\\b"
    ]

    private static let addIncomePatterns = [
        "\\b(received|earned|salary|income|حقوق|درآمد|گرفتم|واریز)\\b",
        "\\b(paycheck|gehalt|einkommen|wage|bonus|tip|refund)\\b",
        "\\b(حقوقم|درآمدم|واریز شد|پول گرفتم|دستمزد)\\b",
        "\\b(got paid|payday|freelance income)\\b"
    ]

    private static let deleteTransactionPatterns = [
        "\\b(delete|remove|حذف|پاک کن)\\b.*\\b(transaction|تراکنش|خرید|expense|last)\\b",
        "\\b(حذفش کن|پاکش کن|بردارش)\\b",
        "\\b(delete|remove)\\b.*\\b(the last|that|this|it)\\b",
        "\\b(آخریو حذف|حذف کن آخری)\\b"
    ]

    private static let editTransactionPatterns = [
        "\\b(edit|change|update|modify|ویرایش|تغییر|عوض)\\b.*\\b(transaction|تراکنش|خرید|amount|مبلغ)\\b",
        "\\b(ویرایشش کن|تغییرش بده|عوضش کن|اصلاح)\\b",
        "\\b(change|update)\\b.*\\b(the|that|last|it)\\b.*\\b(to|amount|category)\\b",
        "\\b(مبلغشو عوض|کتگوریشو عوض|تاریخشو عوض)\\b"
    ]

    // ── Budget ──

    private static let setBudgetPatterns = [
        "\\b(set|change|update|adjust)\\b.*\\b(budget|بودجه)\\b",
        "\\b(budget|بودجه)\\b.*\\b(to|به|set|بذار|بکن)\\b",
        "\\b(بودجه.*بذار|بودجه.*تنظیم|بودجه.*ست)\\b",
        "\\b(monthly budget|ماهانه بودجه)\\b",
        "\\b(بودجمو|بودجه رو)\\b.*\\b(بذار|بکن|تنظیم|عوض)\\b",
        "\\b(category budget|set.*budget.*for)\\b"
    ]

    private static let checkBudgetPatterns = [
        "\\b(how much|remaining|left|باقی|مانده|چقدر)\\b.*\\b(budget|بودجه)\\b",
        "\\b(budget|بودجه)\\b.*\\b(status|وضعیت|check|remaining|left|باقی)\\b",
        "\\b(وضع بودجه|بودجم چقدر|چقد مونده|باقیمونده)\\b",
        "\\b(am i over budget|under budget|budget.*remaining)\\b",
        "\\b(بودجم چطوره|وضع بودجم)\\b"
    ]

    // ── Goals ──

    private static let createGoalPatterns = [
        "\\b(create|new|start|ایجاد|بساز)\\b.*\\b(goal|هدف)\\b",
        "\\b(save for|save up|پس‌انداز برای|پس انداز)\\b",
        "\\b(saving goal|savings goal|هدف پس‌انداز)\\b",
        "\\b(میخوام.*جمع کنم|میخوام.*پس انداز)\\b",
        "\\b(i want to save|planning to save)\\b"
    ]

    private static let addContributionPatterns = [
        "\\b(add|put|contribute|واریز|اضافه)\\b.*\\b(goal|هدف|towards|saving|fund)\\b",
        "\\b(واریز.*هدف|اضافه.*هدف|بریز.*هدف)\\b",
        "\\b(put.*towards|contribute to|add to.*goal)\\b"
    ]

    private static let checkGoalsPatterns = [
        "\\b(goal|هدف)\\b.*\\b(progress|status|وضعیت|پیشرفت|how|check)\\b",
        "\\b(how are my goals|goal status|وضعیت هدف|هدفام چطوره)\\b",
        "\\b(goal progress|am i on track|هدفم کجاست)\\b"
    ]

    // ── Subscriptions ──

    private static let addSubscriptionPatterns = [
        "\\b(add|new|اضافه)\\b.*\\b(subscription|اشتراک)\\b",
        "\\b(subscribe|اشتراک بزن|اشتراک اضافه)\\b",
        "\\b(monthly|yearly)\\b.*\\b(subscription|payment|plan)\\b",
        "\\b(هر ماه.*میدم|هر ماه.*پرداخت)\\b"
    ]

    private static let cancelSubscriptionPatterns = [
        "\\b(cancel|stop|لغو|کنسل)\\b.*\\b(subscription|اشتراک)\\b",
        "\\b(unsubscribe|remove subscription)\\b",
        "\\b(لغو.*اشتراک|کنسل.*اشتراک|اشتراک.*لغو|اشتراک.*کنسل)\\b"
    ]

    // ── Accounts ──

    private static let updateBalancePatterns = [
        "\\b(update|set|change)\\b.*\\b(balance|موجودی)\\b",
        "\\b(balance.*to|موجودی.*به|موجودیمو)\\b",
        "\\b(account.*balance|set.*balance)\\b"
    ]

    private static let checkAccountsPatterns = [
        "\\b(account|حساب)\\b.*\\b(balance|status|موجودی|وضعیت)\\b",
        "\\b(net worth|how much do i have|موجودیم|حسابم چقدر)\\b",
        "\\b(what.*balance|check.*account|حساب.*چقدر)\\b",
        "\\b(دارایی|ارزش|سرمایه)\\b"
    ]

    // ── Analysis ──

    private static let spendingPatterns = [
        "\\b(spending|خرج|هزینه|مخارج)\\b",
        "\\b(breakdown|analysis|تحلیل|آنالیز)\\b",
        "\\b(how much did i|چقدر خرج|how much have i)\\b",
        "\\b(spending.*this month|this month.*spending|خرج.*ماه|ماه.*خرج)\\b",
        "\\b(where.*money.*go|biggest expense|بیشترین خرج|کجا خرج)\\b",
        "\\b(top categories|category breakdown|تفکیک)\\b"
    ]

    private static let comparisonPatterns = [
        "\\b(compare|vs|versus|مقایسه)\\b",
        "\\b(last month|ماه قبل|previous|قبلی)\\b.*\\b(vs|compare|مقایسه|than|نسبت)\\b",
        "\\b(better|worse|more|less)\\b.*\\b(than last|than previous)\\b",
        "\\b(بهتر|بدتر|بیشتر|کمتر)\\b.*\\b(ماه قبل|قبلی)\\b",
        "\\b(از ماه پیش|نسبت به قبل|مقایسه ماه)\\b",
        "\\b(month over month|trend|روند)\\b"
    ]

    private static let forecastPatterns = [
        "\\b(forecast|predict|پیش‌بینی|پیشبینی|next month|ماه بعد)\\b",
        "\\b(will i|آیا.*خواهم|estimate|تخمین|project)\\b",
        "\\b(how much will|at this rate|at this pace|با این روند)\\b",
        "\\b(end of month|آخر ماه.*چقدر|predict.*spend)\\b",
        "\\b(gonna|going to)\\b.*\\b(spend|save|owe)\\b"
    ]

    private static let advicePatterns = [
        "\\b(advice|suggest|recommend|tip|پیشنهاد|توصیه|نظر)\\b",
        "\\b(should i|what should|بهتره|چیکار کنم|how can i save)\\b",
        "\\b(help me save|ways to save|cut costs|کم کنم|صرفه‌جویی)\\b",
        "\\b(ideas|suggestions|recommendations|راه حل)\\b",
        "\\b(improve|optimize|بهتر کنم|بهینه)\\b.*\\b(budget|spending|بودجه|خرج)\\b"
    ]

    // ── Plan ──

    private static let planPatterns = [
        "\\b(plan|restructure|ساختار|برنامه‌ریزی)\\b.*\\b(budget|spending|بودجه|خرج)\\b",
        "\\b(set a better|make a plan|بهتر کنم)\\b",
        "\\b(budget.*next month|بودجه.*ماه بعد)\\b",
        "\\b(need a plan|make a budget|بودجه بریز)\\b"
    ]

    // ── Automate ──

    private static let automatePatterns = [
        "\\b(automat|from now on|handle.*automatically|خودکار|اتوماتیک)\\b",
        "\\b(set up recurring|add recurring|تکرار|مکرر)\\b",
        "\\b(every month|هر ماه)\\b.*\\b(automat|handle|pay|پرداخت)\\b",
        "\\b(schedule|auto-pay|auto pay)\\b"
    ]

    // ── Review / Cleanup ──

    private static let reviewPatterns = [
        "\\b(clean up|cleanup|review|مرور|بررسی|تمیز)\\b.*\\b(transaction|uncategorized|دسته‌بندی نشده)\\b",
        "\\b(fix.*categor|recategorize|دسته‌بندی.*درست)\\b",
        "\\b(duplicate|تکراری)\\b.*\\b(transaction|remove|حذف)\\b",
        "\\b(sort out|organize|مرتب)\\b.*\\b(transaction|expense|خرج)\\b"
    ]

    // ── Monthly Close ──

    private static let monthlyClosePatterns = [
        "\\b(month.?end|close.*month|ببند.*ماه|پایان ماه)\\b",
        "\\b(monthly.*close|monthly.*review|بررسی.*ماهانه)\\b",
        "\\b(wrap up|finalize|نهایی)\\b.*\\b(month|ماه)\\b"
    ]

    // ── Ambiguous Patterns ──

    /// "put X into Y" — could be transaction, goal, or budget
    private static let ambiguousPutIntoPatterns = [
        "\\b(put|place|throw|drop|بذار|بریز)\\b.*\\b(into|in|to|توی|به)\\b",
        "\\b(allocate|assign)\\b.*\\b(to|for)\\b"
    ]

    /// "set aside X for Y" — could be goal or budget
    private static let ambiguousSetAsidePatterns = [
        "\\b(set aside|reserve|save|keep|کنار بذار|نگه دار)\\b.*\\b(for|برای)\\b"
    ]

    /// "fix this month" — review vs analysis vs monthly close
    private static let ambiguousFixPatterns = [
        "^fix\\b.*\\b(this month|month|ماه)$",
        "^(fix|sort|clean)\\b.*\\b(this|ماه|month)\\b"
    ]

    // ── Bare Amount ──

    private static let bareAmountPatterns = [
        "^[$€£¥₹﷼]\\d+",
        "^\\d+[$€£¥₹﷼]",
        "^\\d+\\s+(for|بابت|برای)\\b",
        "^[$€£¥₹﷼]?\\d+(\\.\\d{1,2})?\\s+\\w+"
    ]

    // ── Question ──

    private static let questionPatterns = [
        "^(how|what|when|where|why|which|who|can|do|does|is|are|am)\\b",
        "\\?$",
        "^(چقدر|کی|کجا|چرا|چطور|آیا|چند)\\b",
        "[؟]$"
    ]
}
