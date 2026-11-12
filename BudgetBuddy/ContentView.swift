import SwiftUI

struct ContentView: View {
    @State private var showingAddTransaction = false

    var body: some View {
        TabView {
            NavigationStack { DashboardView(showingAddTransaction: $showingAddTransaction) }
                .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            NavigationStack { BudgetView() }
                .tabItem { Label("Budget", systemImage: "chart.bar.fill") }

            NavigationStack { TransactionListView(showingAddTransaction: $showingAddTransaction) }
                .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.indigo)
        .sheet(isPresented: $showingAddTransaction) {
            NavigationStack { AddTransactionView() }
        }
    }
}
