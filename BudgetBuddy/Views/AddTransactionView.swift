import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var category: TransactionCategory = .groceries
    @State private var date = Date()
    @State private var notes = ""
    @State private var isIncome = false

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
                        ForEach(TransactionCategory.expenseCategories) { item in
                            Label(item.rawValue, systemImage: item.symbol).tag(item)
                        }
                    }
                    LabeledContent("Group", value: category.group.rawValue).foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
            }
        }
        .navigationTitle("Add Transaction").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(parsedAmount == nil || parsedAmount ?? 0 <= 0) }
        }
    }

    private func save() {
        guard let parsedAmount, parsedAmount > 0 else { return }
        store.add(Transaction(amount: parsedAmount, category: category, date: date, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), isIncome: isIncome))
        dismiss()
    }
}
