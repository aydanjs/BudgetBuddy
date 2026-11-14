import SwiftUI

let currencyCode = Locale.current.currency?.identifier ?? "USD"

struct ContentView: View {
    @State private var showingAddTransaction = false
    @State private var selectedTab: AppTab = .dashboard
    @State private var transactionMonth: Date?

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    showingAddTransaction: $showingAddTransaction,
                    selectedTab: $selectedTab,
                    transactionMonth: $transactionMonth
                )
            }
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                .tag(AppTab.dashboard)

            NavigationStack { BudgetView() }
                .tabItem { Label("Budget", systemImage: "chart.bar.fill") }
                .tag(AppTab.budget)

            NavigationStack {
                TransactionListView(showingAddTransaction: $showingAddTransaction, selectedMonth: $transactionMonth)
            }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.transactions)

            NavigationStack { ForecastView() }
                .tabItem { Label("Plan", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.plan)
        }
        .tint(.budgetBuddyBlue)
        .sheet(isPresented: $showingAddTransaction) {
            NavigationStack { AddTransactionView() }
        }
    }
}

enum AppTab: Hashable {
    case dashboard, budget, transactions, plan
}

extension Color {
    static let budgetBuddyBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
}
