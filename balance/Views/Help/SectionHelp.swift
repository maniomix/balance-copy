import SwiftUI

// MARK: - Content model

/// One self-contained tutorial entry for a section of the app.
/// Lives in `SectionHelpLibrary` keyed by `SectionHelpScreen`.
struct SectionHelp {
    let screen: SectionHelpScreen
    let tagline: String
    let heroIcon: String
    let heroTint: Color
    let elevatorPitch: String
    let blocks: [Block]
    let steps: [Step]
    let proTips: [String]
    let faq: [QA]

    struct Block: Identifiable {
        enum Kind { case what, why, how, watchOut }
        let id = UUID()
        let kind: Kind
        let title: String
        let body: String
    }

    struct Step: Identifiable {
        let id = UUID()
        let number: Int
        let title: String
        let body: String
        let icon: String
    }

    struct QA: Identifiable {
        let id = UUID()
        let q: String
        let a: String
    }
}

extension SectionHelp.Block.Kind {
    var color: Color {
        switch self {
        case .what: DS.Colors.accent
        case .why: DS.Colors.accent
        case .how: DS.Colors.positive
        case .watchOut: DS.Colors.warning
        }
    }
    var label: String {
        switch self {
        case .what: "WHAT IT IS"
        case .why: "WHY IT MATTERS"
        case .how: "HOW IT WORKS"
        case .watchOut: "HEADS UP"
        }
    }
    var icon: String {
        switch self {
        case .what: "sparkles"
        case .why: "heart.fill"
        case .how: "wand.and.stars"
        case .watchOut: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Screens

enum SectionHelpScreen: String, CaseIterable {
    case dashboard
    case transactions
    case budget
    case accounts
    case goals
    case subscriptions
    case insights
    case analytics
    case household
    case more
    case settings
    case aiChat
    case briefing

    var displayName: String {
        switch self {
        case .dashboard: "Dashboard"
        case .transactions: "Transactions"
        case .budget: "Budget"
        case .accounts: "Accounts"
        case .goals: "Goals"
        case .subscriptions: "Subscriptions"
        case .insights: "Insights"
        case .analytics: "Analytics"
        case .household: "Household"
        case .more: "More"
        case .settings: "Settings"
        case .aiChat: "Centmond AI"
        case .briefing: "Monthly Briefing"
        }
    }
}

// MARK: - Library

enum SectionHelpLibrary {
    static func entry(for screen: SectionHelpScreen) -> SectionHelp? { entries[screen] }

    private static let entries: [SectionHelpScreen: SectionHelp] = [
        .dashboard: dashboard,
        .transactions: transactions,
        .budget: budget,
        .accounts: accounts,
        .goals: goals,
        .subscriptions: subscriptions,
        .insights: insights,
        .analytics: analytics,
        .household: household,
        .more: more,
        .settings: settings,
        .aiChat: aiChat,
        .briefing: briefing,
    ]

    // MARK: Dashboard

    private static let dashboard = SectionHelp(
        screen: .dashboard,
        tagline: "Your money at a glance — income, spending, what's safe to spend.",
        heroIcon: "house.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "The Dashboard is your home base. Every important number for the month — what came in, what went out, and what's safe to spend — sits in one place so you can answer 'how am I doing?' in under five seconds.",
        blocks: [
            .init(kind: .what, title: "A live monthly snapshot",
                  body: "Tiles up top show Income, Spending, what's left in your budget, and Safe to Spend — a smart number that already subtracts upcoming bills."),
            .init(kind: .why, title: "Decisions, not data dumps",
                  body: "You shouldn't have to do math in your head. Every chart here answers a real question: can I order takeout tonight? Am I on pace?"),
            .init(kind: .how, title: "Updates as you go",
                  body: "Add a transaction and every tile and chart on this screen recalculates instantly. No refresh needed."),
            .init(kind: .watchOut, title: "Watch the month switcher",
                  body: "All numbers reflect the month picked at the top. Tapping the arrows changes everything you see here."),
        ],
        steps: [
            .init(number: 1, title: "Read the tiles",
                  body: "Green is good (money in or buffer left). Red means you've gone over. Safe to Spend is the one to trust day-to-day.",
                  icon: "square.grid.2x2.fill"),
            .init(number: 2, title: "Scan the charts",
                  body: "Pace, vs Last Month, and Daily charts live behind the pill selector — switch between them to read the story.",
                  icon: "chart.bar.fill"),
            .init(number: 3, title: "Tap the AI Advisor",
                  body: "The advisor card surfaces 1–3 things worth noticing. Tap any card to open a detail sheet, or jump into chat from there.",
                  icon: "lightbulb.fill"),
            .init(number: 4, title: "Open recent activity",
                  body: "The recent transactions list at the bottom is one tap to inspect or recategorize a row.",
                  icon: "list.bullet.rectangle.fill"),
        ],
        proTips: [
            "Swipe a recent transaction row for quick actions.",
            "Use Back Tap (set in Settings) to add a transaction without opening the app.",
            "The AI banner is a one-tap shortcut — ask 'why am I red this month?'",
        ],
        faq: [
            .init(q: "Why is Safe to Spend lower than Remaining?",
                  a: "Safe to Spend already subtracts the bills and subscriptions still due before month-end. Remaining is just budget minus actual spend so far."),
            .init(q: "Some numbers look stale.",
                  a: "Check the month picker — you may be looking at a past month. Pull-to-refresh isn't needed; everything reactive."),
        ]
    )

    // MARK: Transactions

    private static let transactions = SectionHelp(
        screen: .transactions,
        tagline: "Every euro you've spent or earned, in one searchable list.",
        heroIcon: "list.bullet.rectangle.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "Transactions is the source of truth. Add, edit, search, recategorize, split — anything that touches a single line of money happens here.",
        blocks: [
            .init(kind: .what, title: "Your full ledger",
                  body: "Every income, expense, and transfer ever recorded — across all accounts and dates."),
            .init(kind: .why, title: "Categorization = good budgets",
                  body: "Centmond can only build smart budgets and forecasts if your transactions are correctly categorized. This is where you fix that."),
            .init(kind: .how, title: "Swipe is power-user mode",
                  body: "Swipe a row for quick edit or delete. Tap a row to open the detail sheet for full editing, splits, and sharing."),
            .init(kind: .watchOut, title: "Filter chips stack",
                  body: "If results look thin, check the chip bar — month, account, and category filters all narrow the list at once."),
        ],
        steps: [
            .init(number: 1, title: "Add a transaction",
                  body: "Tap the + button. Pick income, expense, or transfer; fill amount, category, account, date.",
                  icon: "plus.circle.fill"),
            .init(number: 2, title: "Search & filter",
                  body: "Type in the search bar, or use the chip bar above the list to narrow by date, account, or category.",
                  icon: "magnifyingglass"),
            .init(number: 3, title: "Edit a row",
                  body: "Tap a row to open the detail sheet. Change category, amount, or notes — saves immediately.",
                  icon: "pencil.circle.fill"),
            .init(number: 4, title: "Split or share",
                  body: "From the detail sheet, split a transaction across categories or share with household members for accurate balances.",
                  icon: "rectangle.split.3x1.fill"),
        ],
        proTips: [
            "CSV import lives in Settings → Import — it auto-detects most bank export formats.",
            "Tag a transaction as a subscription to link it to a recurring service for forecasting.",
            "Use the AI: 'recategorize all coffee transactions to Food & Drink'.",
        ],
        faq: [
            .init(q: "Why are some rows greyed out?",
                  a: "Those are 'pending' — usually imported but not yet reviewed. Mark them reviewed to clear the muting."),
            .init(q: "Can I undo a delete?",
                  a: "Single deletes can be undone from the toast. Bulk deletes show a confirm and are permanent."),
        ]
    )

    // MARK: Budget

    private static let budget = SectionHelp(
        screen: .budget,
        tagline: "Set monthly limits per category. Watch them fill up. Stay on track.",
        heroIcon: "chart.pie.fill",
        heroTint: DS.Colors.positive,
        elevatorPitch: "A budget is just a promise to yourself. Centmond makes it a visual one — colored bars and clear 'safe to spend' numbers so you always know where you stand.",
        blocks: [
            .init(kind: .what, title: "Per-category envelopes",
                  body: "Each category gets a monthly cap. Spend within it = green. Approaching the cap = amber. Over = red."),
            .init(kind: .why, title: "Visible limits change behavior",
                  body: "People who see their budget daily spend ~20% less. The progress bars are built for exactly that."),
            .init(kind: .how, title: "Limits are sticky, not nags",
                  body: "Going over a budget is allowed — Centmond won't block a transaction. But the dashboard tile turns red and next month's safe-to-spend recalibrates."),
            .init(kind: .watchOut, title: "Total budget vs. category sums",
                  body: "Your category caps don't have to add up to your income. The total summary shows the gap."),
        ],
        steps: [
            .init(number: 1, title: "Pick a category",
                  body: "Tap any row to set or change its monthly cap. €0 = uncapped (no warnings).",
                  icon: "tag.fill"),
            .init(number: 2, title: "Read the bars",
                  body: "Each row shows a color-coded progress bar. The percentage to the right is how much of the cap you've used.",
                  icon: "chart.bar.fill"),
            .init(number: 3, title: "Roll over to next month",
                  body: "Caps carry forward automatically. Tweak per-month from the row's edit sheet.",
                  icon: "arrow.right.circle.fill"),
        ],
        proTips: [
            "Use AI: 'suggest a budget based on my last 3 months' — it'll propose caps you can approve.",
            "Categories with no spend in 90 days fade — consider archiving them in Settings.",
        ],
        faq: [
            .init(q: "Why is everything empty?",
                  a: "Either no transactions in that range, or your transactions don't have categories assigned. Open Transactions and check."),
            .init(q: "Can I have weekly budgets?",
                  a: "Not yet — Centmond uses monthly envelopes."),
        ]
    )

    // MARK: Accounts

    private static let accounts = SectionHelp(
        screen: .accounts,
        tagline: "Every bank, card, and wallet you track — and what's in each one.",
        heroIcon: "building.columns.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "Accounts are containers. Every transaction belongs to one. Add your checking, savings, credit cards, and cash — Centmond will track balances and roll them up into your Net Worth.",
        blocks: [
            .init(kind: .what, title: "Where your money lives",
                  body: "Checking, savings, credit, loan, investment, cash. Each has a balance, a currency, and an owner."),
            .init(kind: .why, title: "Accounts power Net Worth",
                  body: "The Net Worth card sums all asset accounts and subtracts all liability accounts. Garbage in, garbage out — keep balances current."),
            .init(kind: .how, title: "Balances auto-update",
                  body: "Every transaction tagged to an account adjusts its running balance. You only enter the starting balance once."),
            .init(kind: .watchOut, title: "Credit cards are liabilities",
                  body: "A credit card balance is money you OWE, so it subtracts from net worth. Set the type correctly when adding."),
        ],
        steps: [
            .init(number: 1, title: "Add an account",
                  body: "Tap +. Name it (e.g. 'Revolut EUR'), pick the type, set today's balance.",
                  icon: "plus.app.fill"),
            .init(number: 2, title: "Tag transactions",
                  body: "When adding a transaction, pick which account it came from. Centmond updates that account's balance.",
                  icon: "link"),
            .init(number: 3, title: "Transfer between accounts",
                  body: "Use the Transfer sheet to move money between two of your own accounts — supports FX for multi-currency.",
                  icon: "arrow.left.arrow.right"),
            .init(number: 4, title: "Reconcile periodically",
                  body: "Compare Centmond's balance to your bank's. If off, add an 'adjustment' transaction to true it up.",
                  icon: "checkmark.shield.fill"),
        ],
        proTips: [
            "Use a clear naming convention: 'Bank · Type · Currency'.",
            "Archive old closed accounts instead of deleting — keeps history intact.",
            "The reorder sheet (long-press list) lets you control display order.",
        ],
        faq: [
            .init(q: "Can Centmond connect to my bank?",
                  a: "No — for privacy, Centmond is local-first. Use CSV import for bulk loading."),
            .init(q: "Multiple currencies?",
                  a: "Each account can have its own currency. Reports use your default currency and show conversions where needed."),
        ]
    )

    // MARK: Goals

    private static let goals = SectionHelp(
        screen: .goals,
        tagline: "Save for the things you actually care about — and watch the bar fill up.",
        heroIcon: "target",
        heroTint: DS.Colors.positive,
        elevatorPitch: "A goal turns 'I should save more' into 'I'm 47% of the way to my Japan trip'. Set a target, log contributions, and let Centmond track the rest.",
        blocks: [
            .init(kind: .what, title: "Targets with deadlines",
                  body: "Each goal has a name, a target amount, an optional deadline, and an icon. That's it."),
            .init(kind: .why, title: "Specific beats vague",
                  body: "'Save €4,000 for Japan by September' is 10× more motivating than 'save more'. Centmond shows pace and gap so you can adjust."),
            .init(kind: .how, title: "Income allocation",
                  body: "Mark a percentage of every income to auto-flow into goals. Or transfer manually from any account."),
            .init(kind: .watchOut, title: "Goals don't move money",
                  body: "Centmond tracks goal progress as bookkeeping — your actual savings still need to live in a real account. Pair every goal with a savings account in your head."),
        ],
        steps: [
            .init(number: 1, title: "Create a goal",
                  body: "Pick name, target, deadline, and an icon.",
                  icon: "plus.circle.fill"),
            .init(number: 2, title: "Add contributions",
                  body: "Tap a goal → 'Add Contribution' to log a transfer toward it. Or set income allocation to do it automatically.",
                  icon: "arrow.right.to.line.compact"),
            .init(number: 3, title: "Watch the pace",
                  body: "Each card shows progress and 'on pace / behind / ahead'. Behind = consider raising your auto-allocation.",
                  icon: "speedometer"),
        ],
        proTips: [
            "Set a deadline even if it's flexible — pace tracking only works with one.",
            "AI Chat can suggest goals based on your spending patterns.",
            "Shared goals appear in Household so the whole family pulls in the same direction.",
        ],
        faq: [
            .init(q: "I hit my goal — what now?",
                  a: "Mark it complete from the goal card. It moves to the archive but contribution history stays."),
            .init(q: "Can a goal go negative?",
                  a: "No. To 'unsave', delete the contribution from the goal's history."),
        ]
    )

    // MARK: Subscriptions

    private static let subscriptions = SectionHelp(
        screen: .subscriptions,
        tagline: "Find every recurring charge — Netflix, gym, that thing you forgot you signed up for.",
        heroIcon: "arrow.triangle.2.circlepath",
        heroTint: DS.Colors.warning,
        elevatorPitch: "Subscriptions auto-detects services billing you on a schedule and gives you one place to review them. Most people find €30+/month they didn't know about.",
        blocks: [
            .init(kind: .what, title: "Automatic detection",
                  body: "Centmond scans your transactions for repeating charges (same merchant, similar amount, regular interval) and surfaces them as subscription candidates."),
            .init(kind: .why, title: "Silent budget killers",
                  body: "A €9.99 charge feels like nothing. Twelve of them is €1,440 a year. The yearly summary shows the real cost."),
            .init(kind: .how, title: "Confirm or dismiss",
                  body: "Detected subs land in a review queue. Approve = added to forecasting. Dismiss = Centmond stops suggesting it."),
            .init(kind: .watchOut, title: "False positives",
                  body: "Variable bills (utilities, restaurants you frequent) sometimes get flagged. Dismiss them and Centmond learns."),
        ],
        steps: [
            .init(number: 1, title: "Run detection",
                  body: "Centmond scans automatically. Open the Detected tab to see new candidates with confidence scores.",
                  icon: "magnifyingglass.circle.fill"),
            .init(number: 2, title: "Review the list",
                  body: "For each candidate: Add (confirms it), Dismiss (ignores it), or tap to edit details before adding.",
                  icon: "checkmark.circle.fill"),
            .init(number: 3, title: "Add a manual sub",
                  body: "Use the + button for services Centmond hasn't detected yet — annual subs especially.",
                  icon: "plus.circle.fill"),
            .init(number: 4, title: "Forecast the year",
                  body: "The yearly cost card shows what your subs will run you over 12 months. Sobering.",
                  icon: "calendar.badge.clock"),
        ],
        proTips: [
            "Annual subs (insurance, domains) are detected by 12-month gaps — give it a year of data for best results.",
            "AI Chat: 'which subscriptions do I never use?' looks at last-charge dates.",
        ],
        faq: [
            .init(q: "It missed my Spotify charge.",
                  a: "Need at least 2–3 charges with similar amounts. Add it manually with the + button."),
            .init(q: "Free trials?",
                  a: "Set the next billing date to when the trial ends. Centmond will warn you a few days before."),
        ]
    )

    // MARK: Insights

    private static let insights = SectionHelp(
        screen: .insights,
        tagline: "Centmond watches your data and surfaces things worth knowing.",
        heroIcon: "lightbulb.fill",
        heroTint: DS.Colors.warning,
        elevatorPitch: "Insights are short, actionable nudges Centmond generates by watching for patterns: a category you blew past, a new big subscription, a streak worth celebrating, a bill that grew.",
        blocks: [
            .init(kind: .what, title: "Auto-generated cards",
                  body: "Detectors run on your data: spending spikes, budget overruns, new subscriptions, savings streaks, household imbalances, and more."),
            .init(kind: .why, title: "Surface what you'd miss",
                  body: "You can't watch every category every day. Insights are Centmond doing it for you — pinging only when something changed."),
            .init(kind: .how, title: "Engagement-gated",
                  body: "Dismiss an insight type once and Centmond shows you fewer of them. Act on one and that detector stays on."),
            .init(kind: .watchOut, title: "Not all are urgent",
                  body: "Some insights are FYI ('you spent 12% less on dining this month'). Color-coded — amber needs attention, blue is informational."),
        ],
        steps: [
            .init(number: 1, title: "Browse the cards",
                  body: "All active insights live here, grouped by domain (spending, budgets, subscriptions, household, goals).",
                  icon: "rectangle.grid.2x2.fill"),
            .init(number: 2, title: "Tap to act",
                  body: "Each insight has a deeplink — opens the relevant screen pre-filtered to the issue.",
                  icon: "hand.tap.fill"),
            .init(number: 3, title: "Dismiss noise",
                  body: "Swipe or X to dismiss. Centmond learns what you don't care about and shows less of it.",
                  icon: "xmark.circle.fill"),
        ],
        proTips: [
            "The dashboard advisor strip floats the most urgent ones to the top.",
            "AI Chat enriches insights — ask 'what's the story behind this insight?' for a longer explanation.",
            "Notifications can be enabled per-detector in Settings → Preferences.",
        ],
        faq: [
            .init(q: "Why fewer insights than before?",
                  a: "The auto-mute kicked in — Centmond noticed you weren't acting on a type and quieted it. Re-enable in Settings."),
            .init(q: "Custom insight rules?",
                  a: "Not yet — current insights are built-in detectors."),
        ]
    )

    // MARK: Analytics

    private static let analytics = SectionHelp(
        screen: .analytics,
        tagline: "Deeper charts: trends, breakdowns, forecasts. The 'show me the data' screen.",
        heroIcon: "chart.xyaxis.line",
        heroTint: DS.Colors.accent,
        elevatorPitch: "Analytics is for when the dashboard isn't enough. Range selector, multiple chart types, and category drilldowns — built for the days you want to dig.",
        blocks: [
            .init(kind: .what, title: "Six time ranges, multiple charts",
                  body: "Week, Month, 3M, 6M, Year, All. Each range refreshes every chart on this screen."),
            .init(kind: .why, title: "Trends, not snapshots",
                  body: "Single-month views miss the story. Looking at 6 months of dining spend tells you whether last month was a blip or a trend."),
            .init(kind: .how, title: "Tap a slice or bar",
                  body: "Most charts are interactive — tap a category, a bar, or a point to filter into the matching transactions."),
            .init(kind: .watchOut, title: "Forecasts get fuzzier far out",
                  body: "Months 1–3 are usually pretty accurate. Months 9–12 are vibes. Trust the near term, sanity-check the rest."),
        ],
        steps: [
            .init(number: 1, title: "Pick your range",
                  body: "Use the range selector at the top. Everything below recalculates instantly.",
                  icon: "calendar"),
            .init(number: 2, title: "Read the trends",
                  body: "Income vs spending, category breakdown, and per-day patterns each tell a different part of the story.",
                  icon: "chart.line.uptrend.xyaxis"),
            .init(number: 3, title: "Drill into a category",
                  body: "Tap any slice or bar to filter the transactions list to just those rows.",
                  icon: "hand.tap.fill"),
        ],
        proTips: [
            "Compare months by switching range — the chart titles always reflect the active range.",
            "AI Chat: 'what's driving my dining trend?' uses the same data shown here.",
        ],
        faq: [
            .init(q: "Why does my chart look empty?",
                  a: "Most likely no transactions in the selected range, or transactions are missing categories."),
        ]
    )

    // MARK: Household

    private static let household = SectionHelp(
        screen: .household,
        tagline: "Track who paid for what — and who owes who.",
        heroIcon: "person.2.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "Household turns 'wait, did you pay me back for that?' into a clean ledger. Add household members, share expenses, and Centmond shows debts in plain language.",
        blocks: [
            .init(kind: .what, title: "Members + shares + settlements",
                  body: "Add the people you split money with. Tag transactions as shared and pick the split. Record payments when someone settles up."),
            .init(kind: .why, title: "Stop doing math at dinner",
                  body: "No more spreadsheets, no more 'I think you owe me 12-ish'. The Who Owes Who panel says it directly."),
            .init(kind: .how, title: "Real ledger, not approximations",
                  body: "Every share is tracked at transaction-level. Settlements clamp to existing debts so you never go into reverse-debt accidentally."),
            .init(kind: .watchOut, title: "Roles matter",
                  body: "Each member has a role (owner, admin, member, child, view-only). Roles control what they can see or edit if they sync into the household."),
        ],
        steps: [
            .init(number: 1, title: "Create or join",
                  body: "Tap Create Household to start one, or Join with an invite code.",
                  icon: "person.crop.circle.badge.plus"),
            .init(number: 2, title: "Share a transaction",
                  body: "Open a transaction → Share Across Members. Pick equal split or custom percentages.",
                  icon: "rectangle.split.3x1.fill"),
            .init(number: 3, title: "Read 'Who Owes Who'",
                  body: "The hub shows direct statements: 'Ali owes you €25'. No mental math.",
                  icon: "arrow.left.arrow.right"),
            .init(number: 4, title: "Settle up",
                  body: "When someone pays you back, tap Settle Up. Centmond uses FIFO to clear the oldest debts first.",
                  icon: "checkmark.circle.fill"),
        ],
        proTips: [
            "Filter Transactions by household member to see only their stuff.",
            "Shared goals live here too — everyone's contributions count toward one target.",
        ],
        faq: [
            .init(q: "What if amounts don't quite balance after a settlement?",
                  a: "Centmond clamps settlements to existing debts. If something looks off, check the activity feed for the offending share."),
        ]
    )

    // MARK: More

    private static let more = SectionHelp(
        screen: .more,
        tagline: "Everything that doesn't fit on the main tabs — household, recurring, briefings, and more.",
        heroIcon: "ellipsis.circle.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "More is the launchpad for secondary surfaces: the monthly briefing, household, recurring, import — features you don't need every day, but want one tap away.",
        blocks: [
            .init(kind: .what, title: "Secondary surfaces",
                  body: "Monthly briefing, household, recurring, CSV import, review queue, and any beta features live here."),
            .init(kind: .why, title: "Keep the main tabs focused",
                  body: "Dashboard / Transactions / Budget / Insights are daily tools. Everything else lives here so they stay simple."),
            .init(kind: .how, title: "Each entry opens a full screen",
                  body: "Tap a row to drill into that surface. Most have their own help button at the top."),
            .init(kind: .watchOut, title: "Beta features marked clearly",
                  body: "A 'BETA' badge means it's still being polished. Useful, but expect the occasional rough edge."),
        ],
        steps: [
            .init(number: 1, title: "Browse the list",
                  body: "Each row links to a self-contained surface. Read the subtitle to know what's inside.",
                  icon: "list.bullet"),
            .init(number: 2, title: "Tap into one",
                  body: "Open it, use it, come back. Most surfaces remember your last state.",
                  icon: "arrow.right.circle.fill"),
        ],
        proTips: [
            "If you use a feature here daily, consider rearranging your nav from Settings.",
        ],
        faq: []
    )

    // MARK: Settings

    private static let settings = SectionHelp(
        screen: .settings,
        tagline: "Tune Centmond — currency, AI mode, theme, data, danger zone.",
        heroIcon: "gearshape.fill",
        heroTint: DS.Colors.subtext,
        elevatorPitch: "Settings is where you make Centmond yours. Pick your currency, manage notifications, tune the AI, and (carefully) wipe everything.",
        blocks: [
            .init(kind: .what, title: "Sections by topic",
                  body: "Profile, Centmond AI, Preferences, Privacy, Currency, Theme, Contact, Danger Zone — each lives in its own row or sheet."),
            .init(kind: .why, title: "Defaults that follow you",
                  body: "Setting your default currency here applies to every new transaction, report, and export. One source of truth."),
            .init(kind: .how, title: "Data is yours, always",
                  body: "Export everything as CSV. Import bank CSVs from Import. Centmond's data lives on your device and you fully own it."),
            .init(kind: .watchOut, title: "Danger Zone is real",
                  body: "Erase All Data wipes everything. There's no undo."),
        ],
        steps: [
            .init(number: 1, title: "Set your defaults",
                  body: "Tap Currency to pick your default. Theme switches between System / Light / Dark.",
                  icon: "slider.horizontal.3"),
            .init(number: 2, title: "Manage notifications",
                  body: "Preferences → Notifications controls which insights and reminders ping you.",
                  icon: "bell.badge.fill"),
            .init(number: 3, title: "Tune the AI",
                  body: "Centmond AI row: pick mode (Advisor / Assistant / Autopilot / CFO), tone, automation preferences.",
                  icon: "brain.head.profile.fill"),
            .init(number: 4, title: "Manage your data",
                  body: "Privacy snapshot shows what's stored. Import / export from More.",
                  icon: "square.and.arrow.up.on.square.fill"),
        ],
        proTips: [
            "Tap your name at the top to edit profile and sign out.",
            "Sample Data gives you a fully-populated demo set to play with.",
        ],
        faq: [
            .init(q: "Where does Centmond store my data?",
                  a: "In a local SwiftData store inside the app's container, plus optional sync via Supabase if you sign in."),
            .init(q: "Sync between devices?",
                  a: "Yes — sign in to enable cloud sync. Local-only mode also works."),
        ]
    )

    // MARK: AI Chat

    private static let aiChat = SectionHelp(
        screen: .aiChat,
        tagline: "Ask anything about your money. The AI runs on your iPhone — privately.",
        heroIcon: "brain.head.profile.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "Centmond AI is a private financial assistant that runs entirely on your iPhone. Nothing leaves your device. Ask questions, ask it to make changes, or just brainstorm — it knows your transactions, budgets, and goals.",
        blocks: [
            .init(kind: .what, title: "Local. Private. Yours.",
                  body: "The AI model lives on your phone. No cloud, no API calls. Airplane mode works."),
            .init(kind: .why, title: "It already knows the context",
                  body: "Ask 'what did I spend on coffee last month?' and it answers — because it has read access to your Centmond data."),
            .init(kind: .how, title: "It can take actions too",
                  body: "Ask it to create a budget, recategorize a transaction, or add a goal. It proposes the change as a card you Confirm or Reject before anything is written."),
            .init(kind: .watchOut, title: "Confirm every action",
                  body: "Action cards always need your approval — nothing happens silently. The AI can be wrong; double-check numbers it cites for important decisions."),
        ],
        steps: [
            .init(number: 1, title: "Start with a question",
                  body: "Try 'how much did I spend last week?' or 'am I on track for my emergency fund?' Plain language works.",
                  icon: "text.bubble.fill"),
            .init(number: 2, title: "Review action cards",
                  body: "If it suggests a change, an action card appears. Tap Confirm to apply, Reject to discard.",
                  icon: "checkmark.seal.fill"),
            .init(number: 3, title: "Patch with follow-ups",
                  body: "Said 'add €10 coffee'? Follow up with 'change date to yesterday' and the same card updates.",
                  icon: "arrow.triangle.2.circlepath"),
            .init(number: 4, title: "Keep chats organized",
                  body: "Open chat history (clock icon) to revisit past conversations or start a fresh chat for unrelated topics.",
                  icon: "clock.arrow.circlepath"),
        ],
        proTips: [
            "Suggested questions appear under the input — tap one if you're stuck.",
            "Long chats slow down — start a fresh chat for unrelated topics.",
            "The AI mode (Settings → Centmond AI) changes how chatty and proactive it is.",
        ],
        faq: [
            .init(q: "Does my data leave my phone?",
                  a: "No. The model is local. Centmond does not send your transactions or chat history to any AI server."),
            .init(q: "Why is the first answer slow?",
                  a: "The model loads into memory on first use. After that it stays warm and answers fast — and unloads automatically when idle to free RAM."),
            .init(q: "Can it delete things?",
                  a: "Only with your explicit Confirm tap. It cannot silently change or delete data."),
        ]
    )

    // MARK: Briefing

    private static let briefing = SectionHelp(
        screen: .briefing,
        tagline: "A monthly recap of your money — what changed, what to watch, what to celebrate.",
        heroIcon: "newspaper.fill",
        heroTint: DS.Colors.accent,
        elevatorPitch: "The Monthly Briefing is your end-of-month read. It pulls together income, spending, budgets, goals, and household activity into a single, scrollable story.",
        blocks: [
            .init(kind: .what, title: "Sections, urgent first",
                  body: "Each section covers one area — income, spending, budgets, goals, subscriptions, household. The most urgent ones float to the top."),
            .init(kind: .why, title: "End-of-month reflection",
                  body: "It's hard to look back without a structured view. The briefing forces a pause and shows what actually happened."),
            .init(kind: .how, title: "Tap to dig deeper",
                  body: "Each section is tappable — opens chat seeded with the relevant question, or jumps to the source screen."),
            .init(kind: .watchOut, title: "It's monthly, not real-time",
                  body: "The briefing reflects whichever month you've selected. Switch months at the top to see past briefings."),
        ],
        steps: [
            .init(number: 1, title: "Open from the dashboard",
                  body: "The briefing card on the dashboard is your entry point. Tap it any time mid-month for a preview.",
                  icon: "rectangle.stack.fill"),
            .init(number: 2, title: "Scroll the sections",
                  body: "Each card is self-contained. Read top-to-bottom for the full story.",
                  icon: "list.bullet.rectangle"),
            .init(number: 3, title: "Tap into chat",
                  body: "Use the section's tap target to ask AI a question seeded with that context.",
                  icon: "text.bubble.fill"),
        ],
        proTips: [
            "End of month is the best time to review and adjust budgets for next month.",
            "Streaks (like consecutive on-budget months) appear here when triggered.",
        ],
        faq: []
    )
}

// MARK: - Help button (the "?" toolbar icon)

struct SectionHelpButton: View {
    let screen: SectionHelpScreen
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext)
        }
        .accessibilityLabel("How does \(screen.displayName) work?")
        .sheet(isPresented: $isPresented) {
            if let help = SectionHelpLibrary.entry(for: screen) {
                SectionHelpSheet(help: help)
            } else {
                Text("No tutorial yet for \(screen.displayName).")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .padding()
                    .presentationDetents([.medium])
            }
        }
    }
}

// MARK: - Sheet (the modal tutorial)

struct SectionHelpSheet: View {
    let help: SectionHelp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    hero
                    pitch
                    blocksGrid
                    stepsSection
                    if !help.proTips.isEmpty { proTipsSection }
                    if !help.faq.isEmpty { faqSection }
                    footer
                }
                .padding(DS.Spacing.lg)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle(help.screen.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Colors.accent)
                }
            }
        }
    }

    // Hero banner

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [help.heroTint.opacity(0.55), help.heroTint.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Corners.lg, style: .continuous))

            HStack(alignment: .center, spacing: DS.Spacing.md) {
                Image(systemName: help.heroIcon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 4) {
                    Text(help.screen.displayName.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(help.tagline)
                        .font(DS.Typography.title)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Spacing.lg)
        }
        .frame(minHeight: 130)
    }

    private var pitch: some View {
        Text(help.elevatorPitch)
            .font(DS.Typography.body)
            .foregroundStyle(DS.Colors.subtext)
            .fixedSize(horizontal: false, vertical: true)
    }

    // 2-column grid

    private var blocksGrid: some View {
        let cols = [GridItem(.flexible(), spacing: DS.Spacing.md),
                    GridItem(.flexible(), spacing: DS.Spacing.md)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: DS.Spacing.md) {
            ForEach(help.blocks) { block in
                blockCard(block)
            }
        }
    }

    private func blockCard(_ block: SectionHelp.Block) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: block.kind.icon)
                    .font(.system(size: 11, weight: .bold))
                Text(block.kind.label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.0)
            }
            .foregroundStyle(block.kind.color)

            Text(block.title)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Colors.text)

            Text(block.body)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(DS.Spacing.md)
        .background(DS.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corners.md, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(block.kind.color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }

    // Numbered steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionHeader("How to use it", systemImage: "list.number")
            VStack(spacing: DS.Spacing.sm) {
                ForEach(help.steps) { step in
                    stepRow(step)
                }
            }
        }
    }

    private func stepRow(_ step: SectionHelp.Step) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            ZStack {
                Circle()
                    .fill(help.heroTint.opacity(0.18))
                Text("\(step.number)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(help.heroTint)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: step.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(help.heroTint)
                    Text(step.title)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Colors.text)
                }
                Text(step.body)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DS.Corners.md, style: .continuous))
    }

    // Pro tips

    private var proTipsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionHeader("Pro tips", systemImage: "sparkles")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(help.proTips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 4))
                            .foregroundStyle(DS.Colors.warning)
                            .padding(.top, 6)
                        Text(tip)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.warning.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: DS.Corners.md, style: .continuous))
        }
    }

    // FAQ

    private var faqSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            sectionHeader("Common questions", systemImage: "questionmark.bubble.fill")
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ForEach(help.faq) { qa in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(qa.q)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Colors.text)
                        Text(qa.a)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DS.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Corners.md, style: .continuous))
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 11))
            Text("Your data stays on your device.")
                .font(DS.Typography.caption)
        }
        .foregroundStyle(DS.Colors.textTertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 4)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(DS.Typography.section)
        }
        .foregroundStyle(DS.Colors.text)
    }
}
