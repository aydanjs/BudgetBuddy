import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TransactionStore

    var body: some View {
        Form {
            Section("Income plan") {
                DecimalSetting(title: "Hourly rate", value: binding(\.hourlyRate), prefix: "$", suffix: "/hr")
                DecimalSetting(title: "Hours per month", value: binding(\.scheduledHours))
                PercentageSetting(title: "Estimated tax rate", decimal: binding(\.taxRate))
                LabeledContent("Planned net pay") { Text(store.plannedNetIncome, format: .currency(code: currencyCode)).bold() }
            }

            Section("Household plan") {
                PercentageSetting(title: "Tithing rate", decimal: binding(\.tithingRate))
                DecimalSetting(title: "Starting cash", value: binding(\.startingCash), prefix: "$")
                DatePicker("First budget month", selection: dateBinding, displayedComponents: .date)
            }

            Section {
                Text("All information stays on this phone. Budget settings and transactions are saved automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func binding(_ keyPath: WritableKeyPath<BudgetSettings, Decimal>) -> Binding<Decimal> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.updateSettings { $0[keyPath: keyPath] = max(0, value) } })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { store.settings.firstBudgetMonth }, set: { value in store.updateSettings { $0.firstBudgetMonth = value } })
    }
}

private struct DecimalSetting: View {
    let title: String
    @Binding var value: Decimal
    var prefix = ""
    var suffix = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(prefix).foregroundStyle(.secondary)
            TextField("0", value: $value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 75)
            Text(suffix).foregroundStyle(.secondary)
        }
    }
}

private struct PercentageSetting: View {
    let title: String
    @Binding var decimal: Decimal
    private var percent: Binding<Decimal> {
        Binding(get: { decimal * 100 }, set: { decimal = max(0, $0 / 100) })
    }
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: percent, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 65)
            Text("%").foregroundStyle(.secondary)
        }
    }
}
