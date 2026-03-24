import SwiftUI

// MARK: - Simple Tutorial View
struct SimpleTutorialView: View {
    @ObservedObject var onboardingManager: OnboardingManager
    
    private let steps = [
        TutorialStep(
            icon: "plus.circle.fill",
            title: "Add Transactions",
            description: "Tap the + button to add your income and expenses easily",
            color: .green
        ),
        TutorialStep(
            icon: "chart.bar.fill",
            title: "View Dashboard",
            description: "See your spending overview and trends at a glance",
            color: .blue
        ),
        TutorialStep(
            icon: "target",
            title: "Set Budget",
            description: "Set monthly budgets to stay on track with your goals",
            color: .orange
        ),
        TutorialStep(
            icon: "lightbulb.fill",
            title: "Get Insights",
            description: "AI-powered insights about your spending patterns",
            color: .purple
        ),
        TutorialStep(
            icon: "icloud.fill",
            title: "Cloud Sync",
            description: "Your data syncs automatically across all devices",
            color: .cyan
        )
    ]
    
    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Tutorial")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    Spacer()

                    Button {
                        onboardingManager.skipOnboarding()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
                .padding()

                // Steps
                TabView(selection: $onboardingManager.currentStep) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        StepView(step: steps[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                // Bottom buttons
                HStack(spacing: 16) {
                    if onboardingManager.currentStep > 0 {
                        Button {
                            withAnimation {
                                onboardingManager.currentStep -= 1
                            }
                        } label: {
                            HStack {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundStyle(DS.Colors.accent)
                            .padding()
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation {
                            if onboardingManager.currentStep < steps.count - 1 {
                                onboardingManager.currentStep += 1
                            } else {
                                onboardingManager.completeOnboarding()
                            }
                        }
                    } label: {
                        HStack {
                            Text(onboardingManager.currentStep < steps.count - 1 ? "Next" : "Get Started")
                            if onboardingManager.currentStep < steps.count - 1 {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding()
            }
        }
    }
}

// MARK: - Tutorial Step Model
struct TutorialStep {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Step View
struct StepView: View {
    let step: TutorialStep

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            Image(systemName: step.icon)
                .font(.system(size: 80))
                .foregroundStyle(step.color)

            // Content
            VStack(spacing: 16) {
                Text(step.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .multilineTextAlignment(.center)

                Text(step.description)
                    .font(.system(size: 18))
                    .foregroundStyle(DS.Colors.subtext)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }
}

#Preview {
    SimpleTutorialView(onboardingManager: OnboardingManager.shared)
}
