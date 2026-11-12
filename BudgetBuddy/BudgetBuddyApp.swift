import SwiftUI

@main
struct BudgetBuddyApp: App {
    @StateObject private var store = TransactionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
