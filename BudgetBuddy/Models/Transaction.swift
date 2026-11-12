import Foundation

enum TransactionCategory: String, Codable, CaseIterable, Identifiable {
    case food = "Food"
    case rent = "Rent"
    case transport = "Transport"
    case entertainment = "Entertainment"
    case shopping = "Shopping"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .rent: "house.fill"
        case .transport: "car.fill"
        case .entertainment: "film.fill"
        case .shopping: "bag.fill"
        case .other: "ellipsis.circle.fill"
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
