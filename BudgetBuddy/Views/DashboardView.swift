import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool
    @Binding var selectedTab: AppTab
    @Binding var transactionMonth: Date?

    private var income: Decimal { store.actualIncome(in: Date()) }
    private var spending: Decimal { store.actualSpending(in: Date()) }
    private var remaining: Decimal { income - spending }
    private var budgetProgress: Double {
        guard store.totalPlannedSpending > 0 else { return 0 }
        return min(1, max(0, decimalDouble(spending / store.totalPlannedSpending)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                welcomeHeader
                totalMoneyCard
                monthSummary
                budgetProgressCard
                recentTransactions
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    InsightsView(
                        showingAddTransaction: $showingAddTransaction,
                        selectedTab: $selectedTab,
                        transactionMonth: $transactionMonth
                    )
                } label: {
                    Label("Insights", systemImage: "chart.xyaxis.line")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddTransaction = true } label: { Image(systemName: "plus") }
            }
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
                    BalanceDetail(title: "Cash", amount: store.settings.currentSavings, symbol: "building.columns.fill")
                    BalanceDetail(title: "Investments", amount: store.settings.investmentBalance, symbol: "chart.line.uptrend.xyaxis")
                }
                Text("Recorded balances only · forecast returns are not included")
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
            Text("Year to date · BudgetBuddy records balance changes, and you can add earlier balances in History.")
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
                        budget: store.budget(for: category)
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
                store.budget(for: category) > 0 || average(of: { store.actualSpending(for: category, in: $0) }) > 0
            )
        }
    }

    private var yearToDateSnapshots: [NetWorthSnapshot] {
        let year = Calendar.current.component(.year, from: Date())
        return store.netWorthSnapshots.filter { Calendar.current.component(.year, from: $0.date) == year }
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
    @State private var editingSnapshot: NetWorthSnapshot?

    var body: some View {
        List {
            Section {
                ForEach(store.netWorthSnapshots.reversed()) { snapshot in
                    Button {
                        editingSnapshot = snapshot
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(snapshot.date, format: .dateTime.month(.abbreviated).day().year())
                                Text("Cash \(snapshot.cash, format: .currency(code: currencyCode)) · Stocks \(snapshot.investments, format: .currency(code: currencyCode))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(snapshot.total, format: .currency(code: currencyCode)).bold()
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    store.deleteNetWorthSnapshot(at: offsets, from: Array(store.netWorthSnapshots.reversed()))
                }
            } footer: {
                Text("Add earlier balances to build your year-to-date line. Future balance changes are recorded automatically.")
            }
        }
        .navigationTitle("Net Worth History")
        .toolbar {
            Button { editingSnapshot = NetWorthSnapshot(date: Date(), cash: 0, investments: 0) } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(item: $editingSnapshot) { snapshot in
            NetWorthEntryView(snapshot: snapshot)
        }
    }
}

private struct NetWorthEntryView: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    @State var snapshot: NetWorthSnapshot

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $snapshot.date, in: ...Date(), displayedComponents: .date)
                LabeledContent("Cash / savings") {
                    HStack { Text("$"); EditableDecimalField(value: $snapshot.cash, width: 100) }
                }
                LabeledContent("Stock investments") {
                    HStack { Text("$"); EditableDecimalField(value: $snapshot.investments, width: 100) }
                }
                LabeledContent("Net worth") {
                    Text(snapshot.total, format: .currency(code: currencyCode)).bold()
                }
            }
            .navigationTitle("Balance Point")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { store.saveNetWorthSnapshot(snapshot); dismiss() }
                }
            }
        }
    }
}
