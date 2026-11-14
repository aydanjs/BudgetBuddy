import Foundation

enum BudgetGroup: String, Codable, CaseIterable, Identifiable {
    case needs = "Needs"
    case wants = "Wants"
    case giving = "Giving"
    case savings = "Savings"
    var id: String { rawValue }
}

enum TransactionCategory: String, Codable, CaseIterable, Identifiable {
    case rent = "Rent", college = "College", car = "Car", insurance = "Insurance"
    case groceries = "Groceries", hygiene = "Hygiene", laundry = "Laundry", gas = "Gas", other = "Other"
    case fastFood = "Fast Food", fun = "Fun", gifts = "Gifts", dates = "Dates", bigPurchase = "Big Purchase"
    case tithing = "Tithing", savings = "Savings"
    case debtPayment = "Debt Payments"

    var id: String { rawValue }

    var group: BudgetGroup {
        switch self {
        case .rent, .college, .car, .insurance, .groceries, .hygiene, .laundry, .gas, .other, .debtPayment: .needs
        case .fastFood, .fun, .gifts, .dates, .bigPurchase: .wants
        case .tithing: .giving
        case .savings: .savings
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
        }
    }

    static var expenseCategories: [TransactionCategory] { allCases.filter { $0 != .savings } }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "Food": self = .groceries
        case "Transport": self = .gas
        case "Entertainment": self = .fun
        case "Shopping": self = .bigPurchase
        default:
            guard let category = Self(rawValue: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown category")
            }
            self = category
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
    var apr: Decimal = 0
    var minimumPayment: Decimal = 0
    var extraPayment: Decimal = 0

    var monthlyPayment: Decimal { minimumPayment + extraPayment }
}

struct Transaction: Identifiable, Codable {
    let id: UUID
    var amount: Decimal
    var category: TransactionCategory
    var date: Date
    var notes: String
    var isIncome: Bool
    var externalID: String?

    init(id: UUID = UUID(), amount: Decimal, category: TransactionCategory, date: Date, notes: String, isIncome: Bool, externalID: String? = nil) {
        self.id = id
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
        self.isIncome = isIncome
        self.externalID = externalID
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

struct BudgetSettings: Codable {
    var hourlyRate: Decimal = 20
    var scheduledHours: Decimal = 160
    var taxRate: Decimal = 0.10
    var tithingRate: Decimal = 0.10
    var savingsRate: Decimal = 0.20
    var startingCash: Decimal = 0
    var firstBudgetMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    var categoryBudgets: [String: Decimal] = Self.defaultBudgets
    var currentSavings: Decimal = 5_000
    var monthlySavingsContribution: Decimal = 500
    var savingsAPY: Decimal = 0.04
    var investmentBalance: Decimal = 2_000
    var monthlyInvestmentContribution: Decimal = 200
    var lowInvestmentReturn: Decimal = 0.04
    var baseInvestmentReturn: Decimal = 0.08
    var highInvestmentReturn: Decimal = 0.12
    var bigPurchaseName: String = "New car"
    var bigPurchaseCost: Decimal = 20_000
    var bigPurchaseDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var debts: [Debt] = []

    static let defaultBudgets: [String: Decimal] = [
        TransactionCategory.rent.rawValue: 1_250,
        TransactionCategory.groceries.rawValue: 400,
        TransactionCategory.gas.rawValue: 150,
        TransactionCategory.insurance.rawValue: 120,
        TransactionCategory.fastFood.rawValue: 80,
        TransactionCategory.fun.rawValue: 100,
        TransactionCategory.gifts.rawValue: 50,
        TransactionCategory.dates.rawValue: 75
    ]

    private enum CodingKeys: String, CodingKey {
        case hourlyRate, scheduledHours, taxRate, tithingRate, savingsRate, startingCash, firstBudgetMonth, categoryBudgets
        case currentSavings, monthlySavingsContribution, savingsAPY, investmentBalance, monthlyInvestmentContribution
        case lowInvestmentReturn, baseInvestmentReturn, highInvestmentReturn
        case bigPurchaseName, bigPurchaseCost, bigPurchaseDate, debts
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case expectedInvestmentReturn
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hourlyRate = try values.decodeIfPresent(Decimal.self, forKey: .hourlyRate) ?? 20
        scheduledHours = try values.decodeIfPresent(Decimal.self, forKey: .scheduledHours) ?? 160
        taxRate = try values.decodeIfPresent(Decimal.self, forKey: .taxRate) ?? 0.10
        tithingRate = try values.decodeIfPresent(Decimal.self, forKey: .tithingRate) ?? 0.10
        savingsRate = try values.decodeIfPresent(Decimal.self, forKey: .savingsRate) ?? 0.20
        startingCash = try values.decodeIfPresent(Decimal.self, forKey: .startingCash) ?? 0
        firstBudgetMonth = try values.decodeIfPresent(Date.self, forKey: .firstBudgetMonth)
            ?? Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
        categoryBudgets = try values.decodeIfPresent([String: Decimal].self, forKey: .categoryBudgets) ?? Self.defaultBudgets
        currentSavings = try values.decodeIfPresent(Decimal.self, forKey: .currentSavings) ?? 5_000
        monthlySavingsContribution = try values.decodeIfPresent(Decimal.self, forKey: .monthlySavingsContribution) ?? 500
        savingsAPY = try values.decodeIfPresent(Decimal.self, forKey: .savingsAPY) ?? 0.04
        investmentBalance = try values.decodeIfPresent(Decimal.self, forKey: .investmentBalance) ?? 2_000
        monthlyInvestmentContribution = try values.decodeIfPresent(Decimal.self, forKey: .monthlyInvestmentContribution) ?? 200
        let legacyValues = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let previousReturn = try legacyValues.decodeIfPresent(Decimal.self, forKey: .expectedInvestmentReturn)
        lowInvestmentReturn = try values.decodeIfPresent(Decimal.self, forKey: .lowInvestmentReturn) ?? 0.04
        baseInvestmentReturn = try values.decodeIfPresent(Decimal.self, forKey: .baseInvestmentReturn) ?? previousReturn ?? 0.08
        highInvestmentReturn = try values.decodeIfPresent(Decimal.self, forKey: .highInvestmentReturn) ?? 0.12
        bigPurchaseName = try values.decodeIfPresent(String.self, forKey: .bigPurchaseName) ?? "New car"
        bigPurchaseCost = try values.decodeIfPresent(Decimal.self, forKey: .bigPurchaseCost) ?? 20_000
        bigPurchaseDate = try values.decodeIfPresent(Date.self, forKey: .bigPurchaseDate)
            ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        debts = try values.decodeIfPresent([Debt].self, forKey: .debts) ?? []
    }
}
