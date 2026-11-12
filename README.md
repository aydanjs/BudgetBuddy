# BudgetBuddy

BudgetBuddy is a beginner-friendly, native iPhone budgeting app built with SwiftUI. Its budgeting flow is based on the Household Budget Forecast workbook: plan monthly income and category budgets, record actual transactions, and compare the plan with real spending.

## Version 2 features

- A dashboard with actual income, spending, unallocated cash, planned spending, planned savings, and savings rate
- A monthly budget screen with planned-versus-actual progress for every category
- Categories grouped as Needs, Wants, Giving, and Savings
- Income settings for hourly rate, monthly hours, estimated taxes, tithing, and a savings goal rate
- Local storage for both transactions and budget settings
- Sample transactions and starting category budgets for first launch

## What you need

- A Mac
- Xcode 16 or newer (download it free from the Mac App Store)

You do **not** need a paid Apple Developer account to run this app in the iPhone Simulator.

## Open and run the app

1. Open `BudgetBuddy.xcodeproj` in Xcode.
2. At the top of Xcode, choose an iPhone Simulator, such as **iPhone 16**.
3. Click the triangular **Run** button, or press **Command-R**.
4. The simulator will open and launch BudgetBuddy.

The first launch includes sample transactions and budgets so the screens are not empty. Start on the **Settings** tab to enter an hourly rate, expected monthly hours, estimated tax rate, and tithing rate. Then use **Budget** to set category amounts. Add transactions with the **+** button and swipe left on a transaction to delete it.

## How the project is organized

- `BudgetBuddyApp.swift` starts the app and creates the shared data store.
- `Models/Transaction.swift` describes transactions, budget groups, categories, and settings.
- `Stores/TransactionStore.swift` performs budget calculations and saves data as JSON in the app's private Documents folder.
- `Views/` contains the dashboard, monthly budget, transaction, add-transaction, and settings screens.

## Local storage

No information leaves the device. Transactions and settings are saved in private JSON files belonging to the app. Deleting the app from the simulator or phone also deletes its saved data.

## Run from Terminal (optional)

```bash
xcodebuild -project BudgetBuddy.xcodeproj -scheme BudgetBuddy -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
