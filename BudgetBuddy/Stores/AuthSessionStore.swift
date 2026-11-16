import AuthenticationServices
import Foundation
import LocalAuthentication

@MainActor
final class AuthSessionStore: ObservableObject {
    @Published private(set) var hasAppleAccount: Bool
    @Published private(set) var isUnlocked = false
    @Published private(set) var displayName: String
    @Published private(set) var authenticationMessage: String?
    @Published private(set) var hasCompletedOnboarding: Bool
    @Published private(set) var serverSessionToken: String?
    @Published private(set) var isServerAuthenticating = false
    @Published private(set) var serverAuthenticationMessage: String?
    @Published private(set) var isDeletingOnlineAccount = false

    private let defaults: UserDefaults
    private let userIDKey = "appleUserID"
    private let displayNameKey = "appleDisplayName"
    private let onboardingKey = "hasCompletedOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let userID = defaults.string(forKey: userIDKey) ?? ""
        hasAppleAccount = !userID.isEmpty
        displayName = defaults.string(forKey: displayNameKey) ?? ""
        hasCompletedOnboarding = defaults.bool(forKey: onboardingKey)
        serverSessionToken = KeychainSession.load()
    }

    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == ASAuthorizationError.errorDomain,
               let code = ASAuthorizationError.Code(rawValue: nsError.code) {
                if code == .canceled {
                    authenticationMessage = "Apple sign-in was canceled. Please tap the button and try again."
                } else if code == .notHandled {
                    authenticationMessage = "Apple could not complete sign-in on this device. Check your Apple Account and internet connection, then try again."
                } else if code == .failed {
                    authenticationMessage = "Apple sign-in failed. Make sure you are signed into iCloud and have two-factor authentication enabled."
                } else if code == .invalidResponse {
                    authenticationMessage = "Apple returned an invalid sign-in response. Please restart the app and try again."
                } else if code == .unknown {
                    authenticationMessage = "Apple sign-in could not be completed. Please restart the app and try again."
                } else {
                    authenticationMessage = "Apple sign-in could not be completed. Please try again."
                }
            } else {
                authenticationMessage = "Apple sign-in failed: \(error.localizedDescription)"
            }
            return

        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                authenticationMessage = "Apple did not return a valid account. Please try again."
                return
            }

            let name = PersonNameComponentsFormatter().string(from: credential.fullName ?? PersonNameComponents())
            if !name.isEmpty {
                displayName = name
                defaults.set(name, forKey: displayNameKey)
            }

            defaults.set(credential.user, forKey: userIDKey)
            hasAppleAccount = true
            authenticationMessage = nil
            isUnlocked = true

            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8) else {
                serverAuthenticationMessage = "Apple signed you in, but the secure bank-sync session could not be created. You can reconnect from Bank Sync."
                return
            }
            Task { await authenticateServer(identityToken: identityToken) }
        }
    }

    func authenticateReturningUser() async {
        guard hasAppleAccount, !isUnlocked else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationMessage = "Turn on Face ID, Touch ID, or a device passcode to unlock the app."
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your financial information"
            )
            if success {
                authenticationMessage = nil
                isUnlocked = true
            }
        } catch {
            authenticationMessage = "Authentication was canceled. Tap Unlock to try again."
        }
    }

    func lock() {
        guard hasAppleAccount else { return }
        authenticationMessage = nil
        isUnlocked = false
    }

    func completeOnboarding() {
        defaults.set(true, forKey: onboardingKey)
        hasCompletedOnboarding = true
    }

    /// Returns the signed-in person to the guided setup without signing them out
    /// or changing their secure bank connections.
    func restartOnboarding() {
        defaults.set(false, forKey: onboardingKey)
        hasCompletedOnboarding = false
    }

    func signOut() {
        KeychainSession.delete()
        defaults.removeObject(forKey: userIDKey)
        defaults.removeObject(forKey: displayNameKey)
        displayName = ""
        authenticationMessage = nil
        serverAuthenticationMessage = nil
        serverSessionToken = nil
        hasAppleAccount = false
        isUnlocked = false
    }

    func clearExpiredServerSession() {
        KeychainSession.delete()
        serverSessionToken = nil
        serverAuthenticationMessage = "Your secure bank-sync session expired. Continue with Apple once to reconnect it."
    }

    /// Removes only the online account used for bank sync. Local budgets stay on the iPhone
    /// until the person chooses the separate local reset action.
    func deleteOnlineAccount() async -> Bool {
        guard let serverSessionToken else {
            serverAuthenticationMessage = "Sign in with Apple before deleting your online account."
            return false
        }

        isDeletingOnlineAccount = true
        serverAuthenticationMessage = nil
        defer { isDeletingOnlineAccount = false }

        do {
            var request = URLRequest(url: BudgetBuddyAPI.baseURL.appendingPathComponent("/api/account"))
            request.httpMethod = "DELETE"
            request.setValue("Bearer \(serverSessionToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "Turtle Budgeting could not delete your online account."
                throw PlaidLocalError(message: message, statusCode: (response as? HTTPURLResponse)?.statusCode)
            }
            signOut()
            return true
        } catch {
            serverAuthenticationMessage = error.localizedDescription
            return false
        }
    }

    private func authenticateServer(identityToken: String) async {
        isServerAuthenticating = true
        serverAuthenticationMessage = nil
        defer { isServerAuthenticating = false }

        do {
            var request = URLRequest(url: BudgetBuddyAPI.baseURL.appendingPathComponent("/api/auth/apple"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["identity_token": identityToken])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                let message = (try? JSONDecoder().decode(ServerError.self, from: data).error) ?? "Turtle Budgeting could not create a secure bank-sync session."
                throw PlaidLocalError(message: message)
            }
            let token = try JSONDecoder.plaid.decode(SessionResponse.self, from: data).sessionToken
            try KeychainSession.save(token)
            serverSessionToken = token
            serverAuthenticationMessage = nil
        } catch {
            serverAuthenticationMessage = error.localizedDescription
        }
    }
}
