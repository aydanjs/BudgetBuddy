import Foundation

@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var settings = BudgetSettings()

    private let transactionsURL: URL
    private let settingsURL: URL

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        transactionsURL = documents.appendingPathComponent("transactions.json")
        settingsURL = documents.appendingPathComponent("budget-settings.json")
        load()
    }

    var plannedNetIncome: Decimal { settings.hourlyRate * settings.scheduledHours * (1 - settings.taxRate) }
    var plannedTithing: Decimal { plannedNetIncome * settings.tithingRate }
    var savingsGoal: Decimal { plannedNetIncome * settings.savingsRate }
    var totalPlannedSpending: Decimal { settings.categoryBudgets.values.reduce(0, +) + plannedTithing }
    var plannedSavings: Decimal { plannedNetIncome - totalPlannedSpending }

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
        objectWillChange.send()
    }

    func add(_ transaction: Transaction) {
        transactions.append(transaction)
        transactions.sort { $0.date > $1.date }
        saveTransactions()
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
    }

    private func saveTransactions() {
        do { try JSONEncoder().encode(transactions).write(to: transactionsURL, options: .atomic) }
        catch { print("Could not save transactions: \(error.localizedDescription)") }
    }

    private func saveSettings() {
        do { try JSONEncoder().encode(settings).write(to: settingsURL, options: .atomic) }
        catch { print("Could not save budget settings: \(error.localizedDescription)") }
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
