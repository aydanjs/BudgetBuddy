import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject private var store: TransactionStore
    @Binding var showingAddTransaction: Bool

    var body: some View {
        List {
            ForEach(store.transactions) { transaction in TransactionRow(transaction: transaction) }
                .onDelete { store.delete(at: $0, from: store.transactions) }
        }
        .overlay { if store.transactions.isEmpty { ContentUnavailableView("No transactions yet", systemImage: "tray", description: Text("Tap + to add your first one.")) } }
        .navigationTitle("Transactions")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingAddTransaction = true } label: { Image(systemName: "plus") } } }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.isIncome ? "dollarsign.circle.fill" : transaction.category.symbol)
                .font(.title2).foregroundStyle(transaction.isIncome ? .green : .indigo).frame(width: 36, height: 36)
                .background((transaction.isIncome ? Color.green : Color.indigo).opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(transaction.notes.isEmpty ? (transaction.isIncome ? "Income" : transaction.category.rawValue) : transaction.notes).font(.body.weight(.medium))
                Text(transaction.isIncome ? transaction.date.formatted(.dateTime.month(.abbreviated).day()) : "\(transaction.category.rawValue) · \(transaction.category.group.rawValue)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(transaction.amount, format: .currency(code: currencyCode)).font(.subheadline.bold()).foregroundStyle(transaction.isIncome ? .green : .primary)
        }.padding(.vertical, 6)
    }
}
