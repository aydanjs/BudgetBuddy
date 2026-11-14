import SwiftUI
import LinkKit
import AuthenticationServices
import Security

struct PlaidConnectionView: View {
    @EnvironmentObject private var store: TransactionStore
    @StateObject private var model = PlaidConnectionModel()
    @StateObject private var auth = BudgetBuddyAuthSession()
    @State private var importedMessage: String?
    @State private var isPresentingLink = false

    var body: some View {
        List {
            Section("BudgetBuddy account") {
                if auth.isSignedIn {
                    Label("Signed in securely", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Button("Sign Out", role: .destructive) { auth.signOut() }
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        Task { await auth.completeAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
#if DEBUG
                    Button("Developer Sign In") { Task { await auth.developmentSignIn() } }
#endif
                }
                if let message = auth.errorMessage { Text(message).foregroundStyle(.red).font(.footnote) }
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    Label(model.isConnected ? "Connect Another Bank" : "Connect a Bank", systemImage: "link")
                }
                .disabled(model.isLoading || !auth.isSignedIn)

                if model.isConnected {
                    Button {
                        Task { await model.sync() }
                    } label: {
                        Label("Sync Transactions", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(model.isLoading)
                }

                if model.isLoading { ProgressView("Contacting Plaid…") }
                if let message = model.errorMessage { Text(message).foregroundStyle(.red).font(.footnote) }
                if let importedMessage { Text(importedMessage).foregroundStyle(.green).font(.footnote) }
            } header: {
                Text("Bank connection")
            } footer: {
                Text("Plaid handles bank sign-in. BudgetBuddy never sees or stores your bank password.")
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
        .navigationTitle("Bank Sync")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingLink) {
            model.linkSession?.sheet()
        }
        .onChange(of: auth.sessionToken) { _, token in model.sessionToken = token }
        .task { model.sessionToken = auth.sessionToken }
    }

    @MainActor
    private func connect() async {
        do {
            let token = try await model.createLinkToken()
            let configuration = LinkTokenConfiguration(
                token: token,
                onSuccess: { success in
                    isPresentingLink = false
                    model.linkSession = nil
                    Task { await model.exchange(publicToken: success.publicToken) }
                },
                onExit: { exit in
                    isPresentingLink = false
                    model.linkSession = nil
                    if let error = exit.error { model.errorMessage = error.localizedDescription }
                },
                onEvent: { _ in },
                onLoad: { }
            )
            model.linkSession = try Plaid.createPlaidLinkSession(configuration: configuration)
            isPresentingLink = true
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

}

@MainActor
final class PlaidConnectionModel: ObservableObject {
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reviewItems: [PlaidReviewItem] = []

    // LinkKit's session owns the presented Plaid flow and must stay alive until
    // the user finishes or closes it.
    var linkSession: PlaidLinkSession?

    var sessionToken: String?
    private let baseURL = BudgetBuddyAPI.baseURL

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
        if let sessionToken { request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization") }
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

private enum BudgetBuddyAPI {
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BUDGETBUDDY_API_URL") as? String,
           let url = URL(string: value), !value.contains("YOUR_") { return url }
        return URL(string: "https://budgetbuddy-api-vwtp.onrender.com")!
    }
}

@MainActor
private final class BudgetBuddyAuthSession: ObservableObject {
    @Published private(set) var sessionToken: String? = KeychainSession.load()
    @Published var errorMessage: String?
    var isSignedIn: Bool { sessionToken != nil }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        do {
            let authorization = try result.get()
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken,
                  let identityToken = String(data: data, encoding: .utf8) else {
                throw PlaidLocalError(message: "Apple did not return a valid identity token.")
            }
            try await authenticate(path: "/api/auth/apple", body: ["identity_token": identityToken])
        } catch { errorMessage = error.localizedDescription }
    }

#if DEBUG
    func developmentSignIn() async {
        do { try await authenticate(path: "/api/auth/development", body: [:]) }
        catch { errorMessage = error.localizedDescription }
    }
#endif

    func signOut() {
        KeychainSession.delete()
        sessionToken = nil
    }

    private func authenticate(path: String, body: [String: String]) async throws {
        var request = URLRequest(url: BudgetBuddyAPI.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "BudgetBuddy sign-in failed."
            throw PlaidLocalError(message: message)
        }
        let token = try JSONDecoder.plaid.decode(SessionResponse.self, from: data).sessionToken
        try KeychainSession.save(token)
        sessionToken = token
        errorMessage = nil
    }
}

private struct SessionResponse: Decodable { let sessionToken: String }

private enum KeychainSession {
    private static let service = "com.aydanjs.BudgetBuddyFinance"
    private static let account = "api-session"

    static func save(_ token: String) throws {
        delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else {
            throw PlaidLocalError(message: "Could not securely save your sign-in.")
        }
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

struct PlaidReviewItem: Identifiable {
    let id = UUID()
    let source: PlaidTransaction
    var category: TransactionCategory
    var isSelected = true
}

private struct EmptyBody: Encodable {}
private struct PublicTokenBody: Encodable {
    let publicToken: String

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
    }
}
private struct LinkTokenResponse: Decodable { let linkToken: String }
private struct ExchangeResponse: Decodable { let connected: Bool }
private struct ServerError: Decodable { let error: String }
private struct SyncResponse: Decodable {
    let added: [PlaidTransaction]

    enum CodingKeys: String, CodingKey { case added }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        added = try container.decodeIfPresent([PlaidTransaction].self, forKey: .added) ?? []
    }
}

struct PlaidPersonalFinanceCategory: Decodable {
    let primary: String

    enum CodingKeys: String, CodingKey { case primary }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primary = try container.decodeIfPresent(String.self, forKey: .primary) ?? "OTHER"
    }
}

struct PlaidTransaction: Decodable {
    let transactionID: String
    let name: String
    let amount: Double
    let date: String
    let pending: Bool
    let isoCurrencyCode: String?
    let personalFinanceCategory: PlaidPersonalFinanceCategory?

    enum CodingKeys: String, CodingKey {
        case transactionID, name, amount, date, pending
        case isoCurrencyCode, personalFinanceCategory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transactionID = try container.decodeIfPresent(String.self, forKey: .transactionID) ?? UUID().uuidString
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Transaction"
        amount = try container.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Self.today
        pending = try container.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        isoCurrencyCode = try container.decodeIfPresent(String.self, forKey: .isoCurrencyCode)
        personalFinanceCategory = try container.decodeIfPresent(PlaidPersonalFinanceCategory.self, forKey: .personalFinanceCategory)
    }

    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
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
