# Turtle Budgeting Data Retention and Deletion Policy

**Owner:** Turtle Budgeting team  
**Effective date:** November 15, 2026  
**Review cadence:** At least annually and before enabling a new financial-data product.

## Purpose

This policy defines how Turtle Budgeting retains and deletes financial information handled by the optional Plaid bank-sync service.

## Data covered

- Apple Sign in account identifier and available contact data.
- Encrypted Plaid access tokens and Plaid Item identifiers.
- Imported Plaid transaction records.
- Recorded consent to connect a bank through Plaid.

## Retention

The service retains this data only while a user’s online bank-sync account is active. The iOS app keeps separately-entered budget and forecast data in its local app storage; that data is not copied to the bank-sync server.

## Deletion

- **Disconnecting a bank:** BudgetBuddy calls Plaid’s Item removal endpoint and removes the matching connection and its server-side transactions.
- **Deleting an online account:** The in-app **Delete Online Account & Bank Data** control calls the server account-deletion endpoint. The service attempts to remove each Plaid Item, then deletes the user record. Database foreign-key rules delete the associated Plaid connection, transaction, and consent records.
- **Local data:** A person can use **Start Over With Guided Setup** to remove local budget information, or delete the app to remove its local storage.

## Verification

The team will test account deletion before each production release that changes bank-sync data handling. Any deletion failure will be investigated promptly, and affected data will be removed as soon as the issue is corrected.

## Logs and backups

The service must not intentionally log bank credentials, access tokens, or full financial records. Operational logs and provider backups are handled under the hosting provider’s retention processes; the team will minimize their use and review them as the production service matures.
