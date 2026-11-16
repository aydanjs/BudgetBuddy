# Turtle Budgeting Access Control Policy

**Owner:** Turtle Budgeting founder / security owner  
**Effective date:** November 15, 2026  
**Review cadence:** Quarterly and when a person joins or leaves the project.

## 1. Purpose

This policy limits access to Turtle Budgeting production systems and sensitive consumer financial data to authorized people who need that access to operate and maintain the service.

## 2. Scope

This policy applies to the Turtle Budgeting iOS app, source code, GitHub repository, Render deployment, PostgreSQL database, Plaid Dashboard, Apple Developer account, and associated production secrets.

## 3. Access principles

- Each administrator must use an individual account. Shared administrator accounts and shared passwords are not allowed.
- Access is granted only when needed for a defined project responsibility and should use the lowest privilege that allows the work to be completed.
- Multi-factor authentication must be enabled wherever it is available.
- Production access is limited to approved administrators. Collaborators receive only the access required for their assigned work.
- Access is removed promptly when a collaborator no longer needs it.

## 4. Production systems and controls

| System | Access control |
| --- | --- |
| GitHub | Individual GitHub accounts and repository roles; access reviewed quarterly. |
| Render and PostgreSQL | Individual provider accounts; production environment variables are restricted to authorized administrators. |
| Plaid Dashboard | Individual Plaid accounts; production credentials are never placed in source code. |
| Apple Developer and App Store Connect | Individual Apple IDs and assigned roles. |
| iOS app | Users authenticate for connected-bank features using Sign in with Apple. API session tokens are stored in the iPhone Keychain. |

## 5. Sensitive data and secrets

- Bank credentials are entered only in Plaid Link. Turtle Budgeting does not receive or store bank usernames or passwords.
- Plaid access tokens are stored by the hosted API only in encrypted form using AES-256-GCM.
- Secrets, including Plaid credentials, database connection strings, encryption keys, and session secrets, are stored only in protected hosting-provider environment settings.
- Secrets must not be committed to Git, pasted into public issues, screenshots, or shared chat messages.
- A suspected secret exposure requires immediate rotation of the affected credential and review of related access.

## 6. Access requests, changes, and removal

1. The security owner approves access before it is granted.
2. The security owner records the person, system, role, purpose, and approval date in the access-review record.
3. When responsibilities change or end, unnecessary access is removed promptly.
4. The security owner reviews production access at least quarterly and documents the result.

## 7. Reviews and monitoring

The security owner uses `SECURITY_REVIEW_LOG.md` to record quarterly access reviews and monthly security checks. Reviews include active administrators, provider alerts, unexpected errors, and confirmation that production secrets are not stored in source control.

## 8. Exceptions

Exceptions must be approved in writing by the security owner and include a reason, expiration date, and compensating safeguards.

## 9. Acknowledgement

Anyone with access to Turtle Budgeting production systems must read and follow this policy.
