import SwiftUI

// MARK: - Simple Tutorial View
struct SimpleTutorialView: View {
    @ObservedObject var onboardingManager: OnboardingManager

    private let steps = [
        TutorialStep(
            icon: "plus.circle.fill",
            title: "Add Transactions",
            description: "Tap the + button to add your income and expenses easily"
        ),
        TutorialStep(
            icon: "chart.bar.fill",
            title: "View Dashboard",
            description: "See your spending overview and trends at a glance"
        ),
        TutorialStep(
            icon: "target",
            title: "Set Budget",
            description: "Set monthly budgets to stay on track with your goals"
        ),
        TutorialStep(
            icon: "lightbulb.fill",
            title: "Get Insights",
            description: "AI-powered insights about your spending patterns"
        ),
        TutorialStep(
            icon: "icloud.fill",
            title: "Cloud Sync",
            description: "Your data syncs automatically across all devices"
        )
    ]

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Tutorial")
                        .font(DS.Typography.largeTitle)
                        .foregroundStyle(DS.Colors.text)

                    Spacer()

                    Button {
                        onboardingManager.skipOnboarding()
                    } label: {
                        Text("Skip")
                            .font(DS.Typography.body.weight(.medium))
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
                .padding()

                // Steps carousel
                TabView(selection: $onboardingManager.currentStep) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        StepView(step: steps[index], stepIndex: index, totalSteps: steps.count)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Custom page indicator
                HStack(spacing: 8) {
                    ForEach(0..<steps.count, id: \.self) { i in
                        Capsule()
                            .fill(i == onboardingManager.currentStep ? DS.Colors.accent : DS.Colors.grid)
                            .frame(width: i == onboardingManager.currentStep ? 24 : 8, height: 8)
                            .animation(DS.Animations.quick, value: onboardingManager.currentStep)
                    }
                }
                .padding(.bottom, 20)

                // Bottom buttons
                HStack(spacing: 16) {
                    if onboardingManager.currentStep > 0 {
                        Button {
                            withAnimation(DS.Animations.standard) {
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
                        withAnimation(DS.Animations.standard) {
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
                        .font(DS.Typography.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(DS.Colors.accent, in: RoundedRectangle(cornerRadius: DS.Corners.md, style: .continuous))
                    }
                    .buttonStyle(DS.ModernScaleButtonStyle())
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
}

// MARK: - Step View (Premium card-based)
struct StepView: View {
    let step: TutorialStep
    let stepIndex: Int
    let totalSteps: Int

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Card
            VStack(spacing: 24) {
                // Icon with accent background
                ZStack {
                    Circle()
                        .fill(DS.Colors.accent.opacity(0.12))
                        .frame(width: 100, height: 100)

                    Image(systemName: step.icon)
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(DS.Colors.accent)
                }

                // Content
                VStack(spacing: 12) {
                    Text(step.title)
                        .font(DS.Typography.largeTitle)
                        .foregroundStyle(DS.Colors.text)
                        .multilineTextAlignment(.center)

                    Text(step.description)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.subtext)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                // Step counter
                Text("\(stepIndex + 1) of \(totalSteps)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Corners.xl, style: .continuous)
                    .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Corners.xl, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.03),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 24)

            Spacer()
        }
    }
}

#Preview {
    SimpleTutorialView(onboardingManager: OnboardingManager.shared)
}
