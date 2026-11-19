import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var store: TransactionStore
    @EnvironmentObject private var auth: AuthSessionStore
    @State private var showingResetConfirmation = false
    @State private var showingClearTransactionsConfirmation = false

    var body: some View {
        Form {
            Section("Income plan") {
                Picker("Income type", selection: incomeTypeBinding) {
                    ForEach(IncomeType.selectableCases) { Text($0.displayName).tag($0) }
                }

                switch store.settings.incomeType {
                case .hourly:
                    DecimalSetting(title: "Hourly rate", value: binding(\.hourlyRate), prefix: "$", suffix: "/hr")
                    DecimalSetting(title: "Hours per week", value: binding(\.hoursPerWeek))
                    PercentageSetting(title: "Estimated tax rate", decimal: binding(\.taxRate))
                case .salary:
                    paycheckAmountField
                case .paycheck:
                    paycheckAmountField
                }

                Picker("Paid", selection: payFrequencyBinding) {
                    ForEach(PayFrequency.allCases) { Text($0.rawValue).tag($0) }
                }
                LabeledContent("Estimated monthly take-home") {
                    Text(store.plannedNetIncome, format: .currency(code: currencyCode)).bold()
                }
            }

            Section("Monthly saving & investing") {
                Picker("Cash savings plan", selection: savingsModeBinding) {
                    ForEach(ContributionPlanMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                if store.settings.savingsContributionMode == .percentage {
                    PercentageSetting(title: "Cash savings goal", decimal: binding(\.savingsRate))
                } else if store.settings.savingsContributionMode == .fixedAmount {
                    DecimalSetting(title: "Cash savings goal", value: binding(\.monthlySavingsContribution), prefix: "$")
                }
                LabeledContent("Planned cash savings") {
                    Text(store.plannedSavingsContribution, format: .currency(code: currencyCode)).bold()
                }

                Picker("Investing plan", selection: investmentModeBinding) {
                    Text(ContributionPlanMode.percentage.rawValue).tag(ContributionPlanMode.percentage)
                    Text(ContributionPlanMode.fixedAmount.rawValue).tag(ContributionPlanMode.fixedAmount)
                }
                if store.settings.investmentContributionMode == .percentage {
                    PercentageSetting(title: "Investing goal", decimal: binding(\.investmentRate))
                } else {
                    DecimalSetting(title: "Investing goal", value: binding(\.monthlyInvestmentContribution), prefix: "$")
                }
                LabeledContent("Planned investing") {
                    Text(store.plannedInvestmentContribution, format: .currency(code: currencyCode)).bold()
                }
                Text("Percentage goals scale with expected income. ‘What is left’ calculates cash savings after planned expenses and investing.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Housing") {
                Picker("Housing", selection: housingTypeBinding) {
                    ForEach(HousingType.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if store.settings.housingType == .rent {
                    DecimalSetting(title: "Monthly rent", value: housingPaymentBinding, prefix: "$")
                } else if store.settings.housingType == .mortgage {
                    DecimalSetting(title: "Monthly mortgage payment", value: housingPaymentBinding, prefix: "$")
                    DecimalSetting(title: "Remaining mortgage balance", value: binding(\.mortgageBalance), prefix: "$")
                    PercentageSetting(title: "Mortgage interest rate", decimal: binding(\.mortgageInterestRate))
                    DecimalSetting(title: "Years remaining", value: binding(\.mortgageYearsRemaining))
                    Text("The payment is used in your monthly budget. Balance, rate, and years remaining help explain and plan the payoff.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No rent or mortgage payment will be included in your monthly plan.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if store.settings.housingType != .neither {
                    Picker("Payment due day", selection: housingDueDayBinding) {
                        ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
                    }
                    Text("Your weekly plan shows this as a scheduled bill in the week it is due, not as flexible spending money.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Household plan") {
                Toggle("Include tithing", isOn: tithingEnabledBinding)
                if store.settings.tithingEnabled {
                    LabeledContent("Tithing rate", value: "10% of monthly income")
                    Text("Tithing builds from income recorded during each month. It becomes an expense only when you mark it paid in Budget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DecimalSetting(title: "Starting cash and savings", value: startingCashBinding, prefix: "$")
                DecimalSetting(title: "Starting investments", value: startingInvestmentBinding, prefix: "$")
                DatePicker("First budget month", selection: dateBinding, displayedComponents: .date)
                Text("These are your setup baselines. Turtle Budgeting keeps them and adds income, subtracts expenses, and updates the same balances everywhere in the app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Categories") {
                NavigationLink {
                    CategoryManagerView()
                } label: {
                    Label("Manage budget categories", systemImage: "square.grid.2x2.fill")
                }
                Text("Add your own categories, edit them later, or hide included categories you do not use. Past transactions keep their original labels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Guidance") {
                NavigationLink {
                    EmergencyFundView()
                } label: {
                    Label("Emergency fund", systemImage: "cross.case.fill")
                }
                NavigationLink {
                    BudgetAdviceView()
                } label: {
                    Label("Budgeting advice & help", systemImage: "questionmark.bubble.fill")
                }
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
                    ConnectedAccountsView()
                } label: {
                    Label("Connected accounts", systemImage: "building.columns.fill")
                }
                Text("Connect, sync, reconnect, or safely remove bank connections through Plaid.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Privacy & data") {
                NavigationLink {
                    PrivacyDataView()
                } label: {
                    Label("How your data is handled", systemImage: "hand.raised.fill")
                }
            }

            Section("Account") {
                if !auth.displayName.isEmpty {
                    LabeledContent("Signed in as", value: auth.displayName)
                }
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                Text("Signing out does not erase budget data stored on this iPhone.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Reset") {
                Button(role: .destructive) {
                    showingClearTransactionsConfirmation = true
                } label: {
                    Label("Clear All Transactions", systemImage: "trash")
                }
                Text("Removes transactions saved on this iPhone but keeps your budget plan, net-worth history, Apple login, and connected banks.")
                    .font(.caption).foregroundStyle(.secondary)

                Button(role: .destructive) {
                    showingResetConfirmation = true
                } label: {
                    Label("Start Over With Guided Setup", systemImage: "arrow.counterclockwise")
                }
                Text("Clears local budget data, then takes you back through the guided setup. Your Apple login and connected banks stay in place.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .alert("Start over with guided setup?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Start Over", role: .destructive) {
                store.resetLocalData()
                auth.restartOnboarding()
            }
        } message: {
            Text("This cannot be undone. Your local numbers and transactions will return to zero, then Turtle Budgeting will guide you through setup again. Your Apple login and bank connection will stay in place.")
        }
        .alert("Clear all transactions?", isPresented: $showingClearTransactionsConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear Transactions", role: .destructive) {
                store.clearAllTransactions()
            }
        } message: {
            Text("This removes every transaction saved on this iPhone. Your budget plan, net-worth history, Apple login, and connected banks will stay in place. You can sync your bank again later to review and import transactions.")
        }
    }

    private func binding(_ keyPath: WritableKeyPath<BudgetSettings, Decimal>) -> Binding<Decimal> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.updateSettings { $0[keyPath: keyPath] = max(0, value) } })
    }

    private var dateBinding: Binding<Date> {
        Binding(get: { store.settings.firstBudgetMonth }, set: { value in store.updateSettings { $0.firstBudgetMonth = value } })
    }

    private var incomeTypeBinding: Binding<IncomeType> {
        Binding(get: { store.settings.incomeType }, set: { value in store.updateSettings { $0.incomeType = value } })
    }

    private var payFrequencyBinding: Binding<PayFrequency> {
        Binding(get: { store.settings.payFrequency }, set: { value in store.updateSettings { $0.payFrequency = value } })
    }

    private var savingsModeBinding: Binding<ContributionPlanMode> {
        Binding(get: { store.settings.savingsContributionMode }, set: { value in
            store.updateSettings { $0.savingsContributionMode = value }
        })
    }

    private var investmentModeBinding: Binding<ContributionPlanMode> {
        Binding(get: { store.settings.investmentContributionMode }, set: { value in
            store.updateSettings { $0.investmentContributionMode = value }
        })
    }

    private var housingTypeBinding: Binding<HousingType> {
        Binding(get: { store.settings.housingType }, set: { value in store.updateSettings { $0.housingType = value } })
    }

    private var tithingEnabledBinding: Binding<Bool> {
        Binding(get: { store.settings.tithingEnabled }, set: { isEnabled in
            store.updateSettings {
                $0.tithingEnabled = isEnabled
                $0.tithingRate = 0.10
            }
        })
    }

    private var housingPaymentBinding: Binding<Decimal> {
        Binding(get: { store.settings.categoryBudgets[TransactionCategory.rent.rawValue] ?? 0 },
                set: { store.setBudget($0, for: .rent) })
    }

    private var housingDueDayBinding: Binding<Int> {
        Binding(get: { store.settings.housingDueDay }, set: { value in
            store.updateSettings { $0.housingDueDay = value }
        })
    }

    private var startingCashBinding: Binding<Decimal> {
        Binding(get: {
            store.settings.lastLinkedCashBalance ?? store.settings.startingCash
        }, set: { value in
            store.updateSettings {
                $0.currentSavings = max(0, value)
                $0.startingCash = max(0, value)
                $0.balanceAnchorDate = Calendar.current.startOfDay(for: Date())
                $0.lastLinkedCashBalance = nil
            }
        })
    }

    private var startingInvestmentBinding: Binding<Decimal> {
        Binding(get: { store.currentInvestmentBalance }, set: { value in
            store.updateSettings {
                $0.startingInvestmentBalance = max(0, value)
                $0.investmentBalance = max(0, value)
                $0.lastLinkedInvestmentBalance = nil
            }
        })
    }

    @ViewBuilder
    private var paycheckAmountField: some View {
        DecimalSetting(title: "Take-home pay per paycheck", value: binding(\.takeHomePaycheck), prefix: "$")
        Text("Enter the usual amount that reaches your bank account after taxes and deductions.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct BudgetAdviceView: View {
    private let supportEmail = "turtlebudgeting@gmail.com"

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("A steady starting order", systemImage: "tortoise.fill")
                        .font(.title3.bold())
                        .foregroundStyle(Color.budgetBuddyGreen)
                    Text("Cover essentials, build an emergency fund, then assign money to other goals and long-term investments.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Simple habits") {
                AdviceRow(symbol: "calendar", title: "Check in weekly", detail: "Small weekly adjustments are easier than fixing an entire month at once.")
                AdviceRow(symbol: "cross.case", title: "Protect the basics", detail: "Work toward 3 months first, then consider 6 or 12 months of essential expenses.")
                AdviceRow(symbol: "arrow.triangle.2.circlepath", title: "Update when life changes", detail: "Pay, housing, and priorities change. Your budget should change with them.")
                AdviceRow(symbol: "chart.line.uptrend.xyaxis", title: "Treat forecasts as estimates", detail: "Investment returns and future costs are never guaranteed.")
            }

            Section("One possible starting framework") {
                AdviceRow(symbol: "house.fill", title: "50% for needs", detail: "Housing, groceries, transportation, insurance, minimum debt payments, and other essentials.")
                AdviceRow(symbol: "sparkles", title: "25% for wants", detail: "Flexible spending that makes life enjoyable but can be adjusted when needed.")
                AdviceRow(symbol: "leaf.fill", title: "25% for your future", detail: "Emergency savings, other goals, and—if it fits your situation—a small long-term investing percentage.")
                Text("50/25/25 is only a planning example, not a rule. Housing costs, income, debt, family needs, and life stage can make a different split more realistic. Starting smaller and increasing gradually still counts as progress.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Have a question?") {
                Text("Send us a message and we will do our best to reply within a few days.")
                Link(destination: URL(string: "mailto:\(supportEmail)?subject=Turtle%20Budgeting%20Question")!) {
                    Label(supportEmail, systemImage: "envelope.fill")
                }
            }

            Section {
                Text("Turtle Budgeting provides general educational information, not individualized financial, investment, tax, or legal advice. Investing involves risk, including possible loss of principal. Consider your circumstances and, when appropriate, a qualified professional before making financial decisions.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Advice & Help")
    }
}

private struct AdviceRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.budgetBuddyBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CategoryManagerView: View {
    @EnvironmentObject private var store: TransactionStore
    @State private var showingAddCategory = false

    var body: some View {
        List {
            Section {
                if store.settings.customCategories.isEmpty {
                    Text("Add categories such as Pets, Subscriptions, Utilities, or Travel.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.settings.customCategories) { category in
                        NavigationLink {
                            CustomCategoryEditor(category: category)
                        } label: {
                            Label(category.name, systemImage: category.symbol)
                        }
                    }
                    .onDelete { offsets in
                        let categories = offsets.map { store.settings.customCategories[$0] }
                        categories.forEach(store.deleteCustomCategory)
                    }
                }
            } header: {
                Text("Your categories")
            } footer: {
                Text("Deleting a custom category removes it from budgets and new transaction choices. It does not change older transactions.")
            }

            Section {
                ForEach(store.manageableBuiltInCategories) { category in
                    Toggle(isOn: Binding(
                        get: { store.expenseCategories.contains(category) },
                        set: { store.setBuiltInCategory(category, isVisible: $0) }
                    )) {
                        Label(category.rawValue, systemImage: category.symbol)
                    }
                }
            } header: {
                Text("Included categories")
            } footer: {
                Text("Turn off categories you do not use. You can turn them back on whenever you want.")
            }
        }
        .navigationTitle("Budget Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAddCategory = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add category")
            }
        }
        .sheet(isPresented: $showingAddCategory) {
            NavigationStack { CustomCategoryEditor() }
        }
    }
}

private struct CustomCategoryEditor: View {
    @EnvironmentObject private var store: TransactionStore
    @Environment(\.dismiss) private var dismiss
    private let existingCategory: CustomBudgetCategory?
    @State private var name: String
    @State private var group: BudgetGroup
    @State private var symbol: String
    @State private var showsDuplicateNameMessage = false

    private let symbols = ["tag.fill", "star.fill", "cart.fill", "bolt.fill", "heart.fill", "airplane", "gamecontroller.fill", "pawprint.fill", "tv.fill", "figure.run", "wrench.and.screwdriver.fill", "ellipsis.circle.fill"]
    private let groups: [BudgetGroup] = [.needs, .wants, .giving]

    init(category: CustomBudgetCategory? = nil) {
        existingCategory = category
        _name = State(initialValue: category?.name ?? "")
        _group = State(initialValue: category?.group ?? .needs)
        _symbol = State(initialValue: category?.symbol ?? "tag.fill")
    }

    var body: some View {
        Form {
            Section("Category") {
                TextField("Name", text: $name)
                Picker("Budget group", selection: $group) {
                    ForEach(groups) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Icon") {
                Picker("Icon", selection: $symbol) {
                    ForEach(symbols, id: \.self) { symbol in
                        Label(symbolName(for: symbol), systemImage: symbol).tag(symbol)
                    }
                }
            }
            if showsDuplicateNameMessage {
                Text("Choose a different category name. Names must be unique.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .navigationTitle(existingCategory == nil ? "New Category" : "Edit Category")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }
    }

    private func save() {
        let didSave: Bool
        if let existingCategory {
            didSave = store.updateCustomCategory(existingCategory, name: name, group: group, symbol: symbol)
        } else {
            didSave = store.addCustomCategory(name: name, group: group, symbol: symbol)
        }
        if didSave { dismiss() } else { showsDuplicateNameMessage = true }
    }

    private func symbolName(for symbol: String) -> String {
        switch symbol {
        case "tag.fill": "Tag"
        case "star.fill": "Star"
        case "cart.fill": "Cart"
        case "bolt.fill": "Utilities"
        case "heart.fill": "Heart"
        case "airplane": "Travel"
        case "gamecontroller.fill": "Games"
        case "pawprint.fill": "Pets"
        case "tv.fill": "Subscriptions"
        case "figure.run": "Fitness"
        case "wrench.and.screwdriver.fill": "Home"
        default: "Other"
        }
    }
}

private struct PrivacyDataView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @State private var showingOnlineDeletionConfirmation = false

    var body: some View {
        List {
            Section("Stored on this iPhone") {
                Label("Transactions and categories", systemImage: "list.bullet.rectangle")
                Label("Budgets and forecast assumptions", systemImage: "chart.bar.fill")
                Label("Debt and net-worth history", systemImage: "chart.line.uptrend.xyaxis")
            }
            Section("Your privacy") {
                Text("Budget and forecast data remains in the app's private storage. If you enable bank sync, Turtle Budgeting’s secure server stores your account connection and imported transaction data so Plaid updates can be delivered.")
                Text("Turtle Budgeting never receives your bank username or password. You can disconnect a bank or delete your online account and bank-sync data from the app.")
                Link("Read the Privacy Notice", destination: URL(string: "https://github.com/aydanjs/BudgetBuddy/blob/main/PRIVACY_POLICY.md")!)
                Link("Contact Turtle Budgeting Privacy", destination: URL(string: "mailto:turtlebudgeting@gmail.com")!)
            }
            Section("Online bank-sync data") {
                Text("Deleting your online account removes your server-side Turtle Budgeting account, connected Plaid banks, encrypted connection tokens, recorded consent, and imported bank transactions. Your local budget on this iPhone stays here unless you use Start Over separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showingOnlineDeletionConfirmation = true
                } label: {
                    Label("Delete Online Account & Bank Data", systemImage: "trash.fill")
                }
                .disabled(auth.serverSessionToken == nil || auth.isDeletingOnlineAccount)
                if auth.isDeletingOnlineAccount {
                    ProgressView("Deleting online account…")
                }
                if let message = auth.serverAuthenticationMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            Section("Forecast disclaimer") {
                Text("Savings and investment projections are estimates for planning. Investment returns are not guaranteed, and Turtle Budgeting does not provide financial advice.")
            }
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete online account and bank data?", isPresented: $showingOnlineDeletionConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Online Account", role: .destructive) {
                Task { _ = await auth.deleteOnlineAccount() }
            }
        } message: {
            Text("This permanently removes your online Turtle Budgeting account, connected banks, server-side imported transactions, encrypted connection tokens, and recorded consent. It does not remove local budget data on this iPhone.")
        }
    }
}

private struct DecimalSetting: View {
    let title: String
    @Binding var value: Decimal
    var prefix = ""
    var suffix = ""
    @State private var requestFocus = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(prefix).foregroundStyle(.secondary)
            EditableDecimalField(value: $value, width: 90, focusRequest: $requestFocus)
            Text(suffix).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { requestFocus = true }
    }
}

private struct PercentageSetting: View {
    let title: String
    @Binding var decimal: Decimal
    private var percent: Binding<Decimal> {
        Binding(get: { decimal * 100 }, set: { decimal = max(0, $0 / 100) })
    }
    @State private var requestFocus = false
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            EditableDecimalField(value: percent, width: 75, focusRequest: $requestFocus)
            Text("%").foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture { requestFocus = true }
    }
}

struct EditableDecimalField: View {
    @Binding var value: Decimal
    let width: CGFloat
    private var focusRequest: Binding<Bool>?
    @State private var text: String
    @State private var isFocused = false

    init(value: Binding<Decimal>, width: CGFloat, focusRequest: Binding<Bool>? = nil) {
        _value = value
        self.width = width
        self.focusRequest = focusRequest
        _text = State(initialValue: Self.displayText(for: value.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 4) {
            RightAlignedDecimalTextInput(text: $text, isFirstResponder: $isFocused)

            if isFocused {
                Button {
                    isFocused = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.budgetBuddyBlue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Finish editing")
            }
        }
            .frame(width: width)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(Color.budgetBuddyBlue.opacity(isFocused ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: text) { _, newValue in
                if let parsed = Self.parse(newValue) { value = max(0, parsed) }
            }
            .onChange(of: isFocused) { _, focused in
                if focused {
                    // Show zero as a placeholder while editing so the first digit
                    // replaces it instead of becoming 60, 70, and so on.
                    if value == 0 { text = "" }
                } else {
                    focusRequest?.wrappedValue = false
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
            .onChange(of: focusRequest?.wrappedValue) { _, requested in
                if requested == true { isFocused = true }
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

/// UIKit gives us reliable cursor control that SwiftUI's TextField does not expose.
/// Every numeric field begins editing at the far-right end of its current value.
struct RightAlignedDecimalTextInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var placeholder = "0"

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.placeholder = placeholder
        field.font = font
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }

        if isFirstResponder, !field.isFirstResponder {
            DispatchQueue.main.async {
                field.becomeFirstResponder()
                context.coordinator.moveCursorToEnd(in: field)
            }
        } else if !isFirstResponder, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RightAlignedDecimalTextInput

        init(parent: RightAlignedDecimalTextInput) {
            self.parent = parent
        }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.isFirstResponder = true
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field else { return }
                self.moveCursorToEnd(in: field)
            }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.isFirstResponder = false
        }

        func moveCursorToEnd(in field: UITextField) {
            field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        }
    }
}
