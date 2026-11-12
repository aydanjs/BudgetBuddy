import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool

    private var thisMonth: [Transaction] {
        store.transactions.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
    }

    private var income: Decimal {
        thisMonth.filter(\.isIncome).reduce(0) { $0 + $1.amount }
    }

    private var spending: Decimal {
        thisMonth.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Date.now, format: .dateTime.month(.wide).year())
                        .foregroundStyle(.secondary)
                    Text((income - spending), format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                    Text("Remaining balance")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(22)
                .background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 22))
                .foregroundStyle(.white)

                HStack(spacing: 12) {
                    SummaryCard(title: "Income", amount: income, color: .green, symbol: "arrow.down.left")
                    SummaryCard(title: "Spending", amount: spending, color: .orange, symbol: "arrow.up.right")
                }

                HStack {
                    Text("Recent transactions").font(.title3.bold())
                    Spacer()
                    NavigationLink("See all") {
                        TransactionListView(showingAddTransaction: $showingAddTransaction)
                    }
                    .font(.subheadline)
                }

                if store.transactions.isEmpty {
                    ContentUnavailableView("No transactions yet", systemImage: "tray", description: Text("Tap + to add your first one."))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(store.transactions.prefix(4)) { transaction in
                            TransactionRow(transaction: transaction)
                            Divider().padding(.leading, 48)
                        }
                    }
                    .padding(.horizontal)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("BudgetBuddy")
        .toolbar {
            Button { showingAddTransaction = true } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add transaction")
        }
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
                .foregroundStyle(color)
                .padding(8)
                .background(color.opacity(0.12), in: Circle())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}
