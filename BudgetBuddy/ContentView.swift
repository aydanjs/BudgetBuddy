import SwiftUI

struct ContentView: View {
    @State private var showingAddTransaction = false

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(showingAddTransaction: $showingAddTransaction)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }

            NavigationStack {
                TransactionListView(showingAddTransaction: $showingAddTransaction)
            }
            .tabItem { Label("Transactions", systemImage: "list.bullet.rectangle") }
        }
        .tint(.indigo)
        .sheet(isPresented: $showingAddTransaction) {
            NavigationStack { AddTransactionView() }
        }
    }
}
