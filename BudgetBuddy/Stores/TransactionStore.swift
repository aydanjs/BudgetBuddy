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

    var plannedNetIncome: Decimal { settings.hourlyRate * settings.scheduledHours * (1 - settings.taxRate) }
    var plannedTithing: Decimal { plannedNetIncome * settings.tithingRate }
    var savingsGoal: Decimal { plannedNetIncome * settings.savingsRate }
    var monthlyDebtPayments: Decimal { settings.debts.reduce(0) { $0 + $1.monthlyPayment } }
    var totalPlannedSpending: Decimal { settings.categoryBudgets.values.reduce(0, +) + plannedTithing + monthlyDebtPayments }
    var plannedSavings: Decimal { plannedNetIncome - totalPlannedSpending }
    var currentNetWorth: Decimal { settings.currentSavings + settings.investmentBalance }

    func transactions(in month: Date) -> [Transaction] {
        transactions.filter { Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    func actualIncome(in month: Date) -> Decimal {
        transactions(in: month).filter(\.isIncome).reduce(0) { $0 + $1.amount }
    }

    func actualSpending(in month: Date) -> Decimal {
        transactions(in: month).filter { !$0.isIncome && $0.category != .savings }.reduce(0) { $0 + $1.amount }
    }

    func actualSpending(for category: TransactionCategory, in month: Date) -> Decimal {
        transactions(in: month).filter { !$0.isIncome && $0.category == category }.reduce(0) { $0 + $1.amount }
    }

    func budget(for category: TransactionCategory) -> Decimal {
        if category == .tithing { return plannedTithing }
        if category == .savings { return plannedSavings }
        if category == .debtPayment { return monthlyDebtPayments }
        return settings.categoryBudgets[category.rawValue] ?? 0
    }

    func setBudget(_ amount: Decimal, for category: TransactionCategory) {
        settings.categoryBudgets[category.rawValue] = max(0, amount)
        saveSettings()
        objectWillChange.send()
    }

    func updateSettings(_ update: (inout BudgetSettings) -> Void) {
        update(&settings)
        saveSettings()
        recordCurrentNetWorth()
        objectWillChange.send()
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

    private func load() {
        do {
            transactions = try JSONDecoder().decode([Transaction].self, from: Data(contentsOf: transactionsURL))
            transactions.sort { $0.date > $1.date }
        } catch {
            transactions = Self.sampleTransactions
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

    private static var sampleTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        func day(_ value: Int) -> Date { calendar.date(bySetting: .day, value: value, of: now) ?? now }
        return [
            Transaction(amount: 3_200, category: .other, date: day(1), notes: "Monthly paycheck", isIncome: true),
            Transaction(amount: 1_250, category: .rent, date: day(2), notes: "Apartment rent", isIncome: false),
            Transaction(amount: 64.35, category: .groceries, date: day(5), notes: "Groceries", isIncome: false),
            Transaction(amount: 28.50, category: .gas, date: day(8), notes: "Gas", isIncome: false),
            Transaction(amount: 15, category: .fun, date: day(10), notes: "Movie night", isIncome: false)
        ].sorted { $0.date > $1.date }
    }
}
