import Foundation

@MainActor
final class TransactionStore: ObservableObject {
    @Published private(set) var transactions: [Transaction] = []

    private let saveURL: URL

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = documents.appendingPathComponent("transactions.json")
        load()
    }

    func add(_ transaction: Transaction) {
        transactions.append(transaction)
        transactions.sort { $0.date > $1.date }
        save()
    }

    func delete(at offsets: IndexSet, from displayedTransactions: [Transaction]) {
        let ids = offsets.map { displayedTransactions[$0].id }
        transactions.removeAll { ids.contains($0.id) }
        save()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: saveURL)
            transactions = try JSONDecoder().decode([Transaction].self, from: data)
            transactions.sort { $0.date > $1.date }
        } catch {
            transactions = Self.sampleTransactions
            save()
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(transactions)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Could not save transactions: \(error.localizedDescription)")
        }
    }

    private static var sampleTransactions: [Transaction] {
        let calendar = Calendar.current
        let now = Date()
        func day(_ value: Int) -> Date {
            calendar.date(bySetting: .day, value: value, of: now) ?? now
        }

        return [
            Transaction(amount: 3200, category: .other, date: day(1), notes: "Monthly paycheck", isIncome: true),
            Transaction(amount: 1250, category: .rent, date: day(2), notes: "Apartment rent", isIncome: false),
            Transaction(amount: 64.35, category: .food, date: day(5), notes: "Groceries", isIncome: false),
            Transaction(amount: 28.50, category: .transport, date: day(8), notes: "Gas", isIncome: false),
            Transaction(amount: 15, category: .entertainment, date: day(10), notes: "Movie night", isIncome: false)
        ].sorted { $0.date > $1.date }
    }
}
