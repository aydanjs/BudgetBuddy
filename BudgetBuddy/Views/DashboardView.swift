import Charts
import SwiftUI
import UIKit

struct DashboardView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool
    @Binding var selectedTab: AppTab
    @Binding var transactionMonth: Date?
    @State private var showsInsightsTitle = true

    private var income: Decimal { store.actualIncome(in: Date()) }
    private var spending: Decimal { store.actualSpending(in: Date()) }
    private var remaining: Decimal { income - spending }
    private var currentWeek: BudgetWeek? { store.currentWeek() }
    private var currentWeekGoal: Decimal {
        guard let currentWeek else { return 0 }
        return store.weeklyFlexibleBudget(weekIndex: currentWeek.index, in: Date())
    }
    private var currentWeekSpent: Decimal {
        guard let currentWeek else { return 0 }
        return store.weeklyFlexibleSpending(weekIndex: currentWeek.index, in: Date())
    }
    private var currentWeekPace: Decimal {
        guard let currentWeek else { return 0 }
        let calendar = Calendar.current
        let totalDays = (calendar.dateComponents([.day], from: currentWeek.start, to: currentWeek.end).day ?? 0) + 1
        let elapsedDays = min(totalDays, max(1, (calendar.dateComponents([.day], from: currentWeek.start, to: Date()).day ?? 0) + 1))
        return totalDays > 0 ? currentWeekGoal * Decimal(elapsedDays) / Decimal(totalDays) : currentWeekGoal
    }
    private var budgetProgress: Double {
        guard store.totalPlannedSpending > 0 else { return 0 }
        return min(1, max(0, decimalDouble(spending / store.totalPlannedSpending)))
    }

    var body: some View {
        ScrollView {
            DashboardScrollObserver(showsExpandedHeader: $showsInsightsTitle)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 18) {
                welcomeHeader
                totalMoneyCard
                monthSummary
                weeklyGoalCard
                emergencyFundCard
                savingsGoalCard
                budgetProgressCard
                recentTransactions
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .toolbar {
            if showsInsightsTitle {
                ToolbarItem(placement: .topBarLeading) {
                    insightsNavigationLink(showsTitle: true)
                }
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    insightsNavigationLink(showsTitle: false)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddTransaction = true } label: { Image(systemName: "plus") }
            }
        }
    }

    private func insightsNavigationLink(showsTitle: Bool) -> some View {
        NavigationLink {
            InsightsView(
                showingAddTransaction: $showingAddTransaction,
                selectedTab: $selectedTab,
                transactionMonth: $transactionMonth
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.xyaxis.line")
                if showsTitle {
                    Text("Insights")
                }
            }
            .accessibilityLabel("Insights")
        }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your money at a glance")
                .font(.title2.bold())
            Text(Date(), format: .dateTime.month(.wide).year())
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var totalMoneyCard: some View {
        NavigationLink {
            NetWorthHistoryView()
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Total money", systemImage: "banknote.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
                Text(store.currentNetWorth, format: .currency(code: currencyCode))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                HStack(spacing: 18) {
                    BalanceDetail(title: "Cash", amount: store.currentCashBalance, symbol: "building.columns.fill")
                    BalanceDetail(title: "Investments", amount: store.currentInvestmentBalance, symbol: "chart.line.uptrend.xyaxis")
                }
                Text(store.settings.lastLinkedCashBalance == nil
                     ? "Starting balances plus recorded income and expenses · forecast returns are not included"
                     : "Latest linked cash balance plus your manual entries · imported bank activity is already included")
                    .font(.caption).foregroundStyle(.white.opacity(0.78))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(
                LinearGradient(colors: [.budgetBuddyNavy, .budgetBuddyBlue, .budgetBuddyTeal], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .shadow(color: Color.budgetBuddyBlue.opacity(0.18), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var monthSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This month").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                SummaryCard(title: "Income", amount: income, color: .budgetBuddyGreen, symbol: "plus")
                Button {
                    transactionMonth = Date()
                    selectedTab = .transactions
                } label: {
                    SummaryCard(title: "Expenses", amount: spending, color: .budgetBuddyBlue, symbol: "minus")
                }
                .buttonStyle(.plain)
            }
            HStack {
                Text("Kept after spending").font(.subheadline)
                Spacer()
                Text(remaining, format: .currency(code: currencyCode)).font(.headline)
                    .foregroundStyle(remaining >= 0 ? Color.budgetBuddyGreen : .red)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private var weeklyGoalCard: some View {
        Button { selectedTab = .budget } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("This week's spending goal", systemImage: "calendar.badge.clock").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }
                if let currentWeek { Text(currentWeek.title).font(.caption).foregroundStyle(.secondary) }
                ProgressView(value: weeklyProgress)
                    .tint(currentWeekSpent <= currentWeekPace ? .budgetBuddyGreen : .orange)
                HStack {
                    VStack(alignment: .leading) {
                        Text("Spent").font(.caption).foregroundStyle(.secondary)
                        Text(currentWeekSpent, format: .currency(code: currencyCode)).bold()
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Weekly goal").font(.caption).foregroundStyle(.secondary)
                        Text(currentWeekGoal, format: .currency(code: currencyCode)).bold()
                    }
                }
                Label(
                    currentWeekSpent <= currentWeekPace ? "On track · \((currentWeekGoal - currentWeekSpent).currencyText) left this week" : "\((currentWeekSpent - currentWeekPace).currencyText) ahead of today's pace",
                    systemImage: currentWeekSpent <= currentWeekPace ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                )
                .font(.subheadline.bold())
                .foregroundStyle(currentWeekSpent <= currentWeekPace ? Color.budgetBuddyGreen : .orange)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var savingsGoalCard: some View {
        if let goal = store.settings.savingsGoals.first {
            Button { selectedTab = .plan } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(goal.name, systemImage: "target").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }
                    ProgressView(value: goal.progress).tint(.budgetBuddyGreen)
                    HStack {
                        Text("\(goal.savedAmount.currencyText) saved")
                        Spacer()
                        Text("\(goal.remainingAmount.currencyText) to go")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.budgetBuddyGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
    }

    private var weeklyProgress: Double {
        guard currentWeekGoal > 0 else { return currentWeekSpent > 0 ? 1 : 0 }
        return min(1, max(0, decimalDouble(currentWeekSpent / currentWeekGoal)))
    }

    private var emergencyFundCard: some View {
        Button { selectedTab = .plan } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    Label("Emergency fund", systemImage: "cross.case.fill").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold())
                }

                if store.emergencyFundTarget > 0 {
                    ProgressView(value: store.emergencyFundProgress)
                        .tint(.budgetBuddyGreen)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Protected").font(.caption).foregroundStyle(.secondary)
                            Text(store.settings.emergencyFundSaved, format: .currency(code: currencyCode)).bold()
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(store.settings.emergencyFundMonths)-month target").font(.caption).foregroundStyle(.secondary)
                            Text(store.emergencyFundTarget, format: .currency(code: currencyCode)).bold()
                        }
                    }
                    Text("\(store.emergencyFundRemaining.currencyText) left to build your safety net")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Set a 3, 6, or 12-month safety target based on the expenses you need to live.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label("Set up your safety net", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.budgetBuddyGreen)
                }
            }
            .padding()
            .background(Color.budgetBuddyBlue.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var budgetProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Monthly spending plan").font(.headline)
                Spacer()
                Button("View budget") { selectedTab = .budget }.font(.subheadline)
            }
            ProgressView(value: budgetProgress)
                .tint(.budgetBuddyGreen)
            HStack {
                Text("\(spending, format: .currency(code: currencyCode)) spent")
                Spacer()
                Text("\(store.totalPlannedSpending, format: .currency(code: currencyCode)) planned")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent transactions").font(.headline)
                Spacer()
                Button("See all") {
                    transactionMonth = nil
                    selectedTab = .transactions
                }
                .font(.subheadline)
            }
            LazyVStack(spacing: 0) {
                ForEach(Array(store.transactions.prefix(3))) { transaction in
                    TransactionRow(transaction: transaction)
                    if transaction.id != store.transactions.prefix(3).last?.id { Divider().padding(.leading, 48) }
                }
            }
            .padding(.horizontal)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct DashboardScrollObserver: UIViewRepresentable {
    @Binding var showsExpandedHeader: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(showsExpandedHeader: $showsExpandedHeader)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        attachObserver(from: view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.showsExpandedHeader = $showsExpandedHeader
        attachObserver(from: uiView, coordinator: context.coordinator)
    }

    private func attachObserver(from view: UIView, coordinator: Coordinator) {
        DispatchQueue.main.async {
            var ancestor = view.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    coordinator.observe(scrollView)
                    return
                }
                ancestor = current.superview
            }
        }
    }

    final class Coordinator {
        var showsExpandedHeader: Binding<Bool>
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?

        init(showsExpandedHeader: Binding<Bool>) {
            self.showsExpandedHeader = showsExpandedHeader
        }

        func observe(_ scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            observation?.invalidate()
            self.scrollView = scrollView
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self, weak scrollView] _, _ in
                guard let self, let scrollView else { return }
                let topOffset = -scrollView.adjustedContentInset.top
                let shouldExpand = scrollView.contentOffset.y <= topOffset + 18
                guard self.showsExpandedHeader.wrappedValue != shouldExpand else { return }
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        self.showsExpandedHeader.wrappedValue = shouldExpand
                    }
                }
            }
        }

        deinit {
            observation?.invalidate()
        }
    }
}

private struct BalanceDetail: View {
    let title: String
    let amount: Decimal
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.white.opacity(0.78))
            Text(amount, format: .currency(code: currencyCode)).font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: Circle())
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: currencyCode))
                .font(.headline).lineLimit(1).minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct InsightsView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool
    @Binding var selectedTab: AppTab
    @Binding var transactionMonth: Date?
    @State private var selectedMonth = Date()
    @State private var viewMode: DashboardViewMode = .month
    @State private var averageMonths = 3

    private var actualIncome: Decimal { average(of: store.actualIncome(in:)) }
    private var actualSpending: Decimal { average(of: store.actualSpending(in:)) }
    private var actualLeft: Decimal { actualIncome - actualSpending }
    private var keptRate: Decimal { actualIncome > 0 ? actualLeft / actualIncome : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                periodControls
                monthlyActuals
                actualVsPlan
                netWorth
                categoryComparison
                recentTransactions
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
    }

    private var periodControls: some View {
        VStack(spacing: 12) {
            Picker("Dashboard period", selection: $viewMode) {
                ForEach(DashboardViewMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)

            if viewMode == .month {
                HStack {
                    Button { changeMonth(by: -1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(selectedMonth, format: .dateTime.month(.wide).year()).font(.headline)
                    Spacer()
                    Button { changeMonth(by: 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
                }
            } else {
                Picker("Average length", selection: $averageMonths) {
                    Text("3 months").tag(3)
                    Text("6 months").tag(6)
                    Text("12 months").tag(12)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var monthlyActuals: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewMode == .month ? "Monthly actuals" : "Monthly average").font(.headline)
            HStack(spacing: 10) {
                ActualCard(title: "Income", amount: actualIncome, color: .budgetBuddyGreen, symbol: "arrow.down.left")
                Button {
                    transactionMonth = viewMode == .month ? selectedMonth : nil
                    selectedTab = .transactions
                } label: {
                    ActualCard(title: "Spent", amount: actualSpending, color: .orange, symbol: "arrow.up.right")
                }
                .buttonStyle(.plain)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Left after spending").font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text(actualLeft, format: .currency(code: currencyCode)).font(.title2.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Kept after spending").font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text(keptRate, format: .percent.precision(.fractionLength(0))).font(.title2.bold())
                }
            }
            .padding()
            .foregroundStyle(.white)
            .background(Color.budgetBuddyBlue.gradient, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var actualVsPlan: some View {
        DashboardSection(title: "Actual vs expected", subtitle: viewMode == .month ? "For the selected month" : "Average actual compared with your monthly expectations") {
            Chart(comparisonData) { item in
                BarMark(x: .value("Amount", item.amount), y: .value("Metric", item.metric))
                    .foregroundStyle(by: .value("Type", item.type))
                    .position(by: .value("Type", item.type))
            }
            .chartForegroundStyleScale(["Actual": Color.budgetBuddyBlue, "Expected": Color.gray.opacity(0.55)])
            .chartXAxis { AxisMarks(format: .currency(code: currencyCode).precision(.fractionLength(0))) }
            .frame(height: 190)
        }
    }

    private var netWorth: some View {
        DashboardSection(title: "Net worth", subtitle: "Cash and stock investments") {
            HStack {
                Text(store.currentNetWorth, format: .currency(code: currencyCode))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Spacer()
                NavigationLink("History") { NetWorthHistoryView() }
                    .font(.subheadline)
            }
            Chart(yearToDateSnapshots) { snapshot in
                LineMark(x: .value("Month", snapshot.date), y: .value("Net worth", decimalDouble(snapshot.total)))
                    .foregroundStyle(Color.budgetBuddyBlue)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Month", snapshot.date), y: .value("Net worth", decimalDouble(snapshot.total)))
                    .foregroundStyle(Color.budgetBuddyBlue)
            }
            .chartYAxis { AxisMarks(format: .currency(code: currencyCode).precision(.fractionLength(0))) }
            .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 170)
            Text("Calculated from your starting balances and every recorded income and expense.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var categoryComparison: some View {
        DashboardSection(title: "Spending by category", subtitle: "Actual compared with budget") {
            VStack(spacing: 16) {
                ForEach(displayedCategories) { category in
                    CategoryComparisonRow(
                        category: category,
                        actual: average(of: { store.actualSpending(for: category, in: $0) }),
                        budget: store.budget(for: category, in: selectedMonth)
                    )
                }
            }
        }
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent transactions").font(.title3.bold())
                Spacer()
                Button("See all") {
                    transactionMonth = viewMode == .month ? selectedMonth : nil
                    selectedTab = .transactions
                }
                .font(.subheadline)
            }
            LazyVStack(spacing: 0) {
                ForEach(recentItems) { transaction in
                    TransactionRow(transaction: transaction)
                    if transaction.id != recentItems.last?.id { Divider().padding(.leading, 48) }
                }
            }
            .padding(.horizontal)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private var monthsToAverage: [Date] {
        (1...averageMonths).compactMap { Calendar.current.date(byAdding: .month, value: -$0, to: Date()) }
    }

    private func average(of value: (Date) -> Decimal) -> Decimal {
        if viewMode == .month { return value(selectedMonth) }
        return monthsToAverage.reduce(0) { $0 + value($1) } / Decimal(averageMonths)
    }

    private func changeMonth(by amount: Int) {
        guard let changed = Calendar.current.date(byAdding: .month, value: amount, to: selectedMonth) else { return }
        selectedMonth = min(changed, Date())
    }

    private var comparisonData: [ComparisonItem] {
        [
            .init(metric: "Income", type: "Actual", amount: decimalDouble(actualIncome)),
            .init(metric: "Income", type: "Expected", amount: decimalDouble(store.plannedNetIncome)),
            .init(metric: "Spending", type: "Actual", amount: decimalDouble(actualSpending)),
            .init(metric: "Spending", type: "Expected", amount: decimalDouble(store.totalPlannedSpending)),
            .init(metric: "Left", type: "Actual", amount: decimalDouble(actualLeft)),
            .init(metric: "Left", type: "Expected", amount: decimalDouble(store.plannedSavings))
        ]
    }

    private var displayedCategories: [TransactionCategory] {
        store.expenseCategories.filter { category in
            category != .tithing && (
                store.budget(for: category, in: selectedMonth) > 0 || average(of: { store.actualSpending(for: category, in: $0) }) > 0
            )
        }
    }

    private var yearToDateSnapshots: [NetWorthSnapshot] {
        let year = Calendar.current.component(.year, from: Date())
        return store.calculatedNetWorthSnapshots.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    private var recentItems: [Transaction] {
        let items = viewMode == .month ? store.transactions(in: selectedMonth) : store.transactions
        return Array(items.prefix(4))
    }
}

private enum DashboardViewMode: String, CaseIterable, Identifiable {
    case month = "Month"
    case average = "Average"
    var id: Self { self }
}

private struct ComparisonItem: Identifiable {
    let id = UUID()
    let metric: String
    let type: String
    let amount: Double
}

private struct ActualCard: View {
    let title: String
    let amount: Decimal
    let color: Color
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color).padding(8).background(color.opacity(0.12), in: Circle())
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: currencyCode)).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct CategoryComparisonRow: View {
    let category: TransactionCategory
    let actual: Decimal
    let budget: Decimal

    private var progress: Double {
        guard budget > 0 else { return actual > 0 ? 1 : 0 }
        return min(1, max(0, decimalDouble(actual / budget)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(category.rawValue, systemImage: category.symbol).font(.subheadline.bold())
            HStack {
                Text("Actual: \(actual, format: .currency(code: currencyCode))")
                    .foregroundStyle(.orange)
                Spacer()
                Text("Budget: \(budget, format: .currency(code: currencyCode))")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            ProgressView(value: progress)
                .tint(actual > budget && budget > 0 ? .red : .budgetBuddyBlue)
        }
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            content
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private func decimalDouble(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}

struct NetWorthHistoryView: View {
    @EnvironmentObject private var store: TransactionStore

    var body: some View {
        List {
            Section {
                ForEach(monthlyHistory.reversed()) { snapshot in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snapshot.date, format: .dateTime.month(.wide).year())
                            Text("Cash \(snapshot.cash, format: .currency(code: currencyCode)) · Investments \(snapshot.investments, format: .currency(code: currencyCode))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(snapshot.total, format: .currency(code: currencyCode)).bold()
                    }
                }
            } footer: {
                Text("These values are calculated automatically from your starting balances and transactions. Change the starting balance in Settings if the baseline is wrong.")
            }
        }
        .navigationTitle("Net Worth History")
    }

    private var monthlyHistory: [NetWorthSnapshot] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: store.calculatedNetWorthSnapshots) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        }
        return grouped.compactMap { month, values in
            guard let last = values.max(by: { $0.date < $1.date }) else { return nil }
            return NetWorthSnapshot(date: month, cash: last.cash, investments: last.investments)
        }.sorted { $0.date < $1.date }
    }
}
