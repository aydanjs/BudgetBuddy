import Foundation

struct BudgetWeek: Identifiable, Hashable {
    let index: Int
    let start: Date
    let end: Date
    var id: Int { index }
    var title: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }
}

@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var settings = BudgetSettings()
    @Published private(set) var netWorthSnapshots: [NetWorthSnapshot] = []

    private let transactionsURL: URL
    private let settingsURL: URL
    private let netWorthURL: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
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
    var plannedTithing: Decimal { settings.tithingEnabled ? plannedNetIncome * settings.tithingRate : 0 }
    var savingsGoal: Decimal { plannedNetIncome * settings.savingsRate }
    var monthlyDebtPayments: Decimal { settings.debts.reduce(0) { $0 + $1.monthlyPayment } }
    var totalPlannedSpending: Decimal { totalPlannedSpending(in: Date()) }
    func totalPlannedSpending(in month: Date) -> Decimal {
        let flexible = flexibleExpenseCategories.reduce(0) { $0 + budget(for: $1, in: month) }
        return flexible + budget(for: .rent, in: month) + budget(for: .tithing, in: month) + monthlyDebtPayments
    }
    var plannedSavings: Decimal {
        let flexible = flexibleExpenseCategories.reduce(0) { $0 + budget(for: $1) }
        return plannedNetIncome - flexible - budget(for: .rent) - plannedTithing - monthlyDebtPayments
    }
    var plannedInvestmentContribution: Decimal {
        switch settings.investmentContributionMode {
        case .percentage:
            return max(0, plannedNetIncome * settings.investmentRate)
        case .fixedAmount, .automaticRemainder:
            return max(0, settings.monthlyInvestmentContribution)
        }
    }
    var plannedSavingsContribution: Decimal {
        switch settings.savingsContributionMode {
        case .automaticRemainder:
            return max(0, plannedSavings - plannedInvestmentContribution)
        case .percentage:
            return max(0, plannedNetIncome * settings.savingsRate)
        case .fixedAmount:
            return max(0, settings.monthlySavingsContribution)
        }
    }
    private var balanceCalculationStart: Date {
        let anchor = settings.balanceAnchorDate > Date() ? settings.firstBudgetMonth : settings.balanceAnchorDate
        return Calendar.current.startOfDay(for: anchor)
    }
    private var cashBaseline: Decimal {
        settings.lastLinkedCashBalance ?? settings.startingCash
    }
    private func affectsCurrentCash(_ transaction: Transaction) -> Bool {
        transaction.date >= balanceCalculationStart &&
        !transaction.isTransfer &&
        transaction.category != .savings &&
        (settings.lastLinkedCashBalance == nil || transaction.externalID == nil)
    }
    private var recordedCashChange: Decimal {
        transactions
            .filter(affectsCurrentCash)
            .reduce(Decimal.zero) { partial, transaction in
                partial + (transaction.isIncome ? transaction.amount : -transaction.amount)
            }
    }
    var currentCashBalance: Decimal {
        cashBaseline + recordedCashChange
    }
    var currentInvestmentBalance: Decimal {
        if let linkedBalance = settings.lastLinkedInvestmentBalance { return linkedBalance }
        return settings.investmentBalance == 0 ? settings.startingInvestmentBalance : settings.investmentBalance
    }
    var currentNetWorth: Decimal { currentCashBalance + currentInvestmentBalance }
    var housingLabel: String { settings.housingType == .mortgage ? "Mortgage" : "Rent" }
    var expenseCategories: [TransactionCategory] {
        TransactionCategory.expenseCategories.filter {
            !settings.hiddenBuiltInCategoryIDs.contains($0.id) && ($0 != .tithing || settings.tithingEnabled)
        }
            + settings.customCategories.map(\.transactionCategory)
    }
    var manageableBuiltInCategories: [TransactionCategory] {
        TransactionCategory.expenseCategories.filter { $0 != .tithing && $0 != .debtPayment }
    }
    var flexibleExpenseCategories: [TransactionCategory] {
        expenseCategories.filter { $0 != .rent && $0 != .tithing && $0 != .debtPayment && $0 != .savings && $0 != .bigPurchase }
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

    func budget(for category: TransactionCategory) -> Decimal { budget(for: category, in: Date()) }

    func budget(for category: TransactionCategory, in month: Date) -> Decimal {
        if category == .tithing { return settings.tithingEnabled ? actualIncome(in: month) * settings.tithingRate : 0 }
        if category == .savings { return plannedSavings }
        if category == .debtPayment { return monthlyDebtPayments }
        if category == .rent && settings.housingType == .neither { return 0 }
        return settings.categoryBudgets[category.rawValue] ?? 0
    }

    func budgetWeeks(in month: Date) -> [BudgetWeek] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let dayRange = calendar.range(of: .day, in: .month, for: month)
        else { return [] }
        let lastDay = dayRange.count
        let starts = [1, 8, 15, 22, 29].filter { $0 <= lastDay }
        return starts.enumerated().compactMap { offset, day in
            guard let start = calendar.date(byAdding: .day, value: day - 1, to: monthStart),
                  let end = calendar.date(byAdding: .day, value: min(day + 6, lastDay) - 1, to: monthStart)
            else { return nil }
            return BudgetWeek(index: offset, start: start, end: end)
        }
    }

    func currentWeek(in month: Date = Date()) -> BudgetWeek? {
        let calendar = Calendar.current
        return budgetWeeks(in: month).first { week in
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: week.end) ?? week.end
            return Date() >= week.start && Date() < endOfDay
        }
    }

    func weeklyBudget(for category: TransactionCategory, weekIndex: Int, in month: Date) -> Decimal {
        let weeks = budgetWeeks(in: month)
        guard weeks.indices.contains(weekIndex) else { return 0 }
        let key = weeklyAllocationKey(category: category, month: month)
        let monthly = budget(for: category, in: month)
        if let values = settings.weeklyBudgetAllocations[key], values.indices.contains(weekIndex) {
            let savedTotal = values.reduce(0, +)
            if savedTotal > 0 {
                return values[weekIndex] * monthly / savedTotal
            }
        }
        let totalDays = weeks.reduce(0) {
            $0 + (Calendar.current.dateComponents([.day], from: $1.start, to: $1.end).day ?? 0) + 1
        }
        let days = (Calendar.current.dateComponents([.day], from: weeks[weekIndex].start, to: weeks[weekIndex].end).day ?? 0) + 1
        return totalDays > 0 ? monthly * Decimal(days) / Decimal(totalDays) : 0
    }

    func weeklyAllocations(for category: TransactionCategory, in month: Date) -> [Decimal] {
        budgetWeeks(in: month).map { weeklyBudget(for: category, weekIndex: $0.index, in: month) }
    }

    func setWeeklyAllocations(_ values: [Decimal], for category: TransactionCategory, in month: Date) {
        settings.weeklyBudgetAllocations[weeklyAllocationKey(category: category, month: month)] = values.map { max(0, $0) }
        saveSettings()
        objectWillChange.send()
    }

    func weeklyFlexibleBudget(weekIndex: Int, in month: Date) -> Decimal {
        flexibleExpenseCategories.reduce(0) { $0 + weeklyBudget(for: $1, weekIndex: weekIndex, in: month) }
    }

    func weeklyFlexibleSpending(weekIndex: Int, in month: Date) -> Decimal {
        let weeks = budgetWeeks(in: month)
        guard weeks.indices.contains(weekIndex) else { return 0 }
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: weeks[weekIndex].end) ?? weeks[weekIndex].end
        return transactions.filter {
            !$0.isIncome && !$0.isTransfer && $0.category != .savings &&
            flexibleExpenseCategories.contains($0.category) && $0.date >= weeks[weekIndex].start && $0.date < end
        }.reduce(0) { $0 + $1.amount }
    }

    func housingIsDue(in week: BudgetWeek, month: Date) -> Bool {
        guard settings.housingType != .neither else { return false }
        let lastDay = Calendar.current.range(of: .day, in: .month, for: month)?.count ?? 31
        let dueDay = min(lastDay, settings.housingDueDay)
        let startDay = Calendar.current.component(.day, from: week.start)
        let endDay = Calendar.current.component(.day, from: week.end)
        return (startDay...endDay).contains(dueDay)
    }

    func saveGoal(_ goal: SavingsGoal) {
        updateSettings { settings in
            if let index = settings.savingsGoals.firstIndex(where: { $0.id == goal.id }) {
                settings.savingsGoals[index] = goal
            } else {
                settings.savingsGoals.append(goal)
            }
        }
    }

    func deleteGoal(at offsets: IndexSet) {
        let ids = offsets.map { settings.savingsGoals[$0].id }
        updateSettings { $0.savingsGoals.removeAll { ids.contains($0.id) } }
    }

    func contribute(_ amount: Decimal, to goalID: UUID) {
        let available = availableToAssignToGoals
        updateSettings { settings in
            guard let index = settings.savingsGoals.firstIndex(where: { $0.id == goalID }) else { return }
            let permittedAmount = amount > 0 ? min(amount, available) : amount
            settings.savingsGoals[index].savedAmount = max(0, settings.savingsGoals[index].savedAmount + permittedAmount)
        }
    }

    var emergencyFundTarget: Decimal {
        settings.emergencyMonthlyExpenses * Decimal(settings.emergencyFundMonths)
    }

    var emergencyFundRemaining: Decimal {
        max(0, emergencyFundTarget - settings.emergencyFundSaved)
    }

    var emergencyFundProgress: Double {
        guard emergencyFundTarget > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: settings.emergencyFundSaved / emergencyFundTarget).doubleValue))
    }

    func contributeToEmergencyFund(_ amount: Decimal) {
        let available = availableToAssignToGoals
        let remaining = emergencyFundRemaining
        updateSettings { settings in
            let permittedAmount = amount > 0 ? min(amount, available, remaining) : amount
            settings.emergencyFundSaved = max(0, settings.emergencyFundSaved + permittedAmount)
        }
    }

    var availableToAssignToGoals: Decimal {
        max(0, currentCashBalance - settings.emergencyFundSaved - settings.savingsGoals.reduce(0) { $0 + $1.savedAmount })
    }

    var calculatedNetWorthSnapshots: [NetWorthSnapshot] {
        let calendar = Calendar.current
        let anchor = balanceCalculationStart
        let baseline = cashBaseline
        var points = [NetWorthSnapshot(date: min(anchor, Date()), cash: baseline, investments: currentInvestmentBalance)]
        var cash = baseline
        let relevant = transactions.filter(affectsCurrentCash).sorted { $0.date < $1.date }
        for transaction in relevant {
            cash += transaction.isIncome ? transaction.amount : -transaction.amount
            points.append(NetWorthSnapshot(date: transaction.date, cash: cash, investments: currentInvestmentBalance))
        }
        if !calendar.isDate(points.last?.date ?? anchor, inSameDayAs: Date()) {
            points.append(NetWorthSnapshot(date: Date(), cash: cash, investments: currentInvestmentBalance))
        }
        return points
    }

    func setBudget(_ amount: Decimal, for category: TransactionCategory) {
        settings.categoryBudgets[category.rawValue] = max(0, amount)
        saveSettings()
        objectWillChange.send()
    }

    func tithingPaid(in month: Date) -> Decimal {
        actualSpending(for: .tithing, in: month)
    }

    func tithingRemaining(in month: Date) -> Decimal {
        max(0, budget(for: .tithing, in: month) - tithingPaid(in: month))
    }

    func markTithingPaid(in month: Date) {
        let remaining = tithingRemaining(in: month)
        guard settings.tithingEnabled, remaining > 0 else { return }

        let calendar = Calendar.current
        let paymentDate: Date
        if calendar.isDate(month, equalTo: Date(), toGranularity: .month) {
            paymentDate = Date()
        } else if let monthInterval = calendar.dateInterval(of: .month, for: month),
                  let finalDay = calendar.date(byAdding: .day, value: -1, to: monthInterval.end) {
            paymentDate = finalDay
        } else {
            paymentDate = month
        }

        add(Transaction(
            amount: remaining,
            category: .tithing,
            date: paymentDate,
            notes: "Monthly tithing · 10% of income",
            isIncome: false
        ))
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
        objectWillChange.send()
    }

    func applyLinkedAccountBalances(cash: Decimal?, investments: Decimal?) {
        guard cash != nil || investments != nil else { return }

        updateSettings { settings in
            if let cash {
                settings.currentSavings = max(0, cash)
                settings.lastLinkedCashBalance = max(0, cash)
                if settings.balanceAnchorDate > Date() {
                    settings.balanceAnchorDate = settings.firstBudgetMonth
                }
            }
            if let investments {
                settings.investmentBalance = max(0, investments)
                settings.lastLinkedInvestmentBalance = max(0, investments)
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
            let adjustedBaseline = max(0, snapshot.cash - recordedCashChange)
            if updatedSettings.lastLinkedCashBalance == nil {
                updatedSettings.startingCash = adjustedBaseline
            } else {
                updatedSettings.lastLinkedCashBalance = adjustedBaseline
            }
            updatedSettings.currentSavings = adjustedBaseline
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
        if fileManager.fileExists(atPath: transactionsURL.path) {
            do {
                transactions = try JSONDecoder().decode([Transaction].self, from: Data(contentsOf: transactionsURL))
                transactions.sort { $0.date > $1.date }
            } catch {
                preserveUnreadableFile(at: transactionsURL, error: error)
            }
        } else {
            saveTransactions()
        }

        if fileManager.fileExists(atPath: settingsURL.path) {
            do {
                settings = try JSONDecoder().decode(BudgetSettings.self, from: Data(contentsOf: settingsURL))
            // Older bank-sync builds moved the anchor to tomorrow so imported
            // transactions would not be counted twice. Preserve that live cash
            // amount as the bank baseline, restore the real budget start, and
            // let manual entries affect Total Money again.
            if settings.balanceAnchorDate > Date() {
                settings.lastLinkedCashBalance = settings.currentSavings
                settings.balanceAnchorDate = settings.firstBudgetMonth
                saveSettings()
            }
            if settings.lowInvestmentReturn == 0,
               settings.baseInvestmentReturn == 0,
               settings.highInvestmentReturn == 0 {
                settings.lowInvestmentReturn = 0.04
                settings.baseInvestmentReturn = 0.08
                settings.highInvestmentReturn = 0.12
                saveSettings()
            }
            } catch {
                preserveUnreadableFile(at: settingsURL, error: error)
            }
        } else {
            saveSettings()
        }

        if fileManager.fileExists(atPath: netWorthURL.path) {
            do {
                let decoded = try JSONDecoder().decode([NetWorthSnapshot].self, from: Data(contentsOf: netWorthURL))
                netWorthSnapshots = decoded.sorted { $0.date < $1.date }

                // Recover a setup investment balance saved by an older build if a
                // later refresh incorrectly replaced the current value with zero.
                if settings.startingInvestmentBalance == 0,
                   settings.investmentBalance == 0,
                   let previousInvestmentBalance = decoded.map(\.investments).filter({ $0 > 0 }).max() {
                    settings.startingInvestmentBalance = previousInvestmentBalance
                    settings.investmentBalance = previousInvestmentBalance
                    saveSettings()
                }
            } catch {
                preserveUnreadableFile(at: netWorthURL, error: error)
            }
        }
        recordCurrentNetWorth()
    }

    private func preserveUnreadableFile(at url: URL, error: Error) {
        print("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
        let backupURL = url.appendingPathExtension("recovery-backup")
        guard !fileManager.fileExists(atPath: backupURL.path) else { return }
        do {
            try fileManager.copyItem(at: url, to: backupURL)
        } catch {
            print("Could not preserve \(url.lastPathComponent): \(error.localizedDescription)")
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

    private func weeklyAllocationKey(category: TransactionCategory, month: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(components.year ?? 0)-\(components.month ?? 0)|\(category.id)"
    }

    private func recordCurrentNetWorth() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let snapshot = NetWorthSnapshot(date: today, cash: currentCashBalance, investments: currentInvestmentBalance)
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
