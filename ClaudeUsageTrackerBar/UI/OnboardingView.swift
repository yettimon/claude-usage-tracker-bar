import SwiftUI

// MARK: - Root

struct OnboardingView: View {
    let onDismiss: () -> Void
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: OnboardingSlide1()
                case 1: OnboardingSlide2()
                case 2: OnboardingSlide3()
                case 3: OnboardingSlide4()
                default:
                    let _ = assertionFailure("Invalid onboarding step: \(step)")
                    OnboardingSlide1()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.2)

            OnboardingNavBar(
                step: step,
                totalSteps: 4,
                onBack: { step -= 1 },
                onNext: { step += 1 },
                onDismiss: onDismiss
            )
        }
        .frame(width: 480, height: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Nav bar

private struct OnboardingNavBar: View {
    let step: Int
    let totalSteps: Int
    let onBack: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            // Dot indicators
            HStack(spacing: 5) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }

            Spacer()

            if step > 0 {
                Button("← Back") { onBack() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if step < totalSteps - 1 {
                Button("Next →") { onNext() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12))
            } else {
                Button("Get Started") { onDismiss() }
                    .buttonStyle(.borderedProminent)
                    .font(.system(size: 12, weight: .semibold))
                    .tint(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Slide 1: Welcome

private struct OnboardingSlide1: View {
    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            Text("Welcome to Claude Usage Tracker")
                .font(.system(size: 18, weight: .bold))
                .multilineTextAlignment(.center)
            Text("A lightweight menu bar app that shows your Claude Code usage and costs — always one click away.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .padding(24)
    }
}

// MARK: - Slide 2: Usage & Costs

private struct OnboardingSlide2: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Usage & Costs")
                .font(.system(size: 15, weight: .semibold))
            Text("Reads Claude Code's local journal files — no account needed")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                Image("OnboardingPopup")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 75)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

                VStack(spacing: 7) {
                    OnboardingSectionCard(title: "TODAY",        cost: "$2.32",  tokens: "4.6M")
                    OnboardingSectionCard(title: "LAST 30 DAYS", cost: "$244",   tokens: "460M")
                    OnboardingSectionCard(title: "ALL TIME",     cost: "$254",   tokens: "478M")
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Slide 3: Quota Tracking

private struct OnboardingSlide3: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quota Tracking")
                .font(.system(size: 15, weight: .semibold))
            Text("Uses existing Claude Code OAuth credentials")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 14) {
                Image("OnboardingQuota")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)

                VStack(alignment: .leading, spacing: 10) {
                    OnboardingQuotaRow(label: "5-hour",  percent: 0.16, color: .green)
                    OnboardingQuotaRow(label: "Weekly",  percent: 0.13, color: .green)
                    Text("Run `claude auth login` to enable")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Slide 4: Get Started

private struct OnboardingSlide4: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("🎉")
                .font(.system(size: 36))
            Text("You're all set!")
                .font(.system(size: 17, weight: .bold))
            Text("Click the app icon in your menu bar to see your usage anytime.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            HStack(spacing: 6) {
                Text("💡")
                Text("Tip: Open **Settings** to show cost or tokens in the menu bar, customise the color, or enable launch at login.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 340)
        }
        .padding(24)
    }
}

// MARK: - Shared subviews

private struct OnboardingSectionCard: View {
    let title: String
    let cost: String
    let tokens: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            HStack {
                Text("Cost").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(cost).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(hex: "34C759"))
            }
            HStack {
                Text("Tokens").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text(tokens).font(.system(size: 10))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct OnboardingQuotaRow: View {
    let label: String
    let percent: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f%%", percent * 100))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2).fill(color)
                        .frame(width: geo.size.width * min(percent, 1.0))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}
