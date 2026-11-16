# BudgetBuddy Security Review Log

Use this log to record the checks required by `SECURITY_POLICY.md`. Do not mark a check complete until it has actually been performed.

## Monthly review template

**Review date:** YYYY-MM-DD  
**Reviewed by:**  
**Systems checked:** GitHub, Render, Plaid, Apple Developer, database

- [ ] Reviewed Render service logs and unexpected API errors.
- [ ] Reviewed Plaid Dashboard alerts and connection issues.
- [ ] Reviewed GitHub security alerts and dependency alerts.
- [ ] Reviewed people with access to GitHub, Render, Plaid, Apple Developer, and the database.
- [ ] Removed access that is no longer needed.
- [ ] Confirmed production secrets are not committed to source control.
- [ ] Recorded security incidents or “none observed.”

**Findings / follow-up work:**

---

## Before-release review template

**Release/build:**  
**Review date:**  
**Reviewed by:**

- [ ] Built and tested the app.
- [ ] Tested the changed feature on a device or simulator.
- [ ] Confirmed Sign in with Apple and affected bank-sync flows work, when applicable.
- [ ] Confirmed no secrets, access tokens, or private keys are included in the build, repository, or release notes.
- [ ] Confirmed the privacy description still matches the app’s behavior.

**Findings / follow-up work:**
