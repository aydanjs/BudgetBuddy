import Foundation

enum ContributionPlanMode: String, Codable, CaseIterable, Identifiable {
    case automaticRemainder = "What is left"
    case percentage = "Percent of income"
    case fixedAmount = "Fixed amount"

    var id: String { rawValue }
}

enum BudgetGroup: String, Codable, CaseIterable, Identifiable {
    case needs = "Needs"
    case wants = "Wants"
    case giving = "Giving"
    case savings = "Savings"
    var id: String { rawValue }
}

struct CustomBudgetCategory: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var group: BudgetGroup
    var symbol: String

    var transactionCategory: TransactionCategory {
        .custom(id: id, name: name, group: group, symbol: symbol)
    }
}

enum TransactionCategory: Codable, Hashable, Identifiable {
    case rent, college, car, insurance, groceries, hygiene, laundry, gas, other
    case fastFood, fun, gifts, dates, bigPurchase, tithing, savings, debtPayment
    case custom(id: UUID, name: String, group: BudgetGroup, symbol: String)

    var id: String {
        if case let .custom(id, _, _, _) = self { return "custom-\(id.uuidString)" }
        return rawValue
    }

    var rawValue: String {
        switch self {
        case .rent: "Rent"
        case .college: "College"
        case .car: "Car"
        case .insurance: "Insurance"
        case .groceries: "Groceries"
        case .hygiene: "Hygiene"
        case .laundry: "Laundry"
        case .gas: "Gas"
        case .other: "Other"
        case .fastFood: "Fast Food"
        case .fun: "Fun"
        case .gifts: "Gifts"
        case .dates: "Dates"
        case .bigPurchase: "Big Purchase"
        case .tithing: "Tithing"
        case .savings: "Savings"
        case .debtPayment: "Debt Payments"
        case let .custom(_, name, _, _): name
        }
    }

    var group: BudgetGroup {
        switch self {
        case .rent, .college, .car, .insurance, .groceries, .hygiene, .laundry, .gas, .other, .debtPayment: .needs
        case .fastFood, .fun, .gifts, .dates, .bigPurchase: .wants
        case .tithing: .giving
        case .savings: .savings
        case let .custom(_, _, group, _): group
        }
    }

    var symbol: String {
        switch self {
        case .rent: "house.fill"
        case .college: "graduationcap.fill"
        case .car: "car.fill"
        case .insurance: "shield.fill"
        case .groceries: "cart.fill"
        case .hygiene: "sparkles"
        case .laundry: "washer.fill"
        case .gas: "fuelpump.fill"
        case .other: "ellipsis.circle.fill"
        case .fastFood: "takeoutbag.and.cup.and.straw.fill"
        case .fun: "party.popper.fill"
        case .gifts: "gift.fill"
        case .dates: "heart.fill"
        case .bigPurchase: "bag.fill"
        case .tithing: "hands.sparkles.fill"
        case .savings: "banknote.fill"
        case .debtPayment: "creditcard.fill"
        case let .custom(_, _, _, symbol): symbol
        }
    }

    static let expenseCategories: [TransactionCategory] = [
        .rent, .college, .car, .insurance, .groceries, .hygiene, .laundry, .gas, .other,
        .fastFood, .fun, .gifts, .dates, .tithing, .debtPayment
    ]

    private struct CustomPayload: Codable {
        let id: UUID
        let name: String
        let group: BudgetGroup
        let symbol: String
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            switch value {
            case "Food": self = .groceries
            case "Transport": self = .gas
            case "Entertainment": self = .fun
            case "Shopping": self = .bigPurchase
            case "Rent": self = .rent
            case "College": self = .college
            case "Car": self = .car
            case "Insurance": self = .insurance
            case "Groceries": self = .groceries
            case "Hygiene": self = .hygiene
            case "Laundry": self = .laundry
            case "Gas": self = .gas
            case "Other": self = .other
            case "Fast Food": self = .fastFood
            case "Fun": self = .fun
            case "Gifts": self = .gifts
            case "Dates": self = .dates
            case "Big Purchase": self = .bigPurchase
            case "Tithing": self = .tithing
            case "Savings": self = .savings
            case "Debt Payments": self = .debtPayment
            default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown category")
            }
            return
        }
        let payload = try container.decode(CustomPayload.self)
        self = .custom(id: payload.id, name: payload.name, group: payload.group, symbol: payload.symbol)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if case let .custom(id, name, group, symbol) = self {
            try container.encode(CustomPayload(id: id, name: name, group: group, symbol: symbol))
        } else {
            try container.encode(rawValue)
        }
    }
}

enum DebtType: String, Codable, CaseIterable, Identifiable {
    case creditCard = "Credit Card"
    case carLoan = "Car Loan"
    case mortgage = "Mortgage"
    case studentLoan = "Student Loan"
    case personalLoan = "Personal / Other"
    var id: String { rawValue }
}

struct Debt: Identifiable, Codable {
    var id = UUID()
    var name: String = ""
    var type: DebtType = .creditCard
    var balance: Decimal = 0
    /// Set only for credit cards. Keeping this optional preserves older saved budgets.
    var creditLimit: Decimal?
    var apr: Decimal = 0
    var minimumPayment: Decimal = 0
    var extraPayment: Decimal = 0

    var monthlyPayment: Decimal { minimumPayment + extraPayment }

    var availableCredit: Decimal? {
        guard type == .creditCard, let creditLimit, creditLimit > 0 else { return nil }
        return max(0, creditLimit - balance)
    }
}

struct Transaction: Identifiable, Codable {
    let id: UUID
    var amount: Decimal
    var category: TransactionCategory
    var date: Date
    var notes: String
    var isIncome: Bool
    var isTransfer: Bool
    var externalID: String?

    init(id: UUID = UUID(), amount: Decimal, category: TransactionCategory, date: Date, notes: String, isIncome: Bool, isTransfer: Bool = false, externalID: String? = nil) {
        self.id = id
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
        self.isIncome = isIncome
        self.isTransfer = isTransfer
        self.externalID = externalID
    }

    private enum CodingKeys: String, CodingKey {
        case id, amount, category, date, notes, isIncome, isTransfer, externalID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        amount = try container.decode(Decimal.self, forKey: .amount)
        category = try container.decode(TransactionCategory.self, forKey: .category)
        date = try container.decode(Date.self, forKey: .date)
        notes = try container.decode(String.self, forKey: .notes)
        isIncome = try container.decode(Bool.self, forKey: .isIncome)
        isTransfer = try container.decodeIfPresent(Bool.self, forKey: .isTransfer) ?? false
        externalID = try container.decodeIfPresent(String.self, forKey: .externalID)
    }
}

struct NetWorthSnapshot: Identifiable, Codable {
    let id: UUID
    var date: Date
    var cash: Decimal
    var investments: Decimal

    var total: Decimal { cash + investments }

    init(id: UUID = UUID(), date: Date, cash: Decimal, investments: Decimal) {
        self.id = id
        self.date = date
        self.cash = cash
        self.investments = investments
    }
}

struct SavingsGoal: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String = ""
    var targetAmount: Decimal = 0
    var targetDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var savedAmount: Decimal = 0
    var deductFromForecast = true

    var remainingAmount: Decimal { max(0, targetAmount - savedAmount) }
    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(1, max(0, NSDecimalNumber(decimal: savedAmount / targetAmount).doubleValue))
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        targetAmount: Decimal = 0,
        targetDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
        savedAmount: Decimal = 0,
        deductFromForecast: Bool = true
    ) {
        self.id = id
        self.name = name
        self.targetAmount = targetAmount
        self.targetDate = targetDate
        self.savedAmount = savedAmount
        self.deductFromForecast = deductFromForecast
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, targetAmount, targetDate, savedAmount, deductFromForecast
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decodeIfPresent(String.self, forKey: .name) ?? ""
        targetAmount = try values.decodeIfPresent(Decimal.self, forKey: .targetAmount) ?? 0
        targetDate = try values.decodeIfPresent(Date.self, forKey: .targetDate)
            ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        savedAmount = try values.decodeIfPresent(Decimal.self, forKey: .savedAmount) ?? 0
        // Existing goals began as planned purchases, so they keep affecting the forecast after migration.
        deductFromForecast = try values.decodeIfPresent(Bool.self, forKey: .deductFromForecast) ?? true
    }
}

enum IncomeType: String, Codable, CaseIterable, Identifiable {
    case hourly = "Hourly"
    case salary = "Annual Salary"
    case paycheck = "Take-home Paycheck"
    var id: String { rawValue }

    static let selectableCases: [IncomeType] = [.salary, .hourly]

    var displayName: String {
        switch self {
        case .salary, .paycheck: "Salary"
        case .hourly: "Hourly"
        }
    }
}

enum PayFrequency: String, Codable, CaseIterable, Identifiable {
    case weekly = "Weekly"
    case biweekly = "Every 2 Weeks"
    case semimonthly = "Twice a Month"
    case monthly = "Monthly"

    var id: String { rawValue }

    var paymentsPerMonth: Decimal {
        switch self {
        case .weekly: 52 / 12
        case .biweekly: 26 / 12
        case .semimonthly: 2
        case .monthly: 1
        }
    }
}

enum HousingType: String, Codable, CaseIterable, Identifiable {
    case rent = "Rent"
    case mortgage = "Mortgage"
    case neither = "Neither"
    var id: String { rawValue }
}

struct BudgetSettings: Codable {
    var incomeType: IncomeType = .hourly
    var payFrequency: PayFrequency = .biweekly
    var hourlyRate: Decimal = 0
    var scheduledHours: Decimal = 0
    var hoursPerWeek: Decimal = 0
    var annualSalary: Decimal = 0
    var takeHomePaycheck: Decimal = 0
    var taxRate: Decimal = 0
    var tithingEnabled = false
    var tithingRate: Decimal = 0.10
    var savingsRate: Decimal = 0
    var startingCash: Decimal = 0
    var firstBudgetMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    var categoryBudgets: [String: Decimal] = Self.defaultBudgets
    var customCategories: [CustomBudgetCategory] = []
    var hiddenBuiltInCategoryIDs: Set<String> = []
    var currentSavings: Decimal = 0
    var startingInvestmentBalance: Decimal = 0
    var monthlySavingsContribution: Decimal = 0
    var savingsAPY: Decimal = 0
    var investmentBalance: Decimal = 0
    var monthlyInvestmentContribution: Decimal = 0
    var savingsContributionMode: ContributionPlanMode = .automaticRemainder
    var investmentContributionMode: ContributionPlanMode = .percentage
    var investmentRate: Decimal = 0.05
    var lowInvestmentReturn: Decimal = 0.04
    var baseInvestmentReturn: Decimal = 0.08
    var highInvestmentReturn: Decimal = 0.12
    var bigPurchaseName: String = ""
    var bigPurchaseCost: Decimal = 0
    var bigPurchaseDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var debts: [Debt] = []
    var housingType: HousingType = .rent
    var mortgageBalance: Decimal = 0
    var mortgageInterestRate: Decimal = 0
    var mortgageYearsRemaining: Decimal = 0
    var housingDueDay: Int = 1
    var balanceAnchorDate: Date = Date()
    var lastLinkedCashBalance: Decimal?
    var lastLinkedInvestmentBalance: Decimal?
    var weeklyBudgetAllocations: [String: [Decimal]] = [:]
    var savingsGoals: [SavingsGoal] = []
    var emergencyMonthlyExpenses: Decimal = 0
    var emergencyFundMonths: Int = 3
    var emergencyFundSaved: Decimal = 0

    static let defaultBudgets: [String: Decimal] = [:]

    private enum CodingKeys: String, CodingKey {
        case incomeType, payFrequency, hourlyRate, scheduledHours, hoursPerWeek, annualSalary, takeHomePaycheck
        case taxRate, tithingEnabled, tithingRate, savingsRate, startingCash, firstBudgetMonth, categoryBudgets, customCategories, hiddenBuiltInCategoryIDs
        case currentSavings, startingInvestmentBalance, monthlySavingsContribution, savingsAPY, investmentBalance, monthlyInvestmentContribution
        case savingsContributionMode, investmentContributionMode, investmentRate
        case lowInvestmentReturn, baseInvestmentReturn, highInvestmentReturn
        case bigPurchaseName, bigPurchaseCost, bigPurchaseDate, debts
        case housingType, mortgageBalance, mortgageInterestRate, mortgageYearsRemaining
        case housingDueDay, balanceAnchorDate, lastLinkedCashBalance, lastLinkedInvestmentBalance, weeklyBudgetAllocations, savingsGoals
        case emergencyMonthlyExpenses, emergencyFundMonths, emergencyFundSaved
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case expectedInvestmentReturn
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        incomeType = try values.decodeIfPresent(IncomeType.self, forKey: .incomeType) ?? .hourly
        if incomeType == .paycheck { incomeType = .salary }
        payFrequency = try values.decodeIfPresent(PayFrequency.self, forKey: .payFrequency) ?? .biweekly
        hourlyRate = try values.decodeIfPresent(Decimal.self, forKey: .hourlyRate) ?? 0
        scheduledHours = try values.decodeIfPresent(Decimal.self, forKey: .scheduledHours) ?? 0
        hoursPerWeek = try values.decodeIfPresent(Decimal.self, forKey: .hoursPerWeek) ?? (scheduledHours / 4)
        annualSalary = try values.decodeIfPresent(Decimal.self, forKey: .annualSalary) ?? 0
        takeHomePaycheck = try values.decodeIfPresent(Decimal.self, forKey: .takeHomePaycheck) ?? 0
        taxRate = try values.decodeIfPresent(Decimal.self, forKey: .taxRate) ?? 0
        if incomeType == .salary, takeHomePaycheck == 0, annualSalary > 0 {
            let estimatedMonthlyTakeHome = (annualSalary / 12) * (1 - taxRate)
            takeHomePaycheck = estimatedMonthlyTakeHome / payFrequency.paymentsPerMonth
        }
        let previousTithingRate = try values.decodeIfPresent(Decimal.self, forKey: .tithingRate) ?? 0
        tithingEnabled = try values.decodeIfPresent(Bool.self, forKey: .tithingEnabled) ?? (previousTithingRate > 0)
        tithingRate = 0.10
        savingsRate = try values.decodeIfPresent(Decimal.self, forKey: .savingsRate) ?? 0
        startingCash = try values.decodeIfPresent(Decimal.self, forKey: .startingCash) ?? 0
        firstBudgetMonth = try values.decodeIfPresent(Date.self, forKey: .firstBudgetMonth)
            ?? Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        categoryBudgets = try values.decodeIfPresent([String: Decimal].self, forKey: .categoryBudgets) ?? Self.defaultBudgets
        customCategories = try values.decodeIfPresent([CustomBudgetCategory].self, forKey: .customCategories) ?? []
        hiddenBuiltInCategoryIDs = try values.decodeIfPresent(Set<String>.self, forKey: .hiddenBuiltInCategoryIDs) ?? []
        currentSavings = try values.decodeIfPresent(Decimal.self, forKey: .currentSavings) ?? startingCash
        if startingCash == 0, currentSavings > 0 { startingCash = currentSavings }
        monthlySavingsContribution = try values.decodeIfPresent(Decimal.self, forKey: .monthlySavingsContribution) ?? 0
        savingsAPY = try values.decodeIfPresent(Decimal.self, forKey: .savingsAPY) ?? 0
        investmentBalance = try values.decodeIfPresent(Decimal.self, forKey: .investmentBalance) ?? 0
        startingInvestmentBalance = try values.decodeIfPresent(Decimal.self, forKey: .startingInvestmentBalance) ?? investmentBalance
        monthlyInvestmentContribution = try values.decodeIfPresent(Decimal.self, forKey: .monthlyInvestmentContribution) ?? 0
        savingsContributionMode = try values.decodeIfPresent(ContributionPlanMode.self, forKey: .savingsContributionMode)
            ?? (monthlySavingsContribution > 0 ? .fixedAmount : savingsRate > 0 ? .percentage : .automaticRemainder)
        investmentContributionMode = try values.decodeIfPresent(ContributionPlanMode.self, forKey: .investmentContributionMode)
            ?? (monthlyInvestmentContribution > 0 ? .fixedAmount : .percentage)
        investmentRate = try values.decodeIfPresent(Decimal.self, forKey: .investmentRate) ?? 0.05
        let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let previousReturn = try legacyValues.decodeIfPresent(Decimal.self, forKey: .expectedInvestmentReturn)
        lowInvestmentReturn = try values.decodeIfPresent(Decimal.self, forKey: .lowInvestmentReturn) ?? 0.04
        baseInvestmentReturn = try values.decodeIfPresent(Decimal.self, forKey: .baseInvestmentReturn) ?? previousReturn ?? 0.08
        highInvestmentReturn = try values.decodeIfPresent(Decimal.self, forKey: .highInvestmentReturn) ?? 0.12
        bigPurchaseName = try values.decodeIfPresent(String.self, forKey: .bigPurchaseName) ?? ""
        bigPurchaseCost = try values.decodeIfPresent(Decimal.self, forKey: .bigPurchaseCost) ?? 0
        bigPurchaseDate = try values.decodeIfPresent(Date.self, forKey: .bigPurchaseDate)
            ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        debts = try values.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        housingType = try values.decodeIfPresent(HousingType.self, forKey: .housingType) ?? .rent
        mortgageBalance = try values.decodeIfPresent(Decimal.self, forKey: .mortgageBalance) ?? 0
        mortgageInterestRate = try values.decodeIfPresent(Decimal.self, forKey: .mortgageInterestRate) ?? 0
        mortgageYearsRemaining = try values.decodeIfPresent(Decimal.self, forKey: .mortgageYearsRemaining) ?? 0
        housingDueDay = min(31, max(1, try values.decodeIfPresent(Int.self, forKey: .housingDueDay) ?? 1))
        balanceAnchorDate = try values.decodeIfPresent(Date.self, forKey: .balanceAnchorDate) ?? firstBudgetMonth
        lastLinkedCashBalance = try values.decodeIfPresent(Decimal.self, forKey: .lastLinkedCashBalance)
        lastLinkedInvestmentBalance = try values.decodeIfPresent(Decimal.self, forKey: .lastLinkedInvestmentBalance)
        weeklyBudgetAllocations = try values.decodeIfPresent([String: [Decimal]].self, forKey: .weeklyBudgetAllocations) ?? [:]
        if let decodedGoals = try values.decodeIfPresent([SavingsGoal].self, forKey: .savingsGoals) {
            savingsGoals = decodedGoals
        } else if bigPurchaseCost > 0, !bigPurchaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            savingsGoals = [SavingsGoal(name: bigPurchaseName, targetAmount: bigPurchaseCost, targetDate: bigPurchaseDate)]
        } else {
            savingsGoals = []
        }
        emergencyMonthlyExpenses = try values.decodeIfPresent(Decimal.self, forKey: .emergencyMonthlyExpenses) ?? 0
        let decodedEmergencyMonths = try values.decodeIfPresent(Int.self, forKey: .emergencyFundMonths) ?? 3
        emergencyFundMonths = [3, 6, 12].contains(decodedEmergencyMonths) ? decodedEmergencyMonths : 3
        emergencyFundSaved = try values.decodeIfPresent(Decimal.self, forKey: .emergencyFundSaved) ?? 0
    }
}
