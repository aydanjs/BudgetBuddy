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

    var id: String { rawValue }

    var group: BudgetGroup {
        switch self {
        case .rent, .college, .car, .insurance, .groceries, .hygiene, .laundry, .gas, .other: .needs
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

struct Transaction: Identifiable, Codable {
    let id: UUID
    var amount: Decimal
    var category: TransactionCategory
    var date: Date
    var notes: String
    var isIncome: Bool

    init(id: UUID = UUID(), amount: Decimal, category: TransactionCategory, date: Date, notes: String, isIncome: Bool) {
        self.id = id
        self.amount = amount
        self.category = category
        self.date = date
        self.notes = notes
        self.isIncome = isIncome
    }
}

struct BudgetSettings: Codable {
    var hourlyRate: Decimal = 20
    var scheduledHours: Decimal = 160
    var taxRate: Decimal = 0.10
    var tithingRate: Decimal = 0.10
    var startingCash: Decimal = 0
    var firstBudgetMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    var categoryBudgets: [String: Decimal] = Self.defaultBudgets

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
}
