import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TransactionStore

    var body: some View {
        Form {
            Section("Income plan") {
                DecimalSetting(title: "Hourly rate", value: binding(\.hourlyRate), prefix: "$", suffix: "/hr")
                DecimalSetting(title: "Hours per month", value: binding(\.scheduledHours))
                PercentageSetting(title: "Estimated tax rate", decimal: binding(\.taxRate))
                PercentageSetting(title: "Savings goal rate", decimal: binding(\.savingsRate))
                LabeledContent("Planned net pay") { Text(store.plannedNetIncome, format: .currency(code: currencyCode)).bold() }
            }

            Section("Household plan") {
                PercentageSetting(title: "Tithing rate", decimal: binding(\.tithingRate))
                DecimalSetting(title: "Starting cash", value: binding(\.startingCash), prefix: "$")
                DatePicker("First budget month", selection: dateBinding, displayedComponents: .date)
            }

            Section("Forecast assumptions") {
                PercentageSetting(title: "Savings APY", decimal: binding(\.savingsAPY))
                PercentageSetting(title: "Low stock return", decimal: binding(\.lowInvestmentReturn))
                PercentageSetting(title: "Base stock return", decimal: binding(\.baseInvestmentReturn))
                PercentageSetting(title: "High stock return", decimal: binding(\.highInvestmentReturn))
                Text("These stock returns are planning assumptions, not guarantees. Savings APY remains the same in every scenario.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Bank sync") {
                NavigationLink {
                    PlaidConnectionView()
                } label: {
                    Label("Connect bank accounts", systemImage: "building.columns.fill")
                }
                Text("Securely connect accounts through Plaid and choose which transactions to import.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacy & data") {
                NavigationLink {
                    PrivacyDataView()
                } label: {
                    Label("How your data is handled", systemImage: "hand.raised.fill")
                }
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

private struct PrivacyDataView: View {
    var body: some View {
        List {
            Section("Stored on this iPhone") {
                Label("Transactions and categories", systemImage: "list.bullet.rectangle")
                Label("Budgets and forecast assumptions", systemImage: "chart.bar.fill")
                Label("Debt and net-worth history", systemImage: "chart.line.uptrend.xyaxis")
            }
            Section("Your privacy") {
                Text("Budget and forecast data remains in the app's private storage. If you enable bank sync, BudgetBuddy's secure server stores your account connection and imported transaction data so Plaid updates can be delivered.")
                Text("BudgetBuddy never receives your bank username or password. You can disconnect a bank or delete your online account and bank-sync data from the app.")
            }
            Section("Forecast disclaimer") {
                Text("Savings and investment projections are estimates for planning. Investment returns are not guaranteed, and BudgetBuddy does not provide financial advice.")
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
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
            EditableDecimalField(value: $value, width: 75)
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
            EditableDecimalField(value: percent, width: 65)
            Text("%").foregroundStyle(.secondary)
        }
    }
}

struct EditableDecimalField: View {
    @Binding var value: Decimal
    let width: CGFloat
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(value: Binding<Decimal>, width: CGFloat) {
        _value = value
        self.width = width
        _text = State(initialValue: Self.displayText(for: value.wrappedValue))
    }

    var body: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .focused($isFocused)
            .onChange(of: text) { _, newValue in
                if let parsed = Self.parse(newValue) { value = max(0, parsed) }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    if let parsed = Self.parse(text) {
                        value = max(0, parsed)
                    } else {
                        value = 0
                    }
                    text = Self.displayText(for: value)
                }
            }
            .onChange(of: value) { _, newValue in
                if !isFocused { text = Self.displayText(for: newValue) }
            }
    }

    private static func parse(_ text: String) -> Decimal? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func displayText(for value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
