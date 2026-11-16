import SwiftUI

let currencyCode = Locale.current.currency?.identifier ?? "USD"

/// Public beta features. Keep the Plaid implementation in the project so it can
/// return later without exposing bank connection controls in the manual beta.
enum AppFeatures {
    static let bankSyncEnabled = false
}

struct ContentView: View {
    @EnvironmentObject private var auth: AuthSessionStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingAddTransaction = false
    @State private var selectedTab: AppTab = .dashboard
    @State private var transactionMonth: Date?

    var body: some View {
        Group {
            if auth.isUnlocked {
                if auth.hasCompletedOnboarding {
                    appTabs
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    OnboardingView()
                        .transition(.opacity)
                }
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isUnlocked)
        .animation(.easeInOut(duration: 0.2), value: auth.hasCompletedOnboarding)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                auth.lock()
            }
        }
    }

    private var appTabs: some View {
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
    /// Logo blue: #429CF5
    static let budgetBuddyBlue = Color(red: 66 / 255, green: 156 / 255, blue: 245 / 255)
    /// A deeper companion blue for gradients and readable contrast.
    static let budgetBuddyNavy = Color(red: 25 / 255, green: 91 / 255, blue: 157 / 255)
    /// Logo detail green: #009D55
    static let budgetBuddyTeal = Color(red: 0 / 255, green: 157 / 255, blue: 85 / 255)
    static let budgetBuddyGreen = Color(red: 0 / 255, green: 157 / 255, blue: 85 / 255)
    /// Logo turtle green: #55F044
    static let budgetBuddyBrightGreen = Color(red: 85 / 255, green: 240 / 255, blue: 68 / 255)
}
