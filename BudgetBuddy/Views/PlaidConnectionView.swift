import SwiftUI
import LinkKit

struct PlaidConnectionView: View {
    @EnvironmentObject private var store: TransactionStore
    @StateObject private var model = PlaidConnectionModel()
    @State private var importedMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    Task { await connect() }
                } label: {
                    Label(model.isConnected ? "Reconnect Sandbox Bank" : "Connect Sandbox Bank", systemImage: "link")
                }
                .disabled(model.isLoading)

                if model.isConnected {
                    Button {
                        Task { await model.sync() }
                    } label: {
                        Label("Sync Transactions", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isLoading)
                }

                if model.isLoading { ProgressView("Contacting Plaid Sandbox…") }
                if let message = model.errorMessage { Text(message).foregroundStyle(.red).font(.footnote) }
                if let importedMessage { Text(importedMessage).foregroundStyle(.green).font(.footnote) }
            } header: {
                Text("Sandbox connection")
            } footer: {
                Text("Use Plaid's test institution and test credentials only. The local server must be running on this Mac.")
            }

            if !model.reviewItems.isEmpty {
                Section("Review before importing") {
                    ForEach($model.reviewItems) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle(isOn: $item.isSelected) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.source.name).font(.body.weight(.medium))
                                        Text(item.source.date).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(abs(item.source.amount), format: .currency(code: item.source.isoCurrencyCode ?? currencyCode)).bold()
                                }
                            }
                            if item.source.amount >= 0 {
                                Picker("Category", selection: $item.category) {
                                    ForEach(TransactionCategory.expenseCategories) { category in
                                        Text(category.rawValue).tag(category)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                Text("Income").font(.caption).foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button("Import Selected") { importSelected() }
                        .frame(maxWidth: .infinity)
                        .disabled(!model.reviewItems.contains(where: \.isSelected))
                }
            }
        }
        .navigationTitle("Plaid Sandbox")
        .navigationBarTitleDisplayMode(.inline)
    }

    @MainActor
    private func connect() async {
        do {
            let token = try await model.createLinkToken()
            var configuration = LinkTokenConfiguration(token: token) { success in
                Task { await model.exchange(publicToken: success.publicToken) }
            }
            configuration.onExit = { exit in
                if let error = exit.error { model.errorMessage = error.localizedDescription }
            }
            switch Plaid.create(configuration) {
            case .failure(let error): model.errorMessage = error.localizedDescription
            case .success(let handler):
                guard let presenter = topViewController() else {
                    model.errorMessage = "Could not open Plaid Link."
                    return
                }
                handler.open(presentUsing: .viewController(presenter))
            }
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func importSelected() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let transactions = model.reviewItems.filter(\.isSelected).compactMap { item -> Transaction? in
            guard let date = dateFormatter.date(from: item.source.date) else { return nil }
            return Transaction(
                amount: Decimal(abs(item.source.amount)),
                category: item.category,
                date: date,
                notes: item.source.name,
                isIncome: item.source.amount < 0,
                externalID: item.source.transactionID
            )
        }
        let count = store.importTransactions(transactions)
        model.reviewItems.removeAll { $0.isSelected }
        importedMessage = count == 1 ? "Imported 1 transaction." : "Imported \(count) transactions."
    }

    private func topViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              var controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let presented = controller.presentedViewController { controller = presented }
        return controller
    }
}

@MainActor
final class PlaidConnectionModel: ObservableObject {
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reviewItems: [PlaidReviewItem] = []

    private let baseURL = URL(string: "http://127.0.0.1:8080")!

    func createLinkToken() async throws -> String {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let response: LinkTokenResponse = try await post("/api/create-link-token", body: EmptyBody())
        return response.linkToken
    }

    func exchange(publicToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let _: ExchangeResponse = try await post("/api/exchange-public-token", body: PublicTokenBody(publicToken: publicToken))
            isConnected = true
            await sync()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sync() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: SyncResponse = try await post("/api/transactions-sync", body: EmptyBody())
            reviewItems = response.added.filter { !$0.pending }.map { transaction in
                PlaidReviewItem(source: transaction, category: Self.suggestedCategory(for: transaction))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func post<Response: Decodable, Body: Encodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "The local Plaid server returned an error."
            throw PlaidLocalError(message: message)
        }
        return try JSONDecoder.plaid.decode(Response.self, from: data)
    }

    private static func suggestedCategory(for transaction: PlaidTransaction) -> TransactionCategory {
        switch transaction.personalFinanceCategory?.primary {
        case "FOOD_AND_DRINK": .groceries
        case "TRANSPORTATION": .gas
        case "RENT_AND_UTILITIES": .rent
        case "ENTERTAINMENT": .fun
        case "GENERAL_MERCHANDISE": .bigPurchase
        case "EDUCATION": .college
        default: .other
        }
    }
}

struct PlaidReviewItem: Identifiable {
    let id = UUID()
    let source: PlaidTransaction
    var category: TransactionCategory
    var isSelected = true
}

private struct EmptyBody: Encodable {}
private struct PublicTokenBody: Encodable { let publicToken: String }
private struct LinkTokenResponse: Decodable { let linkToken: String }
private struct ExchangeResponse: Decodable { let connected: Bool }
private struct ServerError: Decodable { let error: String }
private struct SyncResponse: Decodable { let added: [PlaidTransaction] }
struct PlaidPersonalFinanceCategory: Decodable { let primary: String }

struct PlaidTransaction: Decodable {
    let transactionID: String
    let name: String
    let amount: Double
    let date: String
    let pending: Bool
    let isoCurrencyCode: String?
    let personalFinanceCategory: PlaidPersonalFinanceCategory?
}

private struct PlaidLocalError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private extension JSONDecoder {
    static var plaid: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
