import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    private let transaction: Transaction?
    @State private var amount: String
    @State private var category: TransactionCategory
    @State private var date: Date
    @State private var notes: String
    @State private var isIncome: Bool

    init(transaction: Transaction? = nil) {
        self.transaction = transaction
        _amount = State(initialValue: transaction.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _category = State(initialValue: transaction?.category ?? .groceries)
        _date = State(initialValue: transaction?.date ?? Date())
        _notes = State(initialValue: transaction?.notes ?? "")
        _isIncome = State(initialValue: transaction?.isIncome ?? false)
    }

    private var parsedAmount: Decimal? { Decimal(string: amount.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) }

    var body: some View {
        Form {
            Section("Amount") {
                Picker("Type", selection: $isIncome) { Text("Expense").tag(false); Text("Income").tag(true) }.pickerStyle(.segmented)
                HStack {
                    Text(Locale.current.currencySymbol ?? "$").font(.title2).foregroundStyle(.secondary)
                    TextField("0.00", text: $amount).font(.title2.bold()).keyboardType(.decimalPad)
                }
            }
            Section("Details") {
                if !isIncome {
                    Picker("Category", selection: $category) {
                        ForEach(store.expenseCategories) { item in
                            Label(item.rawValue, systemImage: item.symbol).tag(item)
                        }
                    }
                    LabeledContent("Group", value: category.group.rawValue).foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
            }

            if let transaction {
                Section {
                    Button("Delete Transaction", role: .destructive) {
                        store.delete(transaction)
                        dismiss()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .navigationTitle(transaction == nil ? "Add Transaction" : "Edit Transaction").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if transaction == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(parsedAmount == nil || parsedAmount ?? 0 <= 0) }
        }
    }

    private func save() {
        guard let parsedAmount, parsedAmount > 0 else { return }
        let updated = Transaction(
            id: transaction?.id ?? UUID(),
            amount: parsedAmount,
            category: category,
            date: date,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isIncome: isIncome
        )
        if transaction == nil {
            store.add(updated)
        } else {
            store.update(updated)
        }
        dismiss()
    }
}
