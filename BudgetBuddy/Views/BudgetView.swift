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
                    BudgetTotal(title: "Planned", value: store.totalPlannedSpending, color: .budgetBuddyBlue)
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
                LabeledContent("Available after budget") {
                    Text(store.plannedSavings, format: .currency(code: currencyCode))
                        .foregroundStyle(store.plannedSavings >= 0 ? Color.budgetBuddyGreen : .red).bold()
                }
                LabeledContent("Savings goal") {
                    Text(store.savingsGoal, format: .currency(code: currencyCode)).bold()
                }
                ProgressView(value: savingsProgress)
                    .tint(store.plannedSavings >= store.savingsGoal ? .budgetBuddyGreen : .orange)
                Text("Your savings goal rate is editable in Settings. Available savings is what remains after planned spending and tithing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Monthly Budget")
    }

    private func categories(in group: BudgetGroup) -> [TransactionCategory] {
        TransactionCategory.expenseCategories.filter {
            $0.group == group && !($0 == .rent && store.settings.housingType == .neither)
        }
    }

    private var savingsProgress: Double {
        guard store.savingsGoal > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: store.plannedSavings / store.savingsGoal).doubleValue))
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
    @State private var requestFocus = false

    private var budget: Decimal { store.budget(for: category) }
    private var actual: Decimal { store.actualSpending(for: category, in: month) }
    private var progress: Double {
        guard budget > 0 else { return actual > 0 ? 1 : 0 }
        return min(1, NSDecimalNumber(decimal: actual / budget).doubleValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(category == .rent ? store.housingLabel : category.rawValue, systemImage: category.symbol)
                Spacer()
                if category == .tithing || category == .debtPayment {
                    Text(budget, format: .currency(code: currencyCode)).bold()
                } else {
                    EditableDecimalField(
                        value: Binding(get: { budget }, set: { store.setBudget($0, for: category) }),
                        width: 100,
                        focusRequest: $requestFocus
                    )
                }
            }
            ProgressView(value: progress).tint(actual > budget && budget > 0 ? .red : .budgetBuddyBlue)
            HStack {
                Text("Spent \(actual, format: .currency(code: currencyCode))")
                Spacer()
                Text(budget > 0 ? "\(max(0, budget - actual), format: .currency(code: currencyCode)) left" : "No budget set")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if category != .tithing && category != .debtPayment { requestFocus = true }
        }
    }
}
