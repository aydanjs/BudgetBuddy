# BudgetBuddy

BudgetBuddy is a beginner-friendly, native iPhone budgeting app built with SwiftUI. It shows a monthly summary, lists transactions, lets you add income or expenses, and stores everything locally on the phone.

## What you need

- A Mac
- Xcode 16 or newer (download it free from the Mac App Store)

You do **not** need a paid Apple Developer account to run this app in the iPhone Simulator.

## Open and run the app

1. Open `BudgetBuddy.xcodeproj` in Xcode.
2. At the top of Xcode, choose an iPhone Simulator, such as **iPhone 16**.
3. Click the triangular **Run** button, or press **Command-R**.
4. The simulator will open and launch BudgetBuddy.

The first launch includes sample transactions so the screens are not empty. Add a transaction with the **+** button. Swipe left on a transaction in the full list to delete it.

## How the project is organized

- `BudgetBuddyApp.swift` starts the app and creates the shared data store.
- `Models/Transaction.swift` describes a transaction and the available categories.
- `Stores/TransactionStore.swift` loads and saves transactions as JSON in the app's private Documents folder.
- `Views/` contains the dashboard, transaction list, and add-transaction screen.

## Local storage

No information leaves the device. Transactions are saved in a private `transactions.json` file belonging to the app. Deleting the app from the simulator or phone also deletes its saved data.

## Run from Terminal (optional)

```bash
xcodebuild -project BudgetBuddy.xcodeproj -scheme BudgetBuddy -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
