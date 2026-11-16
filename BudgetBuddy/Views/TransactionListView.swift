import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool
    @Binding var selectedMonth: Date?
    @State private var selectedCategory: TransactionCategory?

    init(showingAddTransaction: Binding<Bool>, selectedMonth: Binding<Date?> = .constant(nil)) {
        _showingAddTransaction = showingAddTransaction
        _selectedMonth = selectedMonth
    }

    private var filteredTransactions: [Transaction] {
        return store.transactions.filter { transaction in
            let matchesMonth = selectedMonth.map { Calendar.current.isDate(transaction.date, equalTo: $0, toGranularity: .month) } ?? true
            let matchesCategory = selectedCategory.map { !transaction.isIncome && !transaction.isTransfer && transaction.category == $0 } ?? true
            return matchesMonth && matchesCategory
        }
    }

    var body: some View {
        List {
            ForEach(filteredTransactions) { transaction in
                NavigationLink {
                    AddTransactionView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction)
                }
            }
                .onDelete { store.delete(at: $0, from: filteredTransactions) }
        }
        .overlay {
            if store.transactions.isEmpty {
                ContentUnavailableView("No transactions yet", systemImage: "tray", description: Text("Tap + to add your first one."))
            } else if filteredTransactions.isEmpty {
                ContentUnavailableView("No matching transactions", systemImage: "line.3.horizontal.decrease.circle", description: Text("Try a different category."))
            }
        }
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("All Months") { selectedMonth = nil }
                    if selectedMonth != nil {
                        Button("Selected Month: \(selectedMonth!.formatted(.dateTime.month(.wide).year()))") {}
                            .disabled(true)
                        Divider()
                    }
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as TransactionCategory?)
                        ForEach(store.expenseCategories) { category in
                            Label(category.rawValue, systemImage: category.symbol).tag(category as TransactionCategory?)
                        }
                    }
                } label: {
                    Label(filterLabel, systemImage: "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter transactions by category")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddTransaction = true } label: { Image(systemName: "plus") }
            }
        }
    }

    private var filterLabel: String {
        if let selectedCategory { return selectedCategory.rawValue }
        if let selectedMonth { return selectedMonth.formatted(.dateTime.month(.abbreviated)) }
        return "All"
    }
}

struct TransactionRow: View {
    let transaction: Transaction

    private var symbol: String {
        if transaction.isTransfer { return "arrow.left.arrow.right.circle.fill" }
        return transaction.isIncome ? "dollarsign.circle.fill" : transaction.category.symbol
    }

    private var accentColor: Color {
        if transaction.isTransfer { return .secondary }
        return transaction.isIncome ? .budgetBuddyGreen : .budgetBuddyBlue
    }

    private var fallbackTitle: String {
        if transaction.isTransfer { return "Transfer" }
        return transaction.isIncome ? "Income" : transaction.category.rawValue
    }

    private var detailText: String {
        if transaction.isTransfer {
            return "Transfer · Excluded from spending"
        }
        if transaction.isIncome {
            return transaction.date.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(transaction.category.rawValue) · \(transaction.category.group.rawValue)"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(accentColor)
                .frame(width: 36, height: 36)
                .background(accentColor.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.notes.isEmpty ? fallbackTitle : transaction.notes).font(.body.weight(.medium))
                Text(detailText)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(transaction.isTransfer ? Color.secondary : (transaction.isIncome ? Color.budgetBuddyGreen : Color.primary))
        }.padding(.vertical, 6)
    }
}
