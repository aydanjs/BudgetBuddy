import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool

    private let month = Date()
    private var income: Decimal { store.actualIncome(in: month) }
    private var spending: Decimal { store.actualSpending(in: month) }
    private var remaining: Decimal { income - spending }
    private var savingsRate: Decimal { income > 0 ? remaining / income : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(month, format: .dateTime.month(.wide).year())
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                    Text(remaining, format: .currency(code: currencyCode))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Unallocated this month")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(Color.indigo.gradient, in: RoundedRectangle(cornerRadius: 22))
                .foregroundStyle(.white)

                HStack(spacing: 12) {
                    SummaryCard(title: "Pay received", amount: income, color: .green, symbol: "arrow.down.left")
                    SummaryCard(title: "Actual spending", amount: spending, color: .orange, symbol: "arrow.up.right")
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Monthly plan").font(.headline)
                        Spacer()
                        Text(store.plannedNetIncome, format: .currency(code: currencyCode))
                            .font(.subheadline.bold())
                    }
                    MetricLine(label: "Planned spending", value: store.totalPlannedSpending, color: .orange)
                    MetricLine(label: "Left to save", value: store.plannedSavings, color: .green)
                    HStack {
                        Text("Actual savings rate").foregroundStyle(.secondary)
                        Spacer()
                        Text(savingsRate, format: .percent.precision(.fractionLength(0))).bold()
                    }
                }
                .padding()
                .background(.background, in: RoundedRectangle(cornerRadius: 16))

                HStack {
                    Text("Recent transactions").font(.title3.bold())
                    Spacer()
                    NavigationLink("See all") { TransactionListView(showingAddTransaction: $showingAddTransaction) }
                        .font(.subheadline)
                }

                LazyVStack(spacing: 0) {
                    ForEach(store.transactions.prefix(4)) { transaction in
                        TransactionRow(transaction: transaction)
                        if transaction.id != store.transactions.prefix(4).last?.id { Divider().padding(.leading, 48) }
                    }
                }
                .padding(.horizontal)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("BudgetBuddy")
        .toolbar { Button { showingAddTransaction = true } label: { Image(systemName: "plus") } }
    }
}

private struct SummaryCard: View {
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
        .frame(maxWidth: .infinity, alignment: .leading).padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MetricLine: View {
    let label: String
    let value: Decimal
    let color: Color
    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .currency(code: currencyCode)).bold()
        }
    }
}

let currencyCode = Locale.current.currency?.identifier ?? "USD"
