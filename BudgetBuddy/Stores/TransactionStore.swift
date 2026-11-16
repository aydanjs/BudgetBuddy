import Foundation

@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var settings = BudgetSettings()
    @Published private(set) var netWorthSnapshots: [NetWorthSnapshot] = []

    private let transactionsURL: URL
    private let settingsURL: URL
    private let netWorthURL: URL

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        transactionsURL = documents.appendingPathComponent("transactions.json")
        settingsURL = documents.appendingPathComponent("budget-settings.json")
        netWorthURL = documents.appendingPathComponent("net-worth-history.json")
        load()
    }

    var plannedNetIncome: Decimal {
        switch settings.incomeType {
        case .hourly:
            settings.hourlyRate * settings.hoursPerWeek * (52 / 12) * (1 - settings.taxRate)
        case .salary:
            settings.takeHomePaycheck * settings.payFrequency.paymentsPerMonth
        case .paycheck:
            settings.takeHomePaycheck * settings.payFrequency.paymentsPerMonth
        }
    }
    var plannedTithing: Decimal { plannedNetIncome * settings.tithingRate }
    var savingsGoal: Decimal { plannedNetIncome * settings.savingsRate }
    var monthlyDebtPayments: Decimal { settings.debts.reduce(0) { $0 + $1.monthlyPayment } }
    var totalPlannedSpending: Decimal {
        let nonHousing = settings.categoryBudgets
            .filter { $0.key != TransactionCategory.rent.rawValue }
            .values.reduce(0, +)
        return nonHousing + budget(for: .rent) + plannedTithing + monthlyDebtPayments
    }
    var plannedSavings: Decimal { plannedNetIncome - totalPlannedSpending }
    var currentNetWorth: Decimal { settings.currentSavings + settings.investmentBalance }
    var housingLabel: String { settings.housingType == .mortgage ? "Mortgage" : "Rent" }
    var expenseCategories: [TransactionCategory] {
        TransactionCategory.expenseCategories.filter { !settings.hiddenBuiltInCategoryIDs.contains($0.id) }
            + settings.customCategories.map(\.transactionCategory)
    }
    var manageableBuiltInCategories: [TransactionCategory] {
        TransactionCategory.expenseCategories.filter { $0 != .tithing && $0 != .debtPayment }
    }

    func transactions(in month: Date) -> [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func actualIncome(in month: Date) -> Decimal {
        transactions(in: month).filter { $0.isIncome && !$0.isTransfer }.reduce(0) { $0 + $1.amount }
    }

    func actualSpending(in month: Date) -> Decimal {
        transactions(in: month).filter { !$0.isIncome && !$0.isTransfer && $0.category != .savings }.reduce(0) { $0 + $1.amount }
    }

    func actualSpending(for category: TransactionCategory, in month: Date) -> Decimal {
        transactions(in: month).filter { !$0.isIncome && !$0.isTransfer && $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    func budget(for category: TransactionCategory) -> Decimal {
        if category == .tithing { return plannedTithing }
        if category == .savings { return plannedSavings }
        if category == .debtPayment { return monthlyDebtPayments }
        if category == .rent && settings.housingType == .neither { return 0 }
        return settings.categoryBudgets[category.rawValue] ?? 0
    }

    func setBudget(_ amount: Decimal, for category: TransactionCategory) {
        settings.categoryBudgets[category.rawValue] = max(0, amount)
        saveSettings()
        objectWillChange.send()
    }

    @discardableResult
    func addCustomCategory(name: String, group: BudgetGroup, symbol: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !expenseCategories.contains(where: { $0.rawValue.caseInsensitiveCompare(trimmedName) == .orderedSame })
        else { return false }
        settings.customCategories.append(CustomBudgetCategory(name: trimmedName, group: group, symbol: symbol))
        saveSettings()
        objectWillChange.send()
        return true
    }

    @discardableResult
    func updateCustomCategory(_ category: CustomBudgetCategory, name: String, group: BudgetGroup, symbol: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              !expenseCategories.contains(where: {
                  $0.id != category.transactionCategory.id &&
                  $0.rawValue.caseInsensitiveCompare(trimmedName) == .orderedSame
              }),
              let index = settings.customCategories.firstIndex(where: { $0.id == category.id })
        else { return false }

        let previous = settings.customCategories[index]
        let updated = CustomBudgetCategory(id: previous.id, name: trimmedName, group: group, symbol: symbol)
        settings.customCategories[index] = updated
        if previous.name != updated.name, let budget = settings.categoryBudgets.removeValue(forKey: previous.name) {
            settings.categoryBudgets[updated.name] = budget
        }
        let previousCategory = previous.transactionCategory
        let updatedCategory = updated.transactionCategory
        transactions = transactions.map { transaction in
            var transaction = transaction
            if transaction.category.id == previousCategory.id { transaction.category = updatedCategory }
            return transaction
        }
        saveTransactions()
        saveSettings()
        objectWillChange.send()
        return true
    }

    func deleteCustomCategory(_ category: CustomBudgetCategory) {
        settings.customCategories.removeAll { $0.id == category.id }
        settings.categoryBudgets.removeValue(forKey: category.name)
        saveSettings()
        objectWillChange.send()
    }

    func setBuiltInCategory(_ category: TransactionCategory, isVisible: Bool) {
        guard !category.id.hasPrefix("custom-") else { return }
        if isVisible {
            settings.hiddenBuiltInCategoryIDs.remove(category.id)
        } else {
            settings.hiddenBuiltInCategoryIDs.insert(category.id)
        }
        saveSettings()
        objectWillChange.send()
    }

    func updateSettings(_ update: (inout BudgetSettings) -> Void) {
        update(&settings)
        saveSettings()
        recordCurrentNetWorth()
        objectWillChange.send()
    }

    func applyLinkedAccountBalances(cash: Decimal?, investments: Decimal?) {
        guard cash != nil || investments != nil else { return }

        updateSettings { settings in
            if let cash {
                settings.currentSavings = max(0, cash)
            }
            if let investments {
                settings.investmentBalance = max(0, investments)
            }
        }
    }

    func saveDebt(_ debt: Debt) {
        updateSettings { settings in
            if let index = settings.debts.firstIndex(where: { $0.id == debt.id }) {
                settings.debts[index] = debt
            } else {
                settings.debts.append(debt)
            }
        }
    }

    func deleteDebt(at offsets: IndexSet) {
        let ids = offsets.map { settings.debts[$0].id }
        updateSettings { $0.debts.removeAll { ids.contains($0.id) } }
    }

    func saveNetWorthSnapshot(_ snapshot: NetWorthSnapshot) {
        if let index = netWorthSnapshots.firstIndex(where: { $0.id == snapshot.id }) {
            netWorthSnapshots[index] = snapshot
        } else {
            netWorthSnapshots.append(snapshot)
        }
        netWorthSnapshots.sort { $0.date < $1.date }
        saveNetWorthSnapshots()

        // A snapshot for today is also the person's current balance. Keep the
        // dashboard card in sync while allowing older snapshots to remain
        // historical graph entries only.
        if Calendar.current.isDate(snapshot.date, inSameDayAs: Date()) {
            var updatedSettings = settings
            updatedSettings.currentSavings = max(0, snapshot.cash)
            updatedSettings.investmentBalance = max(0, snapshot.investments)
            settings = updatedSettings
            saveSettings()
        }
    }

    func deleteNetWorthSnapshot(at offsets: IndexSet, from snapshots: [NetWorthSnapshot]) {
        let ids = offsets.map { snapshots[$0].id }
        netWorthSnapshots.removeAll { ids.contains($0.id) }
        saveNetWorthSnapshots()
    }

    func add(_ transaction: Transaction) {
        if let externalID = transaction.externalID, transactions.contains(where: { $0.externalID == externalID }) { return }
        transactions.append(transaction)
        transactions.sort { $0.date > $1.date }
        saveTransactions()
    }

    func importTransactions(_ imported: [Transaction]) -> Int {
        let existingIDs = Set(transactions.compactMap(\.externalID))
        let newTransactions = imported.filter { item in
            guard let externalID = item.externalID else { return true }
            return !existingIDs.contains(externalID)
        }
        transactions.append(contentsOf: newTransactions)
        transactions.sort { $0.date > $1.date }
        saveTransactions()
        return newTransactions.count
    }

    func update(_ transaction: Transaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
        transactions.sort { $0.date > $1.date }
        saveTransactions()
    }

    func delete(_ transaction: Transaction) {
        transactions.removeAll { $0.id == transaction.id }
        saveTransactions()
    }

    func delete(at offsets: IndexSet, from displayedTransactions: [Transaction]) {
        let ids = offsets.map { displayedTransactions[$0].id }
        transactions.removeAll { ids.contains($0.id) }
        saveTransactions()
    }

    /// Removes only the transactions saved on this iPhone. Budget settings,
    /// net-worth history, sign-in, and bank connections are intentionally kept.
    func clearAllTransactions() {
        transactions = []
        saveTransactions()
    }

    func resetLocalData() {
        transactions = []
        settings = BudgetSettings()
        netWorthSnapshots = []
        saveTransactions()
        saveSettings()
        recordCurrentNetWorth()
        objectWillChange.send()
    }

    private func load() {
        do {
            transactions = try JSONDecoder().decode([Transaction].self, from: Data(contentsOf: transactionsURL))
            transactions.sort { $0.date > $1.date }
        } catch {
            transactions = []
            saveTransactions()
        }

        if let data = try? Data(contentsOf: settingsURL), let decoded = try? JSONDecoder().decode(BudgetSettings.self, from: data) {
            settings = decoded
        } else {
            saveSettings()
        }

        if let data = try? Data(contentsOf: netWorthURL),
           let decoded = try? JSONDecoder().decode([NetWorthSnapshot].self, from: data) {
            netWorthSnapshots = decoded.sorted { $0.date < $1.date }
        }
        recordCurrentNetWorth()
    }

    private func saveTransactions() {
        do { try JSONEncoder().encode(transactions).write(to: transactionsURL, options: .atomic) }
        catch { print("Could not save transactions: \(error.localizedDescription)") }
    }

    private func saveSettings() {
        do { try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        catch { print("Could not save budget settings: \(error.localizedDescription)") }
    }

    private func recordCurrentNetWorth() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let snapshot = NetWorthSnapshot(date: today, cash: settings.currentSavings, investments: settings.investmentBalance)
        if let index = netWorthSnapshots.firstIndex(where: { calendar.isDate($0.date, inSameDayAs: today) }) {
            netWorthSnapshots[index] = snapshot
        } else if netWorthSnapshots.count == 1,
                  let index = netWorthSnapshots.firstIndex(where: { calendar.isDate($0.date, equalTo: today, toGranularity: .month) }) {
            // Migrate the original monthly-only snapshot to the new daily history format.
            netWorthSnapshots[index] = snapshot
        } else {
            netWorthSnapshots.append(snapshot)
        }
        netWorthSnapshots.sort { $0.date < $1.date }
        saveNetWorthSnapshots()
    }

    private func saveNetWorthSnapshots() {
        do { try JSONEncoder().encode(netWorthSnapshots).write(to: netWorthURL, options: .atomic) }
        catch { print("Could not save net worth history: \(error.localizedDescription)") }
    }

}
