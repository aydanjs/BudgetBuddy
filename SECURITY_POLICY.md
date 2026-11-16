# BudgetBuddy Information Security Policy

**Owner:** BudgetBuddy founder / security owner  
**Effective date:** November 15, 2026  
**Review cadence:** Every 12 months and before a material change to bank connectivity, authentication, hosting, or data handling.

## 1. Purpose and scope

This policy explains how BudgetBuddy identifies, reduces, and monitors information-security risks while providing a personal budgeting app and optional bank connectivity through Plaid.

It applies to the iOS app, the BudgetBuddy API, its PostgreSQL database, source code, deployment environment, and any person with access to those systems.

## 2. Security owner and responsibilities

The BudgetBuddy founder is the security owner. The security owner must:

- review this policy on the cadence above;
- keep access to GitHub, Render, Plaid, Apple Developer, and database services limited to people who need it;
- remove access promptly when a collaborator no longer needs it;
- review security alerts and reported incidents;
- approve production changes that affect customer data or bank connectivity.

## 3. Data handling

BudgetBuddy minimizes the financial data it handles.

- Budget data entered manually is stored in the app's private local storage on the user's iPhone.
- A user signs in to the bank-sync service with Sign in with Apple.
- Bank usernames and passwords are entered only in Plaid Link and are never provided to or stored by BudgetBuddy.
- The hosted API stores Plaid access tokens only in encrypted form using AES-256-GCM.
- The service stores only the data needed for connected-bank features, such as Plaid Item records and imported transactions.
- API session tokens are stored on the iPhone in the Keychain.

BudgetBuddy does not sell bank data or use it for advertising.

## 4. Access control

- Each administrator uses their own account; shared passwords are not permitted.
- Multi-factor authentication must be enabled where a provider offers it, including GitHub, Render, Plaid, and Apple Developer.
- Production secrets are stored in the hosting provider's protected environment settings, never in source code, screenshots, chat messages, or Git commits.
- Access tokens and credentials must be rotated immediately if they may have been exposed.
- Users can disconnect a bank connection and request deletion of their online account and connected-bank data through the app.

## 5. Secure development and change management

- Code changes are kept in version control and reviewed by at least the developer making the change before release.
- The iOS app must be built and tested before each TestFlight or App Store release.
- Dependencies, Xcode, and the server runtime are kept reasonably current. Critical security updates are prioritized.
- A production change affecting authentication, encryption, Plaid, database access, or permissions requires a documented check that the change works and does not expose secrets.
- Test, sandbox, and production credentials remain separate.

## 6. Risk identification and monitoring

The security owner performs the following operational checks:

| Frequency | Required check |
| --- | --- |
| Before production release | Confirm no secrets are committed; test Sign in with Apple, bank connection, account deletion, and the affected feature. |
| Monthly | Review Render service logs/errors, Plaid Dashboard alerts, GitHub security alerts, active collaborators, and unexpected API failures. |
| Quarterly | Review who has access to GitHub, Render, Plaid, Apple Developer, and the database. Remove unnecessary access and review environment variables. |
| Annually | Review this policy, vendor security documentation, dependencies, data collected, and incident history. |

Security events include suspected unauthorized access, accidental disclosure of a secret, unusual API activity, failed authentication patterns, or data deletion/loss.

## 7. Incident response

If a security event is suspected, the security owner will:

1. Contain it: disable affected credentials, revoke access, or temporarily disable bank sync if needed.
2. Preserve relevant information: record the date, systems involved, actions taken, and available logs.
3. Investigate the scope: determine what data or accounts may have been affected.
4. Remediate: rotate secrets, patch the issue, remove unauthorized access, and verify the fix.
5. Notify affected people and service providers when required by applicable law or contractual terms.
6. Document lessons learned and update this policy or procedures.

## 8. Third-party services

BudgetBuddy relies on third parties for specific functions:

- **Apple:** app distribution, Sign in with Apple, and TestFlight.
- **Plaid:** financial-institution connection and permitted financial data access.
- **Render:** API and database hosting.
- **GitHub:** source-code hosting and collaboration.

Before adding a vendor that can access customer or financial data, the security owner must review its security documentation, data practices, access controls, and whether the data sharing is necessary.

## 9. Exceptions

Any exception to this policy must be written down by the security owner with the reason, duration, compensating safeguards, and approval date.

## 10. Policy acknowledgement

Anyone with administrator or production access must read and follow this policy. This policy is a practical operating document, not a certification and not legal advice.
