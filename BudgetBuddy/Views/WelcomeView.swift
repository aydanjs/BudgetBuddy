import AuthenticationServices
import SwiftUI

/// Change this single value after the final app name is selected.
let appDisplayName = "Turtle Budgeting"

struct WelcomeView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var turtleProgress: CGFloat = 0
    @State private var revealName = false
    @State private var animationFinished = false

    private let swimDuration = 1.25
    private let nameRevealDuration = 0.30
    private let authenticationDelay = 0.32

    var body: some View {
        ZStack {
            Color.budgetBuddyBlue
                .ignoresSafeArea()

            bubbles

            VStack(spacing: 0) {
                swimScene
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard auth.hasAppleAccount, animationFinished, !auth.isUnlocked else { return }
                        Task { await auth.authenticateReturningUser() }
                    }
                if !auth.hasAppleAccount {
                    signInCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .onAppear(perform: startAnimation)
    }

    private var swimScene: some View {
        GeometryReader { proxy in
            let startY = proxy.size.height * 0.84
            let endY = proxy.size.height * 0.22
            let turtleY = startY + (endY - startY) * turtleProgress

            ZStack {
                Text(appDisplayName)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)
                    .opacity(revealName ? 1 : 0)
                    .scaleEffect(revealName ? 1 : 0.92)
                    .position(x: proxy.size.width / 2, y: proxy.size.height * 0.48)

                Image("TurtleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 176, height: 176)
                    .rotationEffect(.degrees(sin(Double(turtleProgress) * .pi * 4) * 4))
                    .position(x: proxy.size.width / 2, y: turtleY)
                    .accessibilityLabel("Turtle swimming upward")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var signInCard: some View {
        VStack(spacing: 14) {
            Text(auth.hasAppleAccount ? welcomeBackTitle : "Your financial plan, all in one place")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(auth.hasAppleAccount ? "Face ID will begin after the app name appears." : "Sign in securely to begin. Apple never shares your password with us.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                auth.completeAppleSignIn(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHint("Signs in without sharing your Apple password")

            if let message = auth.authenticationMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .background(.background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 20, y: 10)
    }

    private var bubbles: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                for index in 0..<30 {
                    let diameter = CGFloat(6 + (index * 11) % 16)
                    let xFraction = CGFloat((index * 37) % 101) / 100
                    let phase = Double((index * 29) % 100) / 100
                    let speed = 0.025 + Double(index % 5) * 0.006
                    let progress = (time * speed + phase).truncatingRemainder(dividingBy: 1)
                    let sway = sin(time * 0.7 + Double(index)) * 7
                    let x = size.width * xFraction + CGFloat(sway)
                    let y = size.height * (1 - CGFloat(progress))
                    let rect = CGRect(
                        x: x - diameter / 2,
                        y: y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                    context.stroke(
                        Path(ellipseIn: rect),
                        with: .color(.white.opacity(0.34)),
                        lineWidth: 1.2
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func startAnimation() {
        turtleProgress = 0
        revealName = false
        animationFinished = false
        withAnimation(.easeInOut(duration: swimDuration)) {
            turtleProgress = 1
        }
        Task {
            try? await Task.sleep(for: .seconds(swimDuration))
            withAnimation(.spring(response: nameRevealDuration, dampingFraction: 0.82)) {
                revealName = true
            }
            try? await Task.sleep(for: .seconds(authenticationDelay))
            animationFinished = true
            if auth.hasAppleAccount {
                await auth.authenticateReturningUser()
            }
        }
    }

    private var welcomeBackTitle: String {
        auth.displayName.isEmpty ? "Welcome back" : "Welcome back, \(auth.displayName)"
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: TransactionStore
    @EnvironmentObject private var auth: AuthSessionStore
    @State private var step = 0
    @State private var draft = OnboardingDraft()
    @State private var loadedExistingSettings = false
    @State private var showingBankConnection = false

    private let finalStep = 5

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    stepContent
                        .frame(maxWidth: 620)
                        .padding(.horizontal, 22)
                        .padding(.top, 24)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                }
                navigationButtons
            }
        }
        .onAppear {
            guard !loadedExistingSettings else { return }
            draft = OnboardingDraft(settings: store.settings)
            loadedExistingSettings = true
        }
        .sheet(isPresented: $showingBankConnection) {
            NavigationStack {
                PlaidConnectionView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingBankConnection = false }
                        }
                    }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image("TurtleLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 34, height: 34)
                    Text(appDisplayName)
                        .font(.headline)
                }
                Spacer()
                Button("Skip tutorial") {
                    auth.completeOnboarding()
                }
                .font(.subheadline.weight(.semibold))
            }

            HStack(spacing: 7) {
                ForEach(0...finalStep, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Color.budgetBuddyBlue : Color.secondary.opacity(0.18))
                        .frame(height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup step \(step + 1) of \(finalStep + 1)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(.background)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 0: welcomeStep
        case 1: incomeStep
        case 2: housingStep
        case 3: balancesStep
        case 4: bankStep
        default: reviewStep
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Image("TurtleLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .padding(18)
                .background(Color.budgetBuddyBlue, in: RoundedRectangle(cornerRadius: 34, style: .continuous))

            VStack(spacing: 10) {
                Text("Let's build your starting plan")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Answer a few simple questions so your dashboard and forecasts begin with numbers that make sense for you.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                OnboardingBenefit(symbol: "banknote.fill", title: "Set up your income", detail: "Use hourly pay or the amount from each paycheck.")
                OnboardingBenefit(symbol: "house.fill", title: "Add your housing", detail: "Choose rent, mortgage, or neither.")
                OnboardingBenefit(symbol: "chart.line.uptrend.xyaxis", title: "Start your forecast", detail: "Add today's balances and monthly goals.")
            }
            .onboardingCard()

            Text("Everything can be changed later in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var incomeStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingTitle(
                title: "How do you get paid?",
                subtitle: "Use the option that is easiest for you to answer."
            )

            VStack(spacing: 18) {
                Picker("Income type", selection: $draft.incomeType) {
                    Text("Salary").tag(IncomeType.salary)
                    Text("Hourly").tag(IncomeType.hourly)
                }
                .pickerStyle(.segmented)

                if draft.incomeType == .hourly {
                    OnboardingValueRow(title: "Hourly rate", value: $draft.hourlyRate, prefix: "$", suffix: "/hr")
                    OnboardingValueRow(title: "Hours per week", value: $draft.hoursPerWeek)
                    OnboardingValueRow(title: "Estimated tax rate", value: percentage($draft.taxRate), suffix: "%")
                } else {
                    OnboardingValueRow(title: "Take-home pay per paycheck", value: $draft.takeHomePaycheck, prefix: "$")
                    Text("Enter the amount that usually reaches your bank after taxes and deductions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("How often are you paid?")
                        .font(.subheadline.weight(.semibold))
                    Picker("Pay frequency", selection: $draft.payFrequency) {
                        ForEach(PayFrequency.allCases) { frequency in
                            Text(frequency.rawValue).tag(frequency)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onboardingCard()

            OnboardingEstimate(
                label: "Estimated monthly take-home",
                value: draft.monthlyIncome
            )
        }
    }

    private var housingStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingTitle(
                title: "What is your housing situation?",
                subtitle: "This becomes part of your monthly spending plan."
            )

            VStack(spacing: 18) {
                Picker("Housing", selection: $draft.housingType) {
                    ForEach(HousingType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                switch draft.housingType {
                case .rent:
                    OnboardingValueRow(title: "Monthly rent", value: $draft.housingPayment, prefix: "$")
                case .mortgage:
                    OnboardingValueRow(title: "Monthly mortgage payment", value: $draft.housingPayment, prefix: "$")
                    OnboardingValueRow(title: "Remaining balance", value: $draft.mortgageBalance, prefix: "$")
                    OnboardingValueRow(title: "Interest rate", value: percentage($draft.mortgageInterestRate), suffix: "%")
                    OnboardingValueRow(title: "Years remaining", value: $draft.mortgageYearsRemaining)
                case .neither:
                    Label("No housing payment will be added to your plan.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.budgetBuddyGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onboardingCard()
        }
    }

    private var balancesStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingTitle(
                title: "Where are you starting?",
                subtitle: "Use current balances only. Forecasted growth is never counted as money you already have."
            )

            VStack(spacing: 18) {
                OnboardingValueRow(title: "Cash and savings today", value: $draft.currentSavings, prefix: "$")
                OnboardingValueRow(title: "Investments today", value: $draft.investmentBalance, prefix: "$")
            }
            .onboardingCard()

            VStack(spacing: 18) {
                OnboardingValueRow(title: "Monthly cash savings", value: $draft.monthlySavingsContribution, prefix: "$")
                OnboardingValueRow(title: "Monthly investing", value: $draft.monthlyInvestmentContribution, prefix: "$")
                OnboardingValueRow(title: "Savings goal from income", value: percentage($draft.savingsRate), suffix: "%")
            }
            .onboardingCard()

            Text("Monthly contributions are amounts you plan to add in the future. They are kept separate from today's balances.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingTitle(
                title: "Your starting plan",
                subtitle: "Review the basics. You can fine-tune categories and forecasts later."
            )

            VStack(spacing: 0) {
                OnboardingReviewRow(title: "Monthly take-home", value: draft.monthlyIncome.currencyText)
                Divider()
                OnboardingReviewRow(title: draft.housingTitle, value: draft.housingPayment.currencyText)
                Divider()
                OnboardingReviewRow(title: "Money today", value: draft.totalMoney.currencyText)
                Divider()
                OnboardingReviewRow(title: "Monthly contributions", value: draft.totalMonthlyContributions.currencyText)
                Divider()
                OnboardingReviewRow(title: "Savings goal", value: draft.savingsRate.percentText)
            }
            .onboardingCard()

            Label("Your dashboard will use actual transactions as you add or import them.", systemImage: "checkmark.shield.fill")
                .font(.subheadline)
                .foregroundStyle(Color.budgetBuddyGreen)
        }
    }

    private var bankStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingTitle(
                title: "Bring in your bank activity",
                subtitle: "Connecting a bank is optional. It can automatically bring transactions into your budget so you do less manual entry."
            )

            VStack(spacing: 18) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.budgetBuddyBlue)
                    .frame(width: 88, height: 88)
                    .background(Color.budgetBuddyBlue.opacity(0.12), in: Circle())

                VStack(spacing: 8) {
                    Text("Secure bank connection")
                        .font(.title3.bold())
                    Text("Plaid handles the bank login screen. Turtle Budgeting never receives or stores your bank username or password.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button {
                    showingBankConnection = true
                } label: {
                    Label("Connect a bank", systemImage: "link")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.budgetBuddyGreen)
                .controlSize(.large)

                Button("Skip for now") {
                    withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .onboardingCard()

            Label("You can connect, reconnect, or disconnect accounts later from Settings.", systemImage: "gearshape.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var navigationButtons: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            if step != 4 {
                Button {
                    if step == finalStep {
                        saveAndFinish()
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                    }
                } label: {
                    HStack {
                        Text(step == finalStep ? "Finish setup" : step == 0 ? "Get started" : "Continue")
                        Image(systemName: step == finalStep ? "checkmark" : "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.budgetBuddyBlue)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func percentage(_ decimal: Binding<Decimal>) -> Binding<Decimal> {
        Binding(
            get: { decimal.wrappedValue * 100 },
            set: { decimal.wrappedValue = max(0, $0 / 100) }
        )
    }

    private func saveAndFinish() {
        store.updateSettings { settings in
            settings.incomeType = draft.incomeType
            settings.payFrequency = draft.payFrequency
            settings.hourlyRate = max(0, draft.hourlyRate)
            settings.hoursPerWeek = max(0, draft.hoursPerWeek)
            settings.takeHomePaycheck = max(0, draft.takeHomePaycheck)
            settings.taxRate = max(0, draft.taxRate)
            settings.housingType = draft.housingType
            settings.categoryBudgets[TransactionCategory.rent.rawValue] = draft.housingType == .neither ? 0 : max(0, draft.housingPayment)
            settings.mortgageBalance = max(0, draft.mortgageBalance)
            settings.mortgageInterestRate = max(0, draft.mortgageInterestRate)
            settings.mortgageYearsRemaining = max(0, draft.mortgageYearsRemaining)
            settings.currentSavings = max(0, draft.currentSavings)
            settings.startingCash = max(0, draft.currentSavings)
            settings.investmentBalance = max(0, draft.investmentBalance)
            settings.monthlySavingsContribution = max(0, draft.monthlySavingsContribution)
            settings.monthlyInvestmentContribution = max(0, draft.monthlyInvestmentContribution)
            settings.savingsRate = max(0, draft.savingsRate)
        }
        auth.completeOnboarding()
    }
}

private struct OnboardingDraft {
    var incomeType: IncomeType = .salary
    var payFrequency: PayFrequency = .biweekly
    var hourlyRate: Decimal = 0
    var hoursPerWeek: Decimal = 0
    var takeHomePaycheck: Decimal = 0
    var taxRate: Decimal = 0
    var housingType: HousingType = .rent
    var housingPayment: Decimal = 0
    var mortgageBalance: Decimal = 0
    var mortgageInterestRate: Decimal = 0
    var mortgageYearsRemaining: Decimal = 0
    var currentSavings: Decimal = 0
    var investmentBalance: Decimal = 0
    var monthlySavingsContribution: Decimal = 0
    var monthlyInvestmentContribution: Decimal = 0
    var savingsRate: Decimal = 0

    init() {}

    init(settings: BudgetSettings) {
        incomeType = settings.incomeType == .paycheck ? .salary : settings.incomeType
        payFrequency = settings.payFrequency
        hourlyRate = settings.hourlyRate
        hoursPerWeek = settings.hoursPerWeek
        takeHomePaycheck = settings.takeHomePaycheck
        taxRate = settings.taxRate
        housingType = settings.housingType
        housingPayment = settings.categoryBudgets[TransactionCategory.rent.rawValue] ?? 0
        mortgageBalance = settings.mortgageBalance
        mortgageInterestRate = settings.mortgageInterestRate
        mortgageYearsRemaining = settings.mortgageYearsRemaining
        currentSavings = settings.currentSavings
        investmentBalance = settings.investmentBalance
        monthlySavingsContribution = settings.monthlySavingsContribution
        monthlyInvestmentContribution = settings.monthlyInvestmentContribution
        savingsRate = settings.savingsRate
    }

    var monthlyIncome: Decimal {
        switch incomeType {
        case .hourly:
            hourlyRate * hoursPerWeek * (52 / 12) * (1 - taxRate)
        case .salary, .paycheck:
            takeHomePaycheck * payFrequency.paymentsPerMonth
        }
    }

    var totalMoney: Decimal { currentSavings + investmentBalance }
    var totalMonthlyContributions: Decimal { monthlySavingsContribution + monthlyInvestmentContribution }
    var housingTitle: String {
        switch housingType {
        case .rent: "Monthly rent"
        case .mortgage: "Monthly mortgage"
        case .neither: "Housing payment"
        }
    }
}

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.largeTitle.bold())
            Text(subtitle).font(.body).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct OnboardingBenefit: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Color.budgetBuddyGreen)
                .frame(width: 40, height: 40)
                .background(Color.budgetBuddyGreen.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

private struct OnboardingValueRow: View {
    let title: String
    @Binding var value: Decimal
    var prefix = ""
    var suffix = ""
    @State private var focusRequest = false

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            Text(prefix).foregroundStyle(.secondary)
            EditableDecimalField(value: $value, width: 112, focusRequest: $focusRequest)
            Text(suffix).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusRequest = true }
    }
}

private struct OnboardingEstimate: View {
    let label: String
    let value: Decimal

    var body: some View {
        HStack {
            Label(label, systemImage: "equal.circle.fill")
            Spacer()
            Text(value, format: .currency(code: currencyCode)).bold()
        }
        .padding(16)
        .foregroundStyle(.white)
        .background(Color.budgetBuddyGreen.gradient, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct OnboardingReviewRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.semibold)
        }
        .padding(.vertical, 13)
    }
}

private extension View {
    func onboardingCard() -> some View {
        padding(18)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

private extension Decimal {
    var currencyText: String {
        formatted(.currency(code: currencyCode))
    }

    var percentText: String {
        formatted(.percent.precision(.fractionLength(0)))
    }
}
