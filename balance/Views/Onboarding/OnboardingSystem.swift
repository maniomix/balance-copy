import SwiftUI
import Combine

// MARK: - Onboarding Manager
@MainActor
class OnboardingManager: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false
    @AppStorage("onboardingStep") var currentStep = 0
    
    @Published var showOnboarding = false
    @Published var highlightedFeature: OnboardingFeature?
    
    static let shared = OnboardingManager()
    
    init() {} // ✅ حذف شد private
    
    func startOnboarding() {
        currentStep = 0
        showOnboarding = true
        highlightedFeature = OnboardingFeature.allSteps.first
        AnalyticsManager.shared.track(.onboardingStarted)
    }
    
    func nextStep() {
        currentStep += 1
        if currentStep >= OnboardingFeature.allSteps.count {
            completeOnboarding()
        } else {
            highlightedFeature = OnboardingFeature.allSteps[currentStep]
            AnalyticsManager.shared.track(.onboardingStepViewed(step: highlightedFeature?.rawValue ?? "unknown"))
        }
    }
    
    func skipOnboarding() {
        let stepName = (currentStep < OnboardingFeature.allSteps.count) ? OnboardingFeature.allSteps[currentStep].rawValue : "unknown"
        AnalyticsManager.shared.track(.onboardingSkipped(atStep: stepName))
        completeOnboarding()
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        showOnboarding = false
        highlightedFeature = nil
        AnalyticsManager.shared.track(.onboardingCompleted(stepsCount: OnboardingFeature.allSteps.count))
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        currentStep = 0
    }
}

// MARK: - Onboarding Features
enum OnboardingFeature: String, CaseIterable {
    case addTransaction
    case viewDashboard
    case setBudget
    case viewInsights
    case cloudSync
    case settings
    
    var title: String {
        switch self {
        case .addTransaction: return "Add Transaction"
        case .viewDashboard: return "Dashboard"
        case .setBudget: return "Set Budget"
        case .viewInsights: return "Insights"
        case .cloudSync: return "Cloud Sync"
        case .settings: return "Settings"
        }
    }
    
    var description: String {
        switch self {
        case .viewDashboard:
            return "See your spending overview, trends, and remaining budget at a glance."
        case .addTransaction:
            return "View all your transactions and tap + to add new ones. Track every transaction!"
        case .setBudget:
            return "Set monthly budgets to stay on track with your financial goals."
        case .viewInsights:
            return "Get AI-powered insights about your spending patterns and recommendations."
        case .cloudSync:
            return "Your data syncs automatically across all your devices securely."
        case .settings:
            return "Customize your app, manage account, and export your data."
        }
    }
    
    var icon: String {
        switch self {
        case .addTransaction: return "plus.circle.fill"
        case .viewDashboard: return "chart.bar.fill"
        case .setBudget: return "target"
        case .viewInsights: return "lightbulb.fill"
        case .cloudSync: return "icloud.fill"
        case .settings: return "gearshape.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .addTransaction: return .green
        case .viewDashboard: return .blue
        case .setBudget: return .orange
        case .viewInsights: return .purple
        case .cloudSync: return .cyan
        case .settings: return .gray
        }
    }
    
    var actionPrompt: String {
        switch self {
        case .viewDashboard:
            return "👉 Tap 'Dashboard' at the bottom"
        case .addTransaction:
            return "👉 Tap 'Transactions' at the bottom"
        case .setBudget:
            return "👉 Tap 'Budget' at the bottom"
        case .viewInsights:
            return "👉 Tap 'Insights' at the bottom"
        case .cloudSync:
            return "👉 Look at sync status above"
        case .settings:
            return "👉 Tap 'Settings' at the bottom"
        }
    }
    
    static var allSteps: [OnboardingFeature] {
        [.viewDashboard, .addTransaction, .setBudget, .viewInsights, .settings]
    }
}

// MARK: - Onboarding Overlay View
struct OnboardingOverlay: View {
    @ObservedObject var manager: OnboardingManager
    let feature: OnboardingFeature
    let targetRect: CGRect
    
    var body: some View {
        ZStack {
            // Dark overlay
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    manager.nextStep()
                }
            
            // Spotlight effect
            Rectangle()
                .fill(Color.clear)
                .frame(width: targetRect.width + 20, height: targetRect.height + 20)
                .position(x: targetRect.midX, y: targetRect.midY)
                .shadow(color: feature.color, radius: 20)
                .blendMode(.destinationOut)
            
            // Tooltip
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: feature.icon)
                        .font(.system(size: 32))
                        .foregroundColor(feature.color)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(feature.description)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .systemBackground))
                        .shadow(radius: 10)
                )
                
                HStack(spacing: 12) {
                    Button("Skip") {
                        manager.skipOnboarding()
                    }
                    .foregroundColor(.gray)
                    
                    Spacer()
                    
                    // Progress dots
                    HStack(spacing: 6) {
                        ForEach(0..<OnboardingFeature.allSteps.count, id: \.self) { index in
                            Circle()
                                .fill(index == manager.currentStep ? feature.color : Color.gray)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Spacer()
                    
                    Button {
                        manager.nextStep()
                    } label: {
                        Text(manager.currentStep == OnboardingFeature.allSteps.count - 1 ? "Done" : "Next")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(feature.color)
                            .cornerRadius(20)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
            .position(
                x: UIScreen.main.bounds.width / 2,
                y: targetRect.maxY + 150
            )
        }
        .compositingGroup()
    }
}

// MARK: - Tutorial Card View (برای Settings)
struct TutorialCardView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared

    var body: some View {
        Button {
            onboardingManager.resetOnboarding()
            onboardingManager.startOnboarding()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(DS.Colors.positive)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("View Tutorial")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(uiColor: .label))
                    
                    Text("Show onboarding again")
                        .font(.system(size: 13))
                        .foregroundColor(Color(uiColor: .secondaryLabel))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(uiColor: .secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - View Extension برای راحتی
extension View {
    func onboardingHighlight(
        feature: OnboardingFeature,
        manager: OnboardingManager,
        isActive: Bool
    ) -> some View {
        self.overlay {
            if isActive && manager.highlightedFeature == feature {
                GeometryReader { geometry in
                    let rect = geometry.frame(in: .global)
                    OnboardingOverlay(
                        manager: manager,
                        feature: feature,
                        targetRect: rect
                    )
                }
            }
        }
    }
}

// MARK: - Welcome Screen (اولین بار)
struct WelcomeView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App Icon
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 80))
                .foregroundStyle(DS.Colors.accent)

            VStack(spacing: 12) {
                Text("Welcome to Centmond!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                Text("Take control of your finances")
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Colors.subtext)
            }

            Spacer()

            VStack(spacing: 16) {
                Button {
                    onboardingManager.startOnboarding()
                } label: {
                    Text("Start Tutorial")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DS.PrimaryButton())

                Button {
                    onboardingManager.skipOnboarding()
                } label: {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
    }
}

#Preview {
    TutorialCardView()
}

