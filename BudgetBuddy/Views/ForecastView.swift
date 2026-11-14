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
    private var projectedSavings: Decimal {
        futureValue(balance: settings.currentSavings, monthly: settings.monthlySavingsContribution, annualRate: settings.savingsAPY, months: months)
    }
    private var projectedInvestments: Decimal {
        futureValue(balance: settings.investmentBalance, monthly: settings.monthlyInvestmentContribution, annualRate: selectedStockReturn, months: months)
    }
    private var totalContributed: Decimal {
        settings.currentSavings + settings.investmentBalance
            + (settings.monthlySavingsContribution + settings.monthlyInvestmentContribution) * Decimal(months)
    }
    private var projectedGrowth: Decimal { projectedSavings + projectedInvestments - totalContributed }
    private var savingsAdded: Decimal { settings.monthlySavingsContribution * Decimal(months) }
    private var investmentAdded: Decimal { settings.monthlyInvestmentContribution * Decimal(months) }
    private var savingsGrowth: Decimal { projectedSavings - settings.currentSavings - savingsAdded }
    private var investmentGrowth: Decimal { projectedInvestments - settings.investmentBalance - investmentAdded }
    private var purchaseMonths: Int {
        max(1, Calendar.current.dateComponents([.month], from: Date(), to: settings.bigPurchaseDate).month ?? 1)
    }
    private var savingsByPurchaseDate: Decimal {
        futureValue(balance: settings.currentSavings, monthly: settings.monthlySavingsContribution, annualRate: settings.savingsAPY, months: purchaseMonths)
    }
    private var purchaseGap: Decimal { settings.bigPurchaseCost - savingsByPurchaseDate }
    private var purchaseProgress: Double {
        guard settings.bigPurchaseCost > 0 else { return 0 }
        return min(1, max(0, double(savingsByPurchaseDate / settings.bigPurchaseCost)))
    }
    private var neededMonthlySavings: Decimal {
        guard settings.bigPurchaseCost > 0 else { return 0 }
        let monthlyRate = effectiveMonthlyRate(settings.savingsAPY)
        let growth = pow(1 + monthlyRate, Double(purchaseMonths))
        let amountAfterStartingSavings = max(0, double(settings.bigPurchaseCost) - double(settings.currentSavings) * growth)
        guard amountAfterStartingSavings > 0 else { return 0 }
        if monthlyRate == 0 { return Decimal(amountAfterStartingSavings / Double(purchaseMonths)) }
        return Decimal(amountAfterStartingSavings * monthlyRate / (growth - 1))
    }

    var body: some View {
        Form {
            Section {
                Picker("Forecast length", selection: $horizon) {
                    ForEach(ForecastHorizon.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Projected total in \(horizon.title.lowercased())")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    Text(projectedSavings + projectedInvestments, format: .currency(code: currencyCode))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    HStack {
                        Text("Contributed \(totalContributed, format: .currency(code: currencyCode))")
                        Spacer()
                        Text("Growth \(projectedGrowth, format: .currency(code: currencyCode))")
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .listRowBackground(LinearGradient(colors: [.budgetBuddyBlue, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .foregroundStyle(.white)
            }

            Section("Debt") {
                NavigationLink {
                    DebtPayoffView()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Debt Payoff", systemImage: "creditcard.fill")
                            .font(.headline)
                        Text("Track balances, interest, payments, and payoff dates")
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
                }
            }

            Section("Savings account") {
                ForecastMoneyRow(title: "Balance today", value: decimalBinding(\.currentSavings))
                Text("The amount currently in your savings account.")
                    .font(.caption).foregroundStyle(.secondary)
                ForecastMoneyRow(title: "Add each month", value: decimalBinding(\.monthlySavingsContribution))
                Text("How much you plan to deposit into savings every month.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("APY") { Text(settings.savingsAPY, format: .percent.precision(.fractionLength(1))).bold() }
                ForecastResultRow(title: "Projected in \(horizon.title.lowercased())", value: projectedSavings)
                ForecastBreakdown(
                    starting: settings.currentSavings,
                    added: savingsAdded,
                    growth: savingsGrowth
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
                ForecastMoneyRow(title: "Balance today", value: decimalBinding(\.investmentBalance))
                Text("The current value of your long-term stock investments.")
                    .font(.caption).foregroundStyle(.secondary)
                ForecastMoneyRow(title: "Invest each month", value: decimalBinding(\.monthlyInvestmentContribution))
                Text("How much new money you plan to invest every month.")
                    .font(.caption).foregroundStyle(.secondary)
                ForecastResultRow(title: "Projected in \(horizon.title.lowercased())", value: projectedInvestments)
                ForecastBreakdown(
                    starting: settings.investmentBalance,
                    added: investmentAdded,
                    growth: investmentGrowth
                )
                Text("Low, Base, and High rates are editable in Settings. Returns are estimates and can be negative; they are not guarantees.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Big Purchase") {
                TextField("Purchase name", text: stringBinding(\.bigPurchaseName))
                ForecastMoneyRow(title: "Target cost", value: decimalBinding(\.bigPurchaseCost))
                DatePicker("Target date", selection: dateBinding, in: Date()..., displayedComponents: .date)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Savings by target date")
                        Spacer()
                        Text(savingsByPurchaseDate, format: .currency(code: currencyCode)).bold()
                    }
                    ProgressView(value: purchaseProgress).tint(purchaseGap <= 0 ? .green : .orange)
                    HStack {
                        Text("\(purchaseMonths) months away")
                        Spacer()
                        if purchaseGap <= 0 {
                            Label("On track", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Text("\(purchaseGap, format: .currency(code: currencyCode)) short").foregroundStyle(.orange)
                        }
                    }
                    .font(.caption)
                }

                LabeledContent("Needed each month") {
                    Text(neededMonthlySavings, format: .currency(code: currencyCode)).bold()
                }
                Text("Big Purchase uses savings only. Investments stay separate for long-term goals.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("Forecasts assume end-of-month contributions and steady rates. Monthly rates use (1 + annual rate)^(1/12) − 1. Taxes, fees, and market changes are not included.")
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

    private func effectiveMonthlyRate(_ annualRate: Decimal) -> Double {
        pow(1 + double(annualRate), 1.0 / 12.0) - 1
    }

    private func futureValue(balance: Decimal, monthly: Decimal, annualRate: Decimal, months: Int) -> Decimal {
        let principal = double(balance)
        let contribution = double(monthly)
        let monthlyRate = effectiveMonthlyRate(annualRate)
        let growth = pow(1 + monthlyRate, Double(months))
        let contributions = monthlyRate == 0
            ? contribution * Double(months)
            : contribution * ((growth - 1) / monthlyRate)
        return Decimal(principal * growth + contributions)
    }

    private func double(_ value: Decimal) -> Double { NSDecimalNumber(decimal: value).doubleValue }

    private func decimalBinding(_ keyPath: WritableKeyPath<BudgetSettings, Decimal>) -> Binding<Decimal> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { newValue in
            store.updateSettings { $0[keyPath: keyPath] = max(0, newValue) }
        })
    }

    private func stringBinding(_ keyPath: WritableKeyPath<BudgetSettings, String>) -> Binding<String> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { newValue in
            store.updateSettings { $0[keyPath: keyPath] = newValue }
        })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { store.settings.bigPurchaseDate }, set: { newValue in
            store.updateSettings { $0.bigPurchaseDate = newValue }
        })
    }
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
        .navigationTitle("Debt Payoff")
        .toolbar {
            Button { editingDebt = Debt() } label: { Image(systemName: "plus") }
        }
        .sheet(item: $editingDebt) { debt in DebtEditorView(debt: debt) }
    }

    private var totalDebt: Decimal { store.settings.debts.reduce(0) { $0 + $1.balance } }
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

            if acceleratedResult.canPayOff {
                Text("Paid off in \(acceleratedResult.durationText) · \(acceleratedResult.totalInterest, format: .currency(code: currencyCode)) interest")
                    .font(.subheadline).foregroundStyle(Color.budgetBuddyBlue)
                if debt.extraPayment > 0 && minimumResult.canPayOff {
                    Text("Extra payment saves \(max(0, minimumResult.totalInterest - acceleratedResult.totalInterest), format: .currency(code: currencyCode)) and \(max(0, minimumResult.months - acceleratedResult.months)) months.")
                        .font(.caption).foregroundStyle(.green)
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Debt details") {
                    TextField("Name, such as My car", text: $debt.name)
                    Picker("Type", selection: $debt.type) {
                        ForEach(DebtType.allCases) { Text($0.rawValue).tag($0) }
                    }
                    DebtMoneyField(title: "Current balance", value: $debt.balance)
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
                        .disabled(debt.balance <= 0 || debt.minimumPayment <= 0)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Where that number comes from").font(.caption.bold())
            BreakdownLine(label: "Starting balance", value: starting)
            BreakdownLine(label: "Your contributions", value: added)
            BreakdownLine(label: "Estimated growth", value: growth)
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
