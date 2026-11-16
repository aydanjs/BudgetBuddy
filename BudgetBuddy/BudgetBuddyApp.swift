import SwiftUI

@main
struct BudgetBuddyApp: App {
    @StateObject private var store = TransactionStore()
    @StateObject private var auth = AuthSessionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(auth)
        }
    }
}

private struct LaunchAnimationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var hasStarted = false
    @State private var isSwimming = false
    @State private var titleMaterialization: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let turtleSize = min(proxy.size.width * 0.72, 290)
            let startY = proxy.size.height / 2 + turtleSize * 0.72
            let finishY = -(proxy.size.height * 0.22)

            ZStack {
                Color.budgetBuddyBlue
                    .ignoresSafeArea()

                ContinuousBubbles()

                ZStack {
                    titleText
                        .foregroundStyle(.white.opacity(0.62))
                        .blur(radius: 10 + (1 - titleMaterialization) * 12)
                        .scaleEffect(1.02 + (1 - titleMaterialization) * 0.05)
                        .opacity(sin(titleMaterialization * CGFloat.pi) * 0.72)

                    titleText
                        .foregroundStyle(.white)
                        .blur(radius: (1 - titleMaterialization) * 16)
                        .scaleEffect(1 + (1 - titleMaterialization) * 0.035)
                        .opacity(pow(titleMaterialization, 1.7))

                }
                    .accessibilityAddTraits(.isHeader)

                Image("TurtleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: turtleSize, height: turtleSize)
                    .offset(y: isSwimming ? finishY : startY)
                    .shadow(color: Color.budgetBuddyNavy.opacity(0.14), radius: 18, y: 10)
                    .accessibilityLabel("BudgetBuddy turtle swimming upward")
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .task { await playAnimation() }
    }

    private var titleText: some View {
        Text("Budget Buddy")
            .font(.custom("AvenirNext-DemiBold", size: 42, relativeTo: .largeTitle))
            .tracking(0.2 + (1 - titleMaterialization) * 3.8)
    }

    @MainActor
    private func playAnimation() async {
        guard !hasStarted else { return }
        hasStarted = true

        if reduceMotion {
            titleMaterialization = 1
            try? await Task.sleep(for: .seconds(1.2))
            onFinished()
            return
        }

        withAnimation(.timingCurve(0.32, 0.02, 0.18, 1, duration: 2.65)) {
            isSwimming = true
        }

        try? await Task.sleep(for: .seconds(1.35))
        withAnimation(.timingCurve(0.22, 0.05, 0.12, 1, duration: 1.30)) {
            titleMaterialization = 1
        }

        try? await Task.sleep(for: .seconds(1.80))
        onFinished()
    }
}

private struct ContinuousBubbles: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate

                for index in 0..<56 {
                    let seed = Double(index) * 12.9898
                    let horizontal = CGFloat(sin(seed) * 0.5 + 0.5)
                    let sizeSeed = CGFloat(sin(seed * 2.43) * 0.5 + 0.5)
                    let speed = 0.075 + (sin(seed * 1.37) * 0.5 + 0.5) * 0.075
                    let phase = sin(seed * 1.91) * 0.5 + 0.5
                    let progress = (time * speed + phase).truncatingRemainder(dividingBy: 1)
                    let bubbleSize = 4 + sizeSeed * 11
                    let x = size.width * (0.025 + horizontal * 0.95)
                        + sin(progress * .pi * 2 + seed) * 5
                    let y = size.height * (1.08 - progress * 1.18)
                    let fade = min(1, progress * 6) * min(1, (1 - progress) * 6)
                    let rect = CGRect(
                        x: x - bubbleSize / 2,
                        y: y - bubbleSize / 2,
                        width: bubbleSize,
                        height: bubbleSize
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.44 * fade)),
                        lineWidth: 1.25
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
