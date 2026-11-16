import SwiftUI
import LinkKit
import AuthenticationServices
import Security

struct PlaidConnectionView: View {
    @EnvironmentObject private var store: TransactionStore
    @EnvironmentObject private var appAuth: AuthSessionStore
    @StateObject private var model = PlaidConnectionModel()
    @State private var importedMessage: String?
    @State private var isPresentingLink = false
    @State private var isPresentingConsent = false

    var body: some View {
        List {
            Section("Turtle Budgeting account") {
                if appAuth.serverSessionToken != nil {
                    Label("Verified with your Apple login", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(Color.budgetBuddyGreen)
                } else if appAuth.isServerAuthenticating {
                    ProgressView("Securing your account…")
                } else {
                    Text("Continue with the same Apple account to restore your secure bank-sync session.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        appAuth.completeAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                }
                if let message = appAuth.serverAuthenticationMessage {
                    Text(message).foregroundStyle(.red).font(.footnote)
                }
            }

            Section {
                Button {
                    isPresentingConsent = true
                } label: {
                    Label(model.isConnected ? "Connect Another Bank" : "Connect a Bank", systemImage: "link")
                }
                .disabled(model.isLoading || appAuth.serverSessionToken == nil)

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
                if let importedMessage { Text(importedMessage).foregroundStyle(Color.budgetBuddyGreen).font(.footnote) }
            } header: {
                Text("Bank connection")
            } footer: {
                Text("Plaid handles bank sign-in. Turtle Budgeting never sees or stores your bank password.")
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
                                    ForEach(store.expenseCategories) { category in
                                        Text(category.rawValue).tag(category)
                                    }
                                }
                                .pickerStyle(.menu)
                            } else {
                                Text("Income").font(.caption).foregroundStyle(Color.budgetBuddyGreen)
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
        .sheet(isPresented: $isPresentingConsent) {
            PlaidConsentSheet {
                Task {
                    guard await model.recordPlaidConsent() else { return }
                    isPresentingConsent = false
                    await connect()
                }
            }
        }
        .onChange(of: appAuth.serverSessionToken) { _, token in
            model.sessionToken = token
            if token != nil { model.sessionExpired = false }
        }
        .onChange(of: model.sessionExpired) { _, expired in
            if expired { appAuth.clearExpiredServerSession() }
        }
        .task {
            model.sessionToken = appAuth.serverSessionToken
            await model.loadConnections()
        }
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

private struct PlaidConsentSheet: View {
    @SwiftUI.Environment(\.dismiss) private var dismiss
    @State private var hasAgreed = false
    let continueToPlaid: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(Color.budgetBuddyGreen)

                    Text("Before you connect")
                        .font(.title2.bold())

                    Text("Plaid will securely show your bank’s sign-in screen. Turtle Budgeting never sees or stores your bank username or password.")

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Plaid may share the account and transaction data you approve.", systemImage: "building.columns.fill")
                        Label("Turtle Budgeting stores an encrypted connection token and imported transaction data so bank sync can work.", systemImage: "lock.fill")
                        Label("You can disconnect a bank or delete your online account and bank-sync data at any time in Settings.", systemImage: "trash.fill")
                    }
                    .font(.subheadline)

                    Toggle("I have read and agree to the Privacy Notice for this optional bank connection.", isOn: $hasAgreed)
                        .toggleStyle(.switch)
                        .font(.subheadline.weight(.medium))

                    Link("Read the full Privacy Notice", destination: URL(string: "https://github.com/aydanjs/BudgetBuddy/blob/main/PRIVACY_POLICY.md")!)
                        .font(.subheadline)
                }
                .padding(24)
            }
            .navigationTitle("Bank connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") { continueToPlaid() }
                        .disabled(!hasAgreed)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

@MainActor
final class PlaidConnectionModel: ObservableObject {
    @Published var isConnected = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var reviewItems: [PlaidReviewItem] = []
    @Published var sessionExpired = false
    @Published var connections: [PlaidBankConnection] = []

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

    func recordPlaidConsent() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let _: PlaidConsentResponse = try await post(
                "/api/consents/plaid",
                body: PlaidConsentBody(policyVersion: "2026-11-15")
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func exchange(publicToken: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let _: ExchangeResponse = try await post("/api/exchange-public-token", body: PublicTokenBody(publicToken: publicToken))
            isConnected = true
            await loadConnections()
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

    func loadConnections() async {
        guard sessionToken != nil else {
            connections = []
            isConnected = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let response: ConnectionsResponse = try await get("/api/connections")
            connections = response.connections
            isConnected = !connections.isEmpty
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disconnect(_ connection: PlaidBankConnection) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await delete("/api/connections/\(connection.itemID)")
            connections.removeAll { $0.itemID == connection.itemID }
            isConnected = !connections.isEmpty
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
            if (response as? HTTPURLResponse)?.statusCode == 401 { sessionExpired = true }
            throw PlaidLocalError(message: message, statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        return try JSONDecoder.plaid.decode(Response.self, from: data)
    }

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        if let sessionToken { request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization") }
        return try await perform(request)
    }

    private func delete(_ path: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
        if let sessionToken { request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization") }
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            if (response as? HTTPURLResponse)?.statusCode == 401 { sessionExpired = true }
            throw PlaidLocalError(message: "BudgetBuddy could not remove this bank connection.", statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "The BudgetBuddy server returned an error."
            if (response as? HTTPURLResponse)?.statusCode == 401 { sessionExpired = true }
            throw PlaidLocalError(message: message, statusCode: (response as? HTTPURLResponse)?.statusCode)
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

struct ConnectedAccountsView: View {
    @EnvironmentObject private var appAuth: AuthSessionStore
    @StateObject private var model = PlaidConnectionModel()
    @StateObject private var liveSummary = PlaidLiveSummaryModel()
    @State private var connectionPendingRemoval: PlaidBankConnection?

    var body: some View {
        List {
            if appAuth.serverSessionToken == nil {
                Section("Secure sign-in needed") {
                    Text("Sign in with the Apple account you used for BudgetBuddy to manage your connected banks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.email]
                    } onCompletion: { result in
                        appAuth.completeAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    if let message = appAuth.serverAuthenticationMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
            } else {
                connectedAccountsContent
            }

            if model.isLoading {
                Section { HStack { Spacer(); ProgressView("Updating bank connections…"); Spacer() } }
            }

            if let message = model.errorMessage {
                Section { Text(message).foregroundStyle(.red).font(.footnote) }
            }
        }
        .navigationTitle("Connected Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.loadConnections() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh connected accounts")
                .disabled(model.isLoading || appAuth.serverSessionToken == nil)
            }
        }
        .refreshable { await model.loadConnections() }
        .onChange(of: appAuth.serverSessionToken) { _, token in
            model.sessionToken = token
            if token != nil { Task { await model.loadConnections() } }
        }
        .onChange(of: model.sessionExpired) { _, expired in
            if expired { appAuth.clearExpiredServerSession() }
        }
        .onChange(of: liveSummary.sessionExpired) { _, expired in
            if expired { appAuth.clearExpiredServerSession() }
        }
        .task {
            model.sessionToken = appAuth.serverSessionToken
            await model.loadConnections()
        }
        .confirmationDialog(
            "Disconnect this bank?",
            isPresented: Binding(get: { connectionPendingRemoval != nil }, set: { if !$0 { connectionPendingRemoval = nil } }),
            titleVisibility: .visible,
            presenting: connectionPendingRemoval
        ) { connection in
            Button("Disconnect \(connection.institutionName ?? "bank")", role: .destructive) {
                Task { await model.disconnect(connection) }
                connectionPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { connectionPendingRemoval = nil }
        } message: { connection in
            Text("This stops future imports from this bank and removes the secure Plaid connection. Transactions you already imported on this iPhone will stay unless you delete them.")
        }
    }

    @ViewBuilder
    private var connectedAccountsContent: some View {
        if model.connections.isEmpty, !model.isLoading {
            Section {
                ContentUnavailableView {
                    Label("No connected banks", systemImage: "building.columns")
                } description: {
                    Text("Connect a bank when you're ready. Plaid handles the bank sign-in, and BudgetBuddy never sees your password.")
                } actions: {
                    NavigationLink("Connect a bank") { PlaidConnectionView() }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.budgetBuddyGreen)
                }
            }
        } else {
            connectedBanksSection
            liveLinkedMoneySection
            connectedAccountActionsSection
        }
    }

    private var connectedBanksSection: some View {
        Section {
            ForEach(model.connections) { connection in
                ConnectedBankRow(
                    connection: connection,
                    connectionPendingRemoval: $connectionPendingRemoval
                )
            }
        } header: {
            Text("Your connected banks")
        }
    }

    private var liveLinkedMoneySection: some View {
        Section {
            if let summary = liveSummary.summary {
                if summary.balanceAvailable {
                    LabeledContent("Cash across linked banks") {
                        Text(summary.cashTotal, format: .currency(code: currencyCode)).bold()
                    }
                } else {
                    Label("Live cash balance unavailable", systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if summary.investmentsAvailable, let investments = summary.investmentsTotal {
                    LabeledContent("Linked investments") {
                        Text(investments, format: .currency(code: currencyCode)).bold()
                    }
                } else if summary.portfolioProductsEnabled {
                    Text("No investment holdings were available from these connections.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if summary.liabilitiesAvailable, let liabilities = summary.liabilitiesTotal {
                    LabeledContent("Linked debt") {
                        Text(liabilities, format: .currency(code: currencyCode)).bold()
                    }
                }

                Text("Updated \(summary.retrievedAtText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Load real balances from your connected accounts when you want an update.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await liveSummary.load(sessionToken: appAuth.serverSessionToken) }
            } label: {
                Label("Load live values", systemImage: "arrow.clockwise.circle.fill")
            }
            .disabled(liveSummary.isLoading)

            if liveSummary.isLoading {
                ProgressView("Loading live values…")
            }
            if let message = liveSummary.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Live linked money")
        } footer: {
            Text("Live values are shown separately from your budget plan and forecast. Investments and debt appear after Plaid approves those products and the account is connected with permission to share them.")
        }
    }

    private var connectedAccountActionsSection: some View {
        Section {
            NavigationLink {
                PlaidConnectionView()
            } label: {
                Label("Connect another bank", systemImage: "plus.circle.fill")
            }

            NavigationLink {
                PlaidConnectionView()
            } label: {
                Label("Review and sync transactions", systemImage: "arrow.triangle.2.circlepath")
            }
        } footer: {
            Text("Syncing checks each connected bank for new transactions. You can review imports before they are added to your budget.")
        }
    }
}

private struct ConnectedBankRow: View {
    let connection: PlaidBankConnection
    @Binding var connectionPendingRemoval: PlaidBankConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(connection.institutionName ?? "Connected bank", systemImage: "building.columns.fill")
                .font(.body.weight(.semibold))

            Text("Last synced \(connection.lastUpdatedText)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let error = connection.errorCode, !error.isEmpty {
                Label("Needs attention: \(error)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                connectionPendingRemoval = connection
            } label: {
                Label("Disconnect", systemImage: "trash")
            }
        }
    }
}

@MainActor
final class PlaidLiveSummaryModel: ObservableObject {
    @Published private(set) var summary: PlaidLiveSummary?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var sessionExpired = false

    func load(sessionToken: String?) async {
        guard let sessionToken else {
            errorMessage = "Sign in with Apple to load your connected account values."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: BudgetBuddyAPI.baseURL.appendingPathComponent("/api/live-summary"))
            request.httpMethod = "GET"
            request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                if (response as? HTTPURLResponse)?.statusCode == 401 { sessionExpired = true }
                let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "BudgetBuddy could not load live account values."
                throw PlaidLocalError(message: message, statusCode: (response as? HTTPURLResponse)?.statusCode)
            }
            summary = try JSONDecoder.plaid.decode(PlaidLiveSummary.self, from: data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum BudgetBuddyAPI {
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "BUDGETBUDDY_API_URL") as? String,
           let url = URL(string: value), !value.contains("YOUR_") { return url }
        return URL(string: "https://budgetbuddy-api-vwtp.onrender.com")!
    }
}

struct SessionResponse: Decodable { let sessionToken: String }

enum KeychainSession {
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
private struct PlaidConsentBody: Encodable {
    let policyVersion: String

    enum CodingKeys: String, CodingKey {
        case policyVersion = "policy_version"
    }
}
private struct PublicTokenBody: Encodable {
    let publicToken: String

    enum CodingKeys: String, CodingKey {
        case publicToken = "public_token"
    }
}
private struct LinkTokenResponse: Decodable { let linkToken: String }
private struct PlaidConsentResponse: Decodable { let consented: Bool }
private struct ExchangeResponse: Decodable { let connected: Bool }
private struct ConnectionsResponse: Decodable { let connections: [PlaidBankConnection] }

struct PlaidBankConnection: Decodable, Identifiable {
    let itemID: String
    let institutionName: String?
    let errorCode: String?
    let updatedAt: String?

    var id: String { itemID }

    var lastUpdatedText: String {
        guard let updatedAt else { return "recently" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: updatedAt) else { return "recently" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct PlaidLiveSummary: Decodable {
    let cashTotal: Double
    let investmentsTotal: Double?
    let liabilitiesTotal: Double?
    let balanceAvailable: Bool
    let investmentsAvailable: Bool
    let liabilitiesAvailable: Bool
    let portfolioProductsEnabled: Bool
    let retrievedAt: String

    var retrievedAtText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        guard let date = formatter.date(from: retrievedAt) else { return "just now" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
struct ServerError: Decodable { let error: String }
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

struct PlaidLocalError: LocalizedError {
    let message: String
    var statusCode: Int? = nil
    var errorDescription: String? { message }
}

extension JSONDecoder {
    static var plaid: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
