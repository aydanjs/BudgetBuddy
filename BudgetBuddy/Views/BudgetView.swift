import SwiftUI

struct BudgetView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var selectedMonth = Date()

    var body: some View {
        List {
            Section {
                DatePicker("Month", selection: $selectedMonth, displayedComponents: [.date])
                    .datePickerStyle(.compact)
                HStack {
                    BudgetTotal(title: "Planned", value: store.totalPlannedSpending, color: .indigo)
                    BudgetTotal(title: "Actual", value: store.actualSpending(in: selectedMonth), color: .orange)
                }
            }

            ForEach([BudgetGroup.needs, .wants, .giving]) { group in
                Section(group.rawValue) {
                    ForEach(categories(in: group)) { category in
                        BudgetCategoryRow(category: category, month: selectedMonth)
                    }
                }
            }

            Section("Savings") {
                LabeledContent("Planned amount") {
                    Text(store.plannedSavings, format: .currency(code: currencyCode))
                        .foregroundStyle(store.plannedSavings >= 0 ? .green : .red).bold()
                }
                Text("Savings is what remains after planned spending and tithing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Monthly Budget")
    }

    private func categories(in group: BudgetGroup) -> [TransactionCategory] {
        TransactionCategory.expenseCategories.filter { $0.group == group }
    }
}

private struct BudgetTotal: View {
    let title: String
    let value: Decimal
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: currencyCode)).font(.headline).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetCategoryRow: View {
    @EnvironmentObject private var store: TransactionStore
    let category: TransactionCategory
    let month: Date

    private var budget: Decimal { store.budget(for: category) }
    private var actual: Decimal { store.actualSpending(for: category, in: month) }
    private var progress: Double {
        guard budget > 0 else { return actual > 0 ? 1 : 0 }
        return min(1, NSDecimalNumber(decimal: actual / budget).doubleValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category.rawValue, systemImage: category.symbol)
                Spacer()
                if category == .tithing {
                    Text(budget, format: .currency(code: currencyCode)).bold()
                } else {
                    TextField("$0", value: Binding(get: { budget }, set: { store.setBudget($0, for: category) }), format: .number)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                }
            }
            ProgressView(value: progress).tint(actual > budget && budget > 0 ? .red : .indigo)
            HStack {
                Text("Spent \(actual, format: .currency(code: currencyCode))")
                Spacer()
                Text(budget > 0 ? "\(max(0, budget - actual), format: .currency(code: currencyCode)) left" : "No budget set")
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4)
    }
}
