# BudgetBuddy

BudgetBuddy is a beginner-friendly native iPhone budgeting app built with SwiftUI. It combines monthly budgeting, actual spending, long-term forecasts, purchase planning, debt payoff estimates, and net-worth tracking.

## Current features

- Dashboard with monthly actuals, expected comparisons, category progress, and net-worth history
- Monthly budget with planned-versus-actual category progress
- Add, edit, filter, and delete transactions
- Savings and stock forecasts for 1-year and 5-year scenarios
- Big-purchase planning and debt-payoff estimates
- Local storage for transactions, settings, debts, and net-worth history
- Secure Plaid bank connections (hosted setup required)

## What you need

- A Mac
- Xcode 16 or newer
- An active Apple Developer Program membership for TestFlight or App Store distribution

A paid membership is not needed to run BudgetBuddy in the iPhone Simulator.

## Open and run the app

1. Open `BudgetBuddy.xcodeproj` in Xcode.
2. Choose an iPhone Simulator at the top of Xcode.
3. Click the triangular **Run** button or press **Command-R**.
4. The simulator will open and launch BudgetBuddy.

The first launch includes sample transactions and budgets. Open **Plan → Settings** to enter income and forecast assumptions, use **Budget** to adjust category amounts, and use the **+** button to add a transaction.

## Project organization

- `BudgetBuddyApp.swift` starts the app and creates the shared data store.
- `Models/Transaction.swift` contains the financial models and settings.
- `Stores/TransactionStore.swift` calculates totals and saves local JSON data.
- `Views/` contains the dashboard, budget, transactions, forecasts, debt planner, settings, and Plaid Sandbox interface.

## Privacy and storage

Budgets, forecasts, and manually entered transactions are stored in the app's private storage. When bank sync is enabled, the hosted API stores an encrypted Plaid access token and synced transaction records for the signed-in user. Bank credentials are entered only in Plaid Link and are never provided to BudgetBuddy.

## Plaid hosted setup

The `server/` folder contains the multi-user API used by the iPhone app. It verifies Sign in with Apple, encrypts Plaid access tokens with AES-256-GCM, persists Plaid Items and transactions in PostgreSQL, handles transaction webhooks, and supports disconnecting banks and deleting an account.

Before requesting Plaid Production access, deploy and test this server using Plaid Sandbox:

1. Copy `server/.env.example` to `server/.env`.
2. Add the Sandbox credentials and local PostgreSQL connection. Generate separate strong values for `TOKEN_ENCRYPTION_KEY` and `SESSION_SECRET`. Never commit or share this file.
3. Run `server/schema.sql` against the PostgreSQL database.
4. Install Node.js 20.6 or newer and install dependencies with `pnpm install`.
5. Start the server:

```bash
cd server
npm start
```

6. Run BudgetBuddy in the iPhone Simulator.
7. Open **Plan → Settings → Connect bank accounts** and use **Developer Sign In**.
8. Connect a Plaid test institution and import the desired fake transactions.

For a hosted deployment, `render.yaml` describes the API and PostgreSQL database. Configure the API URL in the app, add an HTTPS Plaid redirect URI and webhook URL, and keep the Plaid secret only in the host's private environment settings.

## Prepare a TestFlight build

BudgetBuddy currently uses:

- Bundle identifier: `com.aydanjs.BudgetBuddyFinance`
- Version: `1.0`
- Build: `1`

To create an archive:

1. Open `BudgetBuddy.xcodeproj` in Xcode.
2. Select the **BudgetBuddy** project and then the **BudgetBuddy** target.
3. Open **Signing & Capabilities**.
4. Enable **Automatically manage signing** and select your Apple Developer team.
5. Choose **Any iOS Device (arm64)** as the run destination.
6. Select **Product → Archive**.
7. When Organizer opens, validate the archive.
8. Only when ready, select **Distribute App → App Store Connect → Upload**.

Uploading requires a matching app record in App Store Connect and completed privacy information. Creating that record and uploading are intentionally separate from the local project preparation.

## Terminal build (optional)

```bash
xcodebuild -project BudgetBuddy.xcodeproj -scheme BudgetBuddy -sdk iphonesimulator -configuration Debug build CODE_SIGNING_ALLOWED=NO
```
