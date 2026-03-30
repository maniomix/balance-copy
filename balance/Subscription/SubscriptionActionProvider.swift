import Foundation

// ============================================================
// MARK: - Subscription Action Provider
// ============================================================
//
// Curated metadata for common subscription services:
// cancel URLs, tier info, and categories.
//
// Used by SubscriptionDetailView to show actionable buttons
// ("Cancel", "Downgrade") and by the household mode to
// detect duplicate subscriptions across partners.
//
// ============================================================

struct SubscriptionServiceInfo {
    let name: String                       // canonical display name
    let matchPatterns: [String]            // lowercased merchant patterns to match
    let cancelURL: String?                 // direct link to cancel/manage page
    let category: SubscriptionCategory
    let tiers: [SubscriptionTier]          // known pricing tiers
}

struct SubscriptionTier {
    let name: String                       // "Basic", "Standard", "Premium"
    let monthlyPriceCents: Int             // cents
    let features: String                   // brief description
}

enum SubscriptionCategory: String, CaseIterable {
    case streaming = "Streaming"
    case music = "Music"
    case productivity = "Productivity"
    case cloud = "Cloud Storage"
    case fitness = "Fitness"
    case news = "News & Reading"
    case gaming = "Gaming"
    case food = "Food & Delivery"
    case finance = "Finance"
    case social = "Social"
    case shopping = "Shopping"
    case education = "Education"
    case other = "Other"
}

enum SubscriptionActionProvider {

    /// Look up service info by normalized merchant name.
    static func lookup(merchantName: String) -> SubscriptionServiceInfo? {
        let normalized = merchantName.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return services.first { service in
            service.matchPatterns.contains { pattern in
                normalized.contains(pattern)
            }
        }
    }

    /// All known services (for duplicate detection across household).
    static let services: [SubscriptionServiceInfo] = [
        // Streaming
        SubscriptionServiceInfo(
            name: "Netflix",
            matchPatterns: ["netflix"],
            cancelURL: "https://www.netflix.com/cancelplan",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Standard with Ads", monthlyPriceCents: 699, features: "HD, ads"),
                SubscriptionTier(name: "Standard", monthlyPriceCents: 1549, features: "HD, no ads, 2 screens"),
                SubscriptionTier(name: "Premium", monthlyPriceCents: 2299, features: "4K, 4 screens"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Disney+",
            matchPatterns: ["disney+", "disney plus", "disneyplus"],
            cancelURL: "https://www.disneyplus.com/account",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Basic", monthlyPriceCents: 799, features: "HD, ads"),
                SubscriptionTier(name: "Premium", monthlyPriceCents: 1399, features: "4K, no ads"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "HBO Max",
            matchPatterns: ["hbo", "max.com"],
            cancelURL: "https://www.max.com/account",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "With Ads", monthlyPriceCents: 999, features: "HD, ads"),
                SubscriptionTier(name: "Ad-Free", monthlyPriceCents: 1599, features: "HD, no ads"),
                SubscriptionTier(name: "Ultimate", monthlyPriceCents: 1999, features: "4K, no ads"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Hulu",
            matchPatterns: ["hulu"],
            cancelURL: "https://secure.hulu.com/account",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "With Ads", monthlyPriceCents: 799, features: "On-demand, ads"),
                SubscriptionTier(name: "No Ads", monthlyPriceCents: 1799, features: "On-demand, no ads"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Amazon Prime",
            matchPatterns: ["amazon prime", "amzn prime", "prime video"],
            cancelURL: "https://www.amazon.com/mc/pipelines/cancel",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 1499, features: "Full Prime benefits"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Apple TV+",
            matchPatterns: ["apple tv", "apple.com/bill"],
            cancelURL: "https://support.apple.com/en-us/HT202039",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 999, features: "Original content"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "YouTube Premium",
            matchPatterns: ["youtube premium", "youtube music", "google youtube"],
            cancelURL: "https://www.youtube.com/paid_memberships",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Individual", monthlyPriceCents: 1399, features: "Ad-free, downloads"),
                SubscriptionTier(name: "Family", monthlyPriceCents: 2299, features: "Up to 5 members"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Paramount+",
            matchPatterns: ["paramount"],
            cancelURL: "https://www.paramountplus.com/account/",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Essential", monthlyPriceCents: 599, features: "With ads"),
                SubscriptionTier(name: "With Showtime", monthlyPriceCents: 1199, features: "No ads, Showtime"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Peacock",
            matchPatterns: ["peacock"],
            cancelURL: "https://www.peacocktv.com/account/plans",
            category: .streaming,
            tiers: [
                SubscriptionTier(name: "Premium", monthlyPriceCents: 599, features: "With ads"),
                SubscriptionTier(name: "Premium Plus", monthlyPriceCents: 1199, features: "No ads"),
            ]
        ),

        // Music
        SubscriptionServiceInfo(
            name: "Spotify",
            matchPatterns: ["spotify"],
            cancelURL: "https://www.spotify.com/account/subscription/",
            category: .music,
            tiers: [
                SubscriptionTier(name: "Individual", monthlyPriceCents: 1099, features: "Ad-free music"),
                SubscriptionTier(name: "Duo", monthlyPriceCents: 1499, features: "2 accounts"),
                SubscriptionTier(name: "Family", monthlyPriceCents: 1699, features: "Up to 6 accounts"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Apple Music",
            matchPatterns: ["apple music"],
            cancelURL: "https://support.apple.com/en-us/HT202039",
            category: .music,
            tiers: [
                SubscriptionTier(name: "Individual", monthlyPriceCents: 1099, features: "Full catalog"),
                SubscriptionTier(name: "Family", monthlyPriceCents: 1699, features: "Up to 6 members"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Tidal",
            matchPatterns: ["tidal"],
            cancelURL: "https://tidal.com/settings",
            category: .music,
            tiers: [
                SubscriptionTier(name: "HiFi", monthlyPriceCents: 1099, features: "Lossless audio"),
            ]
        ),

        // Productivity
        SubscriptionServiceInfo(
            name: "Microsoft 365",
            matchPatterns: ["microsoft 365", "microsoft office", "ms 365", "office 365"],
            cancelURL: "https://account.microsoft.com/services",
            category: .productivity,
            tiers: [
                SubscriptionTier(name: "Personal", monthlyPriceCents: 699, features: "1 user, 1TB OneDrive"),
                SubscriptionTier(name: "Family", monthlyPriceCents: 999, features: "Up to 6 users"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Adobe Creative Cloud",
            matchPatterns: ["adobe", "creative cloud"],
            cancelURL: "https://account.adobe.com/plans",
            category: .productivity,
            tiers: [
                SubscriptionTier(name: "Photography", monthlyPriceCents: 999, features: "Photoshop + Lightroom"),
                SubscriptionTier(name: "All Apps", monthlyPriceCents: 5999, features: "Full suite"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Notion",
            matchPatterns: ["notion"],
            cancelURL: "https://www.notion.so/my-account",
            category: .productivity,
            tiers: [
                SubscriptionTier(name: "Plus", monthlyPriceCents: 1000, features: "Unlimited blocks"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Canva",
            matchPatterns: ["canva"],
            cancelURL: "https://www.canva.com/settings/billing-payments",
            category: .productivity,
            tiers: [
                SubscriptionTier(name: "Pro", monthlyPriceCents: 1299, features: "Brand kit, premium content"),
            ]
        ),

        // Cloud Storage
        SubscriptionServiceInfo(
            name: "iCloud+",
            matchPatterns: ["icloud", "apple.com/bill"],
            cancelURL: "https://support.apple.com/en-us/HT207594",
            category: .cloud,
            tiers: [
                SubscriptionTier(name: "50GB", monthlyPriceCents: 99, features: "50GB storage"),
                SubscriptionTier(name: "200GB", monthlyPriceCents: 299, features: "200GB, family sharing"),
                SubscriptionTier(name: "2TB", monthlyPriceCents: 999, features: "2TB storage"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Google One",
            matchPatterns: ["google one", "google storage"],
            cancelURL: "https://one.google.com/settings",
            category: .cloud,
            tiers: [
                SubscriptionTier(name: "100GB", monthlyPriceCents: 199, features: "100GB"),
                SubscriptionTier(name: "2TB", monthlyPriceCents: 999, features: "2TB + VPN"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Dropbox",
            matchPatterns: ["dropbox"],
            cancelURL: "https://www.dropbox.com/account/plan",
            category: .cloud,
            tiers: [
                SubscriptionTier(name: "Plus", monthlyPriceCents: 1199, features: "2TB storage"),
            ]
        ),

        // Fitness
        SubscriptionServiceInfo(
            name: "Apple Fitness+",
            matchPatterns: ["apple fitness", "fitness+"],
            cancelURL: "https://support.apple.com/en-us/HT202039",
            category: .fitness,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 999, features: "All workouts"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Peloton",
            matchPatterns: ["peloton"],
            cancelURL: "https://members.onepeloton.com/settings/subscription",
            category: .fitness,
            tiers: [
                SubscriptionTier(name: "App", monthlyPriceCents: 1299, features: "App-only classes"),
                SubscriptionTier(name: "All-Access", monthlyPriceCents: 4400, features: "Equipment + app"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Strava",
            matchPatterns: ["strava"],
            cancelURL: "https://www.strava.com/account",
            category: .fitness,
            tiers: [
                SubscriptionTier(name: "Subscriber", monthlyPriceCents: 1199, features: "Routes, analysis"),
            ]
        ),

        // News & Reading
        SubscriptionServiceInfo(
            name: "Apple News+",
            matchPatterns: ["apple news"],
            cancelURL: "https://support.apple.com/en-us/HT202039",
            category: .news,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 1299, features: "Premium articles"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "New York Times",
            matchPatterns: ["nytimes", "new york times", "nyt"],
            cancelURL: "https://myaccount.nytimes.com/seg/subscription",
            category: .news,
            tiers: [
                SubscriptionTier(name: "Basic", monthlyPriceCents: 400, features: "News articles"),
                SubscriptionTier(name: "All Access", monthlyPriceCents: 2500, features: "News + Games + Cooking"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Audible",
            matchPatterns: ["audible"],
            cancelURL: "https://www.audible.com/account/overview",
            category: .news,
            tiers: [
                SubscriptionTier(name: "Plus", monthlyPriceCents: 799, features: "Plus catalog"),
                SubscriptionTier(name: "Premium Plus", monthlyPriceCents: 1495, features: "1 credit + catalog"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Kindle Unlimited",
            matchPatterns: ["kindle unlimited", "kindle"],
            cancelURL: "https://www.amazon.com/hz/mycd/myx#/home/settings/payment",
            category: .news,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 1199, features: "Unlimited reading"),
            ]
        ),

        // Gaming
        SubscriptionServiceInfo(
            name: "Xbox Game Pass",
            matchPatterns: ["xbox", "game pass", "microsoft xbox"],
            cancelURL: "https://account.microsoft.com/services",
            category: .gaming,
            tiers: [
                SubscriptionTier(name: "Core", monthlyPriceCents: 999, features: "Online play + games"),
                SubscriptionTier(name: "Ultimate", monthlyPriceCents: 1999, features: "PC + console + cloud"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "PlayStation Plus",
            matchPatterns: ["playstation", "psn", "ps plus"],
            cancelURL: "https://store.playstation.com/subscriptions",
            category: .gaming,
            tiers: [
                SubscriptionTier(name: "Essential", monthlyPriceCents: 999, features: "Online play"),
                SubscriptionTier(name: "Premium", monthlyPriceCents: 1799, features: "Game catalog + streaming"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Apple Arcade",
            matchPatterns: ["apple arcade"],
            cancelURL: "https://support.apple.com/en-us/HT202039",
            category: .gaming,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 699, features: "200+ games"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Nintendo Switch Online",
            matchPatterns: ["nintendo"],
            cancelURL: "https://accounts.nintendo.com/shop/subscription",
            category: .gaming,
            tiers: [
                SubscriptionTier(name: "Individual", monthlyPriceCents: 399, features: "Online play"),
            ]
        ),

        // Food & Delivery
        SubscriptionServiceInfo(
            name: "DoorDash DashPass",
            matchPatterns: ["doordash", "dashpass"],
            cancelURL: "https://www.doordash.com/consumer/membership/",
            category: .food,
            tiers: [
                SubscriptionTier(name: "DashPass", monthlyPriceCents: 999, features: "Free delivery"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Uber One",
            matchPatterns: ["uber one", "uber eats"],
            cancelURL: "https://account.uber.com/spending",
            category: .food,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 999, features: "Free delivery + 5% off"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Instacart+",
            matchPatterns: ["instacart"],
            cancelURL: "https://www.instacart.com/store/account/instacart-plus",
            category: .food,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 999, features: "Free delivery"),
            ]
        ),

        // Finance & Security
        SubscriptionServiceInfo(
            name: "1Password",
            matchPatterns: ["1password"],
            cancelURL: "https://my.1password.com/settings/billing",
            category: .finance,
            tiers: [
                SubscriptionTier(name: "Individual", monthlyPriceCents: 299, features: "Password manager"),
                SubscriptionTier(name: "Families", monthlyPriceCents: 499, features: "Up to 5 members"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "NordVPN",
            matchPatterns: ["nordvpn", "nord vpn"],
            cancelURL: "https://my.nordaccount.com/dashboard/nordvpn/",
            category: .finance,
            tiers: [
                SubscriptionTier(name: "Plus", monthlyPriceCents: 1299, features: "VPN + malware protection"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "ExpressVPN",
            matchPatterns: ["expressvpn"],
            cancelURL: "https://www.expressvpn.com/subscriptions",
            category: .finance,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 1299, features: "VPN service"),
            ]
        ),

        // Shopping
        SubscriptionServiceInfo(
            name: "Walmart+",
            matchPatterns: ["walmart+", "walmart plus"],
            cancelURL: "https://www.walmart.com/account/wplus",
            category: .shopping,
            tiers: [
                SubscriptionTier(name: "Monthly", monthlyPriceCents: 1298, features: "Free delivery + fuel"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Costco",
            matchPatterns: ["costco"],
            cancelURL: nil,  // in-store only
            category: .shopping,
            tiers: [
                SubscriptionTier(name: "Gold Star", monthlyPriceCents: 500, features: "Warehouse access"),
                SubscriptionTier(name: "Executive", monthlyPriceCents: 1000, features: "2% cashback"),
            ]
        ),

        // Education
        SubscriptionServiceInfo(
            name: "ChatGPT Plus",
            matchPatterns: ["openai", "chatgpt"],
            cancelURL: "https://chat.openai.com/settings/subscription",
            category: .education,
            tiers: [
                SubscriptionTier(name: "Plus", monthlyPriceCents: 2000, features: "GPT-4, faster responses"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Claude Pro",
            matchPatterns: ["anthropic", "claude"],
            cancelURL: "https://claude.ai/settings/billing",
            category: .education,
            tiers: [
                SubscriptionTier(name: "Pro", monthlyPriceCents: 2000, features: "Extended usage"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "Duolingo",
            matchPatterns: ["duolingo"],
            cancelURL: "https://www.duolingo.com/settings/account",
            category: .education,
            tiers: [
                SubscriptionTier(name: "Super", monthlyPriceCents: 699, features: "No ads, unlimited hearts"),
            ]
        ),
        SubscriptionServiceInfo(
            name: "LinkedIn Premium",
            matchPatterns: ["linkedin"],
            cancelURL: "https://www.linkedin.com/mypreferences/d/manage-premium-subscription",
            category: .social,
            tiers: [
                SubscriptionTier(name: "Career", monthlyPriceCents: 2999, features: "InMail, insights"),
            ]
        ),

        // Social
        SubscriptionServiceInfo(
            name: "X Premium",
            matchPatterns: ["twitter", "x premium", "x.com"],
            cancelURL: "https://twitter.com/settings/manage_subscription",
            category: .social,
            tiers: [
                SubscriptionTier(name: "Basic", monthlyPriceCents: 300, features: "Edit posts"),
                SubscriptionTier(name: "Premium", monthlyPriceCents: 800, features: "Blue checkmark"),
                SubscriptionTier(name: "Premium+", monthlyPriceCents: 1600, features: "No ads"),
            ]
        ),
    ]
}
