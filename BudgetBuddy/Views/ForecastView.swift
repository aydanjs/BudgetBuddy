import SwiftUI

struct ForecastView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var horizon: ForecastHorizon = .oneYear
    @State private var scenario: InvestmentScenario = .base

    private var settings: BudgetSettings { store.settings }
    private var months: Int { horizon.rawValue }
    private var selectedStockReturn: Decimal {
        switch scenario {
        case .low: settings.lowInvestmentReturn
        case .base: settings.baseInvestmentReturn
        case .high: settings.highInvestmentReturn
        }
    }
    private var projection: ForecastProjection {
        ForecastProjection.calculate(
            startingCash: store.currentCashBalance,
            startingInvestments: store.currentInvestmentBalance,
            monthlySavings: store.plannedSavingsContribution,
            monthlyInvestments: store.plannedInvestmentContribution,
            savingsAPY: settings.savingsAPY,
            investmentReturn: selectedStockReturn,
            months: months,
            goals: settings.savingsGoals
        )
    }
    private var projectedSavings: Decimal { projection.endingCash }
    private var projectedInvestments: Decimal { projection.endingInvestments }
    private var projectedGrowth: Decimal { projection.totalGrowth }
    private var savingsAdded: Decimal { store.plannedSavingsContribution * Decimal(months) }
    private var investmentAdded: Decimal { store.plannedInvestmentContribution * Decimal(months) }
    private var savingsGrowth: Decimal { projection.cashGrowth }
    private var investmentGrowth: Decimal { projection.investmentGrowth }

    var body: some View {
        Form {
            Section("Your financial foundation") {
                NavigationLink {
                    EmergencyFundView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Emergency Fund", systemImage: "cross.case.fill")
                            .font(.headline)
                        Text("Build a safety net for 3, 6, or 12 months of essential expenses")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if store.emergencyFundTarget > 0 {
                    ProgressView(value: store.emergencyFundProgress).tint(.budgetBuddyGreen)
                    LabeledContent("Protected") {
                        Text("\(settings.emergencyFundSaved.currencyText) of \(store.emergencyFundTarget.currencyText)").bold()
                    }
                } else {
                    Text("Start here before planning optional purchases. Your Emergency Fund always remains available and cannot be deleted like a regular goal.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Forecast length", selection: $horizon) {
                    ForEach(ForecastHorizon.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)

                NavigationLink {
                    ForecastDetailView(
                        projection: projection,
                        horizon: horizon,
                        scenario: scenario,
                        savingsAPY: settings.savingsAPY,
                        investmentReturn: selectedStockReturn
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Projected net worth in \(horizon.title.lowercased())")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                        Text(projection.total, format: .currency(code: currencyCode))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        HStack {
                            Text("Growth \(projectedGrowth, format: .currency(code: currencyCode))")
                            Spacer()
                            if projection.totalFutureExpenses > 0 {
                                Text("Future expenses −\(projection.totalFutureExpenses.currencyText)")
                            } else {
                                Text("No future expenses")
                            }
                        }
                        .font(.caption).foregroundStyle(.white.opacity(0.85))
                        Label("See where this estimate comes from", systemImage: "list.bullet.rectangle")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .listRowBackground(LinearGradient(colors: [.budgetBuddyBlue, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .foregroundStyle(.white)
            }

            Section("Debt & credit") {
                NavigationLink {
                    DebtPayoffView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Debt & Credit Cards", systemImage: "creditcard.fill")
                            .font(.headline)
                        Text("Track balances, payoff dates, and available card credit")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !settings.debts.isEmpty {
                    LabeledContent("Total balance") {
                        Text(settings.debts.reduce(0) { $0 + $1.balance }, format: .currency(code: currencyCode)).bold()
                    }
                    LabeledContent("Expected each month") {
                        Text(store.monthlyDebtPayments, format: .currency(code: currencyCode)).bold()
                    }
                    if totalAvailableCredit > 0 {
                        LabeledContent("Available credit") {
                            Text(totalAvailableCredit, format: .currency(code: currencyCode)).bold()
                        }
                    }
                }
            }

            Section("Savings account") {
                LabeledContent("Calculated balance today") {
                    Text(store.currentCashBalance, format: .currency(code: currencyCode)).bold()
                }
                Text("Starting cash plus recorded income and expenses. Change the starting balance in Settings if needed.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Monthly savings goal", selection: savingsModeBinding) {
                    ForEach(ContributionPlanMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                if settings.savingsContributionMode == .fixedAmount {
                    ForecastMoneyRow(title: "Save each month", value: decimalBinding(\.monthlySavingsContribution))
                } else if settings.savingsContributionMode == .percentage {
                    ForecastPercentRow(title: "Save from income", value: percentageBinding(\.savingsRate))
                } else {
                    LabeledContent("Available after the plan") {
                        Text(store.plannedSavingsContribution, format: .currency(code: currencyCode)).bold()
                    }
                }
                Text(savingsPlanExplanation)
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("APY") { Text(settings.savingsAPY, format: .percent.precision(.fractionLength(1))).bold() }
                ForecastResultRow(title: "Cash after future expenses", value: projectedSavings)
                ForecastBreakdown(
                    starting: store.currentCashBalance,
                    added: savingsAdded,
                    growth: savingsGrowth,
                    futureExpenses: projection.totalFutureExpenses
                )
            }

            Section("Long-term investments") {
                Picker("Stock outcome", selection: $scenario) {
                    ForEach(InvestmentScenario.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)

                LabeledContent("Selected annual return") {
                    Text(selectedStockReturn, format: .percent.precision(.fractionLength(1))).bold()
                }
                ForecastMoneyRow(title: "Balance today", value: investmentBalanceBinding)
                Text("This uses the investment balance from guided setup, so you do not need to enter it again.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Monthly investing goal", selection: investmentModeBinding) {
                    Text(ContributionPlanMode.percentage.rawValue).tag(ContributionPlanMode.percentage)
                    Text(ContributionPlanMode.fixedAmount.rawValue).tag(ContributionPlanMode.fixedAmount)
                }
                if settings.investmentContributionMode == .percentage {
                    ForecastPercentRow(title: "Invest from income", value: percentageBinding(\.investmentRate))
                } else {
                    ForecastMoneyRow(title: "Invest each month", value: decimalBinding(\.monthlyInvestmentContribution))
                }
                LabeledContent("Planned monthly investment") {
                    Text(store.plannedInvestmentContribution, format: .currency(code: currencyCode)).bold()
                }
                Text("Percentage goals automatically adjust when your expected monthly income changes.")
                    .font(.caption).foregroundStyle(.secondary)
                ForecastResultRow(title: "Projected in \(horizon.title.lowercased())", value: projectedInvestments)
                ForecastBreakdown(
                    starting: store.currentInvestmentBalance,
                    added: investmentAdded,
                    growth: investmentGrowth,
                    futureExpenses: 0
                )
                Text("Low, Base, and High rates are editable in Settings. Returns are estimates and can be negative; they are not guarantees.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Savings goals") {
                NavigationLink {
                    SavingsGoalsView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Goals & Vaults", systemImage: "target").font(.headline)
                        Text("Plan purchases, assign money, and include them in your forecast")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let goal = settings.savingsGoals.first {
                    ProgressView(value: goal.progress).tint(.budgetBuddyGreen)
                    LabeledContent(goal.name) {
                        Text("\(goal.savedAmount.currencyText) of \(goal.targetAmount.currencyText)").bold()
                    }
                }
            }

            Section("Advice & help") {
                NavigationLink {
                    BudgetAdviceView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Budgeting Advice", systemImage: "questionmark.bubble.fill").font(.headline)
                        Text("Simple guidance and a way to ask Turtle Budgeting a question")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Text("Forecasts assume end-of-month contributions and steady rates. Planned purchases are deducted in their target month. Monthly rates use (1 + annual rate)^(1/12) − 1. Taxes, fees, and market changes are not included.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape.fill") }
            }
        }
    }

    private func decimalBinding(_ keyPath: WritableKeyPath<BudgetSettings, Decimal>) -> Binding<Decimal> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { newValue in
            store.updateSettings { $0[keyPath: keyPath] = max(0, newValue) }
        })
    }

    private func percentageBinding(_ keyPath: WritableKeyPath<BudgetSettings, Decimal>) -> Binding<Decimal> {
        Binding(
            get: { store.settings[keyPath: keyPath] * 100 },
            set: { newValue in
                store.updateSettings { $0[keyPath: keyPath] = max(0, newValue / 100) }
            }
        )
    }

    private var savingsModeBinding: Binding<ContributionPlanMode> {
        Binding(
            get: { store.settings.savingsContributionMode },
            set: { mode in store.updateSettings { $0.savingsContributionMode = mode } }
        )
    }

    private var investmentModeBinding: Binding<ContributionPlanMode> {
        Binding(
            get: { store.settings.investmentContributionMode },
            set: { mode in store.updateSettings { $0.investmentContributionMode = mode } }
        )
    }

    private var investmentBalanceBinding: Binding<Decimal> {
        Binding(
            get: { store.currentInvestmentBalance },
            set: { value in
                store.updateSettings {
                    $0.investmentBalance = max(0, value)
                    $0.startingInvestmentBalance = max(0, value)
                    $0.lastLinkedInvestmentBalance = nil
                }
            }
        )
    }

    private var savingsPlanExplanation: String {
        switch settings.savingsContributionMode {
        case .automaticRemainder:
            return "Calculated from expected income minus planned expenses and planned investing. It changes automatically with your plan."
        case .percentage:
            return "A percentage works well when income varies from month to month."
        case .fixedAmount:
            return "Use a fixed amount when you want the same cash-savings target each month."
        }
    }

    private var totalAvailableCredit: Decimal {
        settings.debts.reduce(0) { $0 + ($1.availableCredit ?? 0) }
    }

}

private struct ForecastExpenseImpact: Identifiable, Hashable {
    let id: UUID
    let name: String
    let amount: Decimal
    let date: Date
    let monthNumber: Int
}

private struct ForecastProjection: Hashable {
    let startingCash: Decimal
    let startingInvestments: Decimal
    let monthlySavings: Decimal
    let monthlyInvestments: Decimal
    let months: Int
    let endingCash: Decimal
    let endingInvestments: Decimal
    let cashGrowth: Decimal
    let investmentGrowth: Decimal
    let futureExpenses: [ForecastExpenseImpact]

    var startingTotal: Decimal { startingCash + startingInvestments }
    var savingsAdded: Decimal { monthlySavings * Decimal(months) }
    var investmentsAdded: Decimal { monthlyInvestments * Decimal(months) }
    var totalGrowth: Decimal { cashGrowth + investmentGrowth }
    var totalFutureExpenses: Decimal { futureExpenses.reduce(0) { $0 + $1.amount } }
    var total: Decimal { endingCash + endingInvestments }

    static func calculate(
        startingCash: Decimal,
        startingInvestments: Decimal,
        monthlySavings: Decimal,
        monthlyInvestments: Decimal,
        savingsAPY: Decimal,
        investmentReturn: Decimal,
        months: Int,
        goals: [SavingsGoal],
        now: Date = Date()
    ) -> ForecastProjection {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let endDate = calendar.date(byAdding: .month, value: months, to: startOfToday) ?? now
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        let futureExpenses = goals
            .filter {
                $0.deductFromForecast && $0.targetAmount > 0 &&
                $0.targetDate >= startOfToday && $0.targetDate <= endDate
            }
            .map { goal in
                let goalMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: goal.targetDate)) ?? goal.targetDate
                let difference = calendar.dateComponents([.month], from: startOfMonth, to: goalMonth).month ?? 0
                return ForecastExpenseImpact(
                    id: goal.id,
                    name: goal.name,
                    amount: goal.targetAmount,
                    date: goal.targetDate,
                    monthNumber: min(months, max(1, difference))
                )
            }
            .sorted { $0.date < $1.date }

        let expensesByMonth = Dictionary(grouping: futureExpenses, by: \.monthNumber)
        let cashRate = effectiveMonthlyRate(savingsAPY)
        let investmentRate = effectiveMonthlyRate(investmentReturn)
        var cash = startingCash
        var investments = startingInvestments
        var cashGrowth: Decimal = 0
        var investmentGrowth: Decimal = 0

        if months > 0 {
            for month in 1...months {
                let cashInterest = Decimal(decimalDouble(max(0, cash)) * cashRate)
                let marketGrowth = Decimal(decimalDouble(max(0, investments)) * investmentRate)
                cashGrowth += cashInterest
                investmentGrowth += marketGrowth
                cash += cashInterest + monthlySavings
                investments += marketGrowth + monthlyInvestments
                cash -= expensesByMonth[month, default: []].reduce(0) { $0 + $1.amount }
            }
        }

        return ForecastProjection(
            startingCash: startingCash,
            startingInvestments: startingInvestments,
            monthlySavings: monthlySavings,
            monthlyInvestments: monthlyInvestments,
            months: months,
            endingCash: cash,
            endingInvestments: investments,
            cashGrowth: cashGrowth,
            investmentGrowth: investmentGrowth,
            futureExpenses: futureExpenses
        )
    }

    private static func effectiveMonthlyRate(_ annualRate: Decimal) -> Double {
        pow(1 + decimalDouble(annualRate), 1.0 / 12.0) - 1
    }

    private static func decimalDouble(_ value: Decimal) -> Double {
        NSDecimalNumber(decimal: value).doubleValue
    }
}

private struct ForecastDetailView: View {
    let projection: ForecastProjection
    let horizon: ForecastHorizon
    let scenario: InvestmentScenario
    let savingsAPY: Decimal
    let investmentReturn: Decimal

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Projected net worth")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                    Text(projection.total, format: .currency(code: currencyCode))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("Estimated \(horizon.title.lowercased()) from now")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .listRowBackground(
                    LinearGradient(
                        colors: [.budgetBuddyNavy, .budgetBuddyBlue, .budgetBuddyTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }

            Section("The calculation") {
                ForecastEquationRow(title: "Money today", value: projection.startingTotal)
                ForecastEquationRow(title: "Planned cash savings", value: projection.savingsAdded, showsPlus: true)
                ForecastEquationRow(title: "Planned investments", value: projection.investmentsAdded, showsPlus: true)
                ForecastEquationRow(title: "Estimated savings interest", value: projection.cashGrowth, showsPlus: true)
                ForecastEquationRow(title: "Estimated investment growth", value: projection.investmentGrowth, showsPlus: true)
                ForecastEquationRow(title: "Planned future expenses", value: -projection.totalFutureExpenses)
                LabeledContent("Projected total") {
                    Text(projection.total, format: .currency(code: currencyCode))
                        .font(.headline)
                        .foregroundStyle(Color.budgetBuddyBlue)
                }
            }

            Section("Future expenses included") {
                if projection.futureExpenses.isEmpty {
                    Text("No planned purchases fall inside this forecast. Add one in Goals & Vaults, or mark an existing goal as a planned purchase.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projection.futureExpenses) { expense in
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.minus")
                                .foregroundStyle(Color.budgetBuddyTeal)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(expense.name).font(.headline)
                                Text(expense.date, format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(-expense.amount, format: .currency(code: currencyCode))
                                .bold().foregroundStyle(.red)
                        }
                    }
                }
            }

            Section("Assumptions") {
                LabeledContent("Cash APY") {
                    Text(savingsAPY, format: .percent.precision(.fractionLength(1)))
                }
                LabeledContent("Stock scenario") { Text(scenario.title) }
                LabeledContent("Stock return") {
                    Text(investmentReturn, format: .percent.precision(.fractionLength(1)))
                }
                Text("Assigned goal money is still part of your cash today, so it is not subtracted until the planned purchase date. This avoids counting the same expense twice.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Forecast Breakdown")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ForecastEquationRow: View {
    let title: String
    let value: Decimal
    var showsPlus = false

    var body: some View {
        LabeledContent(title) {
            Text(prefix + magnitude.currencyText)
                .foregroundStyle(value < 0 ? .red : .primary)
        }
    }

    private var magnitude: Decimal { value < 0 ? -value : value }

    private var prefix: String {
        if value < 0 { return "−" }
        return showsPlus && value > 0 ? "+" : ""
    }
}

struct EmergencyFundView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var amount: Decimal = 0
    @State private var action: GoalFundingAction = .add

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Your safety net", systemImage: "cross.case.fill")
                        .font(.title2.bold())
                        .foregroundStyle(Color.budgetBuddyGreen)
                    Text("An emergency fund is money reserved for essentials if income stops or an unexpected cost arrives.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Set your target") {
                ForecastMoneyRow(title: "Essential expenses each month", value: monthlyExpensesBinding)
                Text("Include only what you would need to keep living: housing, groceries, utilities, transportation, insurance, and minimum debt payments.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Months protected", selection: monthsBinding) {
                    Text("3 months").tag(3)
                    Text("6 months").tag(6)
                    Text("12 months").tag(12)
                }
                .pickerStyle(.segmented)
                LabeledContent("Emergency fund target") {
                    Text(store.emergencyFundTarget, format: .currency(code: currencyCode)).bold()
                }
            }

            Section("Progress") {
                ProgressView(value: store.emergencyFundProgress).tint(.budgetBuddyGreen)
                LabeledContent("Protected so far") {
                    Text(store.settings.emergencyFundSaved, format: .currency(code: currencyCode)).bold()
                }
                LabeledContent("Still to build") {
                    Text(store.emergencyFundRemaining, format: .currency(code: currencyCode)).bold()
                }
                LabeledContent("Available to assign") {
                    Text(store.availableToAssignToGoals, format: .currency(code: currencyCode)).bold()
                }
            }

            Section("Assign money") {
                Picker("Action", selection: $action) {
                    ForEach(GoalFundingAction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Amount") {
                    HStack { Text("$"); EditableDecimalField(value: $amount, width: 120) }
                }
                Button(action == .add ? "Add to emergency fund" : "Remove from emergency fund") {
                    store.contributeToEmergencyFund(action == .add ? amount : -amount)
                    amount = 0
                }
                .disabled(
                    amount <= 0 || store.emergencyFundTarget <= 0 ||
                    (action == .add && (store.availableToAssignToGoals <= 0 || store.emergencyFundRemaining <= 0))
                )
            }

            Section {
                Text("Assigned money stays inside your total cash balance—it is simply marked as protected. Your Emergency Fund is a permanent part of the plan and cannot be deleted.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Emergency Fund")
    }

    private var monthlyExpensesBinding: Binding<Decimal> {
        Binding(
            get: { store.settings.emergencyMonthlyExpenses },
            set: { value in store.updateSettings { $0.emergencyMonthlyExpenses = max(0, value) } }
        )
    }

    private var monthsBinding: Binding<Int> {
        Binding(
            get: { store.settings.emergencyFundMonths },
            set: { value in store.updateSettings { $0.emergencyFundMonths = value } }
        )
    }
}

struct SavingsGoalsView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var editingGoal: SavingsGoal?
    @State private var fundingGoal: SavingsGoal?

    var body: some View {
        List {
            if store.settings.savingsGoals.isEmpty {
                ContentUnavailableView(
                    "No savings goals yet",
                    systemImage: "target",
                    description: Text("Create a goal for a trip, car, emergency fund, or anything worth working toward.")
                )
            } else {
                Section {
                    ForEach(store.settings.savingsGoals) { goal in
                        VStack(alignment: .leading, spacing: 10) {
                            Button { editingGoal = goal } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(goal.name).font(.headline)
                                        Text("Target \(goal.targetDate, format: .dateTime.month(.abbreviated).day().year())")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Label(
                                            goal.deductFromForecast ? "Planned purchase" : "Savings only",
                                            systemImage: goal.deductFromForecast ? "calendar.badge.minus" : "banknote.fill"
                                        )
                                        .font(.caption.bold())
                                        .foregroundStyle(goal.deductFromForecast ? Color.budgetBuddyTeal : .secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            ProgressView(value: goal.progress).tint(.budgetBuddyGreen)
                            HStack {
                                Text("\(goal.savedAmount.currencyText) saved")
                                Spacer()
                                Text("\(goal.remainingAmount.currencyText) to go")
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text("About \(neededMonthly(for: goal).currencyText)/month to reach the date")
                                    .font(.caption)
                                Spacer()
                                Button("Assign money") { fundingGoal = goal }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.budgetBuddyGreen)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onDelete(perform: store.deleteGoal)
                } footer: {
                    Text("Assigned money is earmarked inside your existing cash balance. A planned purchase lowers the forecast on its target date; a savings-only goal stays in your future net worth.")
                }
            }
        }
        .navigationTitle("Goals & Vaults")
        .toolbar {
            Button { editingGoal = SavingsGoal() } label: { Image(systemName: "plus") }
                .accessibilityLabel("Add savings goal")
        }
        .sheet(item: $editingGoal) { goal in
            NavigationStack { SavingsGoalEditor(goal: goal) }
        }
        .sheet(item: $fundingGoal) { goal in
            NavigationStack { GoalFundingView(goal: goal) }
        }
    }

    private func neededMonthly(for goal: SavingsGoal) -> Decimal {
        let months = max(1, Calendar.current.dateComponents([.month], from: Date(), to: goal.targetDate).month ?? 1)
        return goal.remainingAmount / Decimal(months)
    }
}

private struct SavingsGoalEditor: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    @State var goal: SavingsGoal

    var body: some View {
        Form {
            Section("Goal") {
                TextField("Name", text: $goal.name)
                LabeledContent("Target amount") {
                    HStack { Text("$"); EditableDecimalField(value: $goal.targetAmount, width: 120) }
                }
                DatePicker("Target date", selection: $goal.targetDate, in: Date()..., displayedComponents: .date)
            }
            Section("Forecast") {
                Toggle("Planned purchase", isOn: $goal.deductFromForecast)
                    .tint(.budgetBuddyGreen)
                Text(
                    goal.deductFromForecast
                        ? "The full target amount will leave your projected net worth in the target month. Money assigned to this goal is not deducted early."
                        : "Use this for money you plan to keep saved. It will remain part of your projected net worth."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if goal.savedAmount > 0 {
                Section {
                    LabeledContent("Already assigned") { Text(goal.savedAmount, format: .currency(code: currencyCode)).bold() }
                }
            }
        }
        .navigationTitle(goal.name.isEmpty ? "New Goal" : "Edit Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    goal.name = goal.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    goal.targetAmount = max(0, goal.targetAmount)
                    store.saveGoal(goal)
                    dismiss()
                }
                .disabled(goal.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || goal.targetAmount <= 0)
            }
        }
    }
}

private struct GoalFundingView: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal
    @State private var amount: Decimal = 0
    @State private var action: GoalFundingAction = .add

    var body: some View {
        Form {
            Section {
                LabeledContent("Available to assign") {
                    Text(store.availableToAssignToGoals, format: .currency(code: currencyCode)).bold()
                }
                Picker("Action", selection: $action) {
                    ForEach(GoalFundingAction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Amount") {
                    HStack { Text("$"); EditableDecimalField(value: $amount, width: 120) }
                }
            }
            Section {
                Text("This organizes money you already have. It does not create an expense or change your total balance.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    store.contribute(action == .add ? amount : -amount, to: goal.id)
                    dismiss()
                }
                .disabled(amount <= 0 || (action == .add && store.availableToAssignToGoals <= 0))
            }
        }
    }
}

private enum GoalFundingAction: String, CaseIterable, Identifiable {
    case add = "Add"
    case remove = "Remove"
    var id: Self { self }
}

struct DebtPayoffView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var editingDebt: Debt?

    var body: some View {
        List {
            if store.settings.debts.isEmpty {
                ContentUnavailableView("No debts added", systemImage: "creditcard", description: Text("Add a loan or credit card to calculate its payoff."))
            } else {
                Section {
                    LabeledContent("Total debt") {
                        Text(totalDebt, format: .currency(code: currencyCode)).bold()
                    }
                    LabeledContent("Monthly payments") {
                        Text(store.monthlyDebtPayments, format: .currency(code: currencyCode)).bold()
                    }
                    if totalAvailableCredit > 0 {
                        LabeledContent("Available credit") {
                            Text(totalAvailableCredit, format: .currency(code: currencyCode)).bold()
                        }
                    }
                }

                Section("Accounts") {
                    ForEach(store.settings.debts) { debt in
                        Button { editingDebt = debt } label: {
                            DebtSummaryRow(debt: debt)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: store.deleteDebt)
                }
            }

            Section {
                Text("Debt payments are included in expected monthly spending. Cars and mortgages are treated as loans; their property values are not included in net worth.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debt & Credit")
        .toolbar {
            Button { editingDebt = Debt() } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editingDebt) { debt in DebtEditorView(debt: debt) }
    }

    private var totalDebt: Decimal { store.settings.debts.reduce(0) { $0 + $1.balance } }
    private var totalAvailableCredit: Decimal { store.settings.debts.reduce(0) { $0 + ($1.availableCredit ?? 0) } }
}

private struct DebtSummaryRow: View {
    let debt: Debt
    private var minimumResult: PayoffResult { calculatePayoff(debt: debt, includeExtra: false) }
    private var acceleratedResult: PayoffResult { calculatePayoff(debt: debt, includeExtra: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(debt.name.isEmpty ? debt.type.rawValue : debt.name).font(.headline)
                    Text(debt.type.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(debt.balance, format: .currency(code: currencyCode)).bold()
            }
            HStack {
                Label("\(debt.apr, format: .percent.precision(.fractionLength(1))) APR", systemImage: "percent")
                Spacer()
                Text("\(debt.monthlyPayment, format: .currency(code: currencyCode))/mo")
            }
            .font(.caption).foregroundStyle(.secondary)

            if let availableCredit = debt.availableCredit, let creditLimit = debt.creditLimit {
                HStack {
                    Label("Available credit", systemImage: "creditcard.and.123")
                    Spacer()
                    Text(availableCredit, format: .currency(code: currencyCode)).bold()
                }
                .font(.subheadline)
                .foregroundStyle(Color.budgetBuddyGreen)

                Text("of \(creditLimit, format: .currency(code: currencyCode)) total limit")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if acceleratedResult.canPayOff {
                Text("Paid off in \(acceleratedResult.durationText) · \(acceleratedResult.totalInterest, format: .currency(code: currencyCode)) interest")
                    .font(.subheadline).foregroundStyle(Color.budgetBuddyBlue)
                if debt.extraPayment > 0 && minimumResult.canPayOff {
                    Text("Extra payment saves \(max(0, minimumResult.totalInterest - acceleratedResult.totalInterest), format: .currency(code: currencyCode)) and \(max(0, minimumResult.months - acceleratedResult.months)) months.")
                        .font(.caption).foregroundStyle(Color.budgetBuddyGreen)
                }
            } else {
                Text("Payment is too low to pay off this balance.")
                    .font(.subheadline).foregroundStyle(.red)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct DebtEditorView: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    @State var debt: Debt

    private var aprPercent: Binding<Decimal> {
        Binding(get: { debt.apr * 100 }, set: { debt.apr = max(0, $0 / 100) })
    }

    private var creditLimitBinding: Binding<Decimal> {
        Binding(
            get: { debt.creditLimit ?? 0 },
            set: { debt.creditLimit = max(0, $0) }
        )
    }

    private var canSave: Bool {
        if debt.type == .creditCard {
            guard let creditLimit = debt.creditLimit, creditLimit > 0 else { return false }
            return debt.balance <= creditLimit
        }
        return debt.balance > 0 && debt.minimumPayment > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Debt details") {
                    TextField("Name, such as My car", text: $debt.name)
                    Picker("Type", selection: $debt.type) {
                        ForEach(DebtType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DebtMoneyField(title: "Current balance", value: $debt.balance)
                    if debt.type == .creditCard {
                        DebtMoneyField(title: "Credit limit", value: creditLimitBinding)
                        if let available = debt.availableCredit {
                            LabeledContent("Available credit") {
                                Text(available, format: .currency(code: currencyCode)).bold()
                            }
                        }
                    }
                    HStack {
                        Text("APR")
                        Spacer()
                        EditableDecimalField(value: aprPercent, width: 75)
                        Text("%").foregroundStyle(.secondary)
                    }
                }
                Section("Monthly payment") {
                    DebtMoneyField(title: "Minimum payment", value: $debt.minimumPayment)
                    DebtMoneyField(title: "Extra payment", value: $debt.extraPayment)
                    LabeledContent("Total each month") {
                        Text(debt.monthlyPayment, format: .currency(code: currencyCode)).bold()
                    }
                }
                Section("Payoff estimate") {
                    let minimum = calculatePayoff(debt: debt, includeExtra: false)
                    let accelerated = calculatePayoff(debt: debt, includeExtra: true)
                    PayoffEstimateRow(title: "Minimum only", result: minimum)
                    PayoffEstimateRow(title: "With extra", result: accelerated)
                }
            }
            .navigationTitle(debt.name.isEmpty ? "Add Debt" : "Edit Debt")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveDebt(debt); dismiss() }
                        .disabled(!canSave)
                }
            }
        }
    }
}

private struct DebtMoneyField: View {
    let title: String
    @Binding var value: Decimal
    var body: some View {
        HStack { Text(title); Spacer(); Text("$").foregroundStyle(.secondary); EditableDecimalField(value: $value, width: 100) }
    }
}

private struct PayoffEstimateRow: View {
    let title: String
    let result: PayoffResult
    var body: some View {
        LabeledContent(title) {
            if result.canPayOff {
                VStack(alignment: .trailing) {
                    Text(result.durationText).bold()
                    Text("\(result.totalInterest, format: .currency(code: currencyCode)) interest")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Payment too low").foregroundStyle(.red)
            }
        }
    }
}

private struct PayoffResult {
    let months: Int
    let totalInterest: Decimal
    let canPayOff: Bool
    var durationText: String {
        let years = months / 12
        let remainingMonths = months % 12
        if years == 0 { return "\(remainingMonths) months" }
        if remainingMonths == 0 { return "\(years) years" }
        return "\(years)y \(remainingMonths)m"
    }
}

private func calculatePayoff(debt: Debt, includeExtra: Bool) -> PayoffResult {
    var balance = NSDecimalNumber(decimal: debt.balance).doubleValue
    let monthlyRate = NSDecimalNumber(decimal: debt.apr).doubleValue / 12
    let basePayment = debt.minimumPayment + (includeExtra ? debt.extraPayment : 0)
    let payment = NSDecimalNumber(decimal: basePayment).doubleValue
    guard balance > 0, payment > 0, monthlyRate == 0 || payment > balance * monthlyRate else {
        return PayoffResult(months: 0, totalInterest: 0, canPayOff: balance <= 0)
    }
    var months = 0
    var interestPaid = 0.0
    while balance > 0.005 && months < 1_200 {
        let interest = balance * monthlyRate
        interestPaid += interest
        balance = max(0, balance + interest - payment)
        months += 1
    }
    return PayoffResult(months: months, totalInterest: Decimal(interestPaid), canPayOff: balance <= 0.005)
}

private enum ForecastHorizon: Int, CaseIterable, Identifiable {
    case oneYear = 12
    case fiveYears = 60
    var id: Int { rawValue }
    var title: String { self == .oneYear ? "1 Year" : "5 Years" }
}

private enum InvestmentScenario: String, CaseIterable, Identifiable {
    case low, base, high
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

private struct ForecastMoneyRow: View {
    let title: String
    @Binding var value: Decimal

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text("$").foregroundStyle(.secondary)
            EditableDecimalField(value: $value, width: 90)
        }
    }
}

private struct ForecastPercentRow: View {
    let title: String
    @Binding var value: Decimal

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            EditableDecimalField(value: $value, width: 90)
            Text("%").foregroundStyle(.secondary)
        }
    }
}

private struct ForecastResultRow: View {
    let title: String
    let value: Decimal

    var body: some View {
        LabeledContent(title) {
            Text(value, format: .currency(code: currencyCode)).bold().foregroundStyle(Color.budgetBuddyBlue)
        }
    }
}

private struct ForecastBreakdown: View {
    let starting: Decimal
    let added: Decimal
    let growth: Decimal
    let futureExpenses: Decimal

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Where that number comes from").font(.caption.bold())
            BreakdownLine(label: "Starting balance", value: starting)
            BreakdownLine(label: "Your contributions", value: added)
            BreakdownLine(label: "Estimated growth", value: growth)
            if futureExpenses > 0 {
                BreakdownLine(label: "Planned future expenses", value: -futureExpenses)
            }
        }
        .padding(.top, 4)
    }
}

private struct BreakdownLine: View {
    let label: String
    let value: Decimal

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .currency(code: currencyCode))
                .foregroundStyle(value < 0 ? .red : .primary)
        }
        .font(.caption)
    }
}
