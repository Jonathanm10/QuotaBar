import Foundation
#if os(macOS)
import Security
#endif

public struct OpenAIProvider: UsageProvider {
    public let providerID: ProviderID = .openAI

    public init() {}

    public func fetchSnapshot(now: Date) async throws -> ProviderSnapshot {
        var credentials = try OpenAICredentialsStore.load()
        if credentials.shouldRefreshProactively {
            credentials = try await Self.refreshOrRecoverFromCodexAuthFile(credentials)
        }

        do {
            return try await Self.fetchSnapshot(credentials: credentials, now: now)
        } catch let error as OpenAIProviderError where error.isUnauthorized {
            guard credentials.refreshToken?.isEmpty == false else { throw error }
            let refreshed = try await Self.refreshOrRecoverFromCodexAuthFile(credentials)
            return try await Self.fetchSnapshot(credentials: refreshed, now: now)
        }
    }

    private static func refreshOrRecoverFromCodexAuthFile(_ credentials: OpenAICredentials) async throws -> OpenAICredentials {
        do {
            let refreshed = try await OpenAICredentialsStore.refresh(credentials)
            try OpenAICredentialsStore.saveRefreshed(refreshed)
            return refreshed
        } catch {
            return try OpenAICredentialsStore.recoverFromCodexAuthFile(after: error, staleCredentials: credentials)
        }
    }

    private static func fetchSnapshot(credentials: OpenAICredentials, now: Date) async throws -> ProviderSnapshot {
        let response = try await OpenAIUsageFetcher.fetchUsage(credentials: credentials)
        let shortWindow = response.rateLimit?.primaryWindow.map {
            UsageWindow(
                label: "5h",
                usedPercent: Double($0.usedPercent),
                sourceWindowMinutes: $0.limitWindowSeconds / 60,
                resetsAt: Date(timeIntervalSince1970: TimeInterval($0.resetAt)),
                source: .oauth
            )
        }
        let weekly = response.rateLimit?.secondaryWindow.map {
            UsageWindow(
                label: "Weekly",
                usedPercent: Double($0.usedPercent),
                sourceWindowMinutes: $0.limitWindowSeconds / 60,
                resetsAt: Date(timeIntervalSince1970: TimeInterval($0.resetAt)),
                source: .oauth
            )
        }

        return ProviderSnapshot(
            provider: .openAI,
            daily: shortWindow,
            weekly: weekly,
            reserve: nil,
            source: "oauth",
            fetchedAt: now
        )
    }
}

public struct OpenAICredentials: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let accountID: String?
    public let idToken: String?
    public let lastRefresh: Date?

    public var shouldRefreshProactively: Bool {
        guard let lastRefresh else { return refreshToken?.isEmpty == false }
        return Date().timeIntervalSince(lastRefresh) > 7 * 24 * 60 * 60
    }
}

public enum OpenAICredentialsStore {
    private static let authPath = URL(filePath: NSHomeDirectory())
        .appending(path: ".codex")
        .appending(path: "auth.json")
    private static let refreshEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let keychainService = "QuotaBar.OpenAIOAuth"

    public static func load() throws -> OpenAICredentials {
        do {
            if let keychainCredentials = try self.loadFromKeychain() {
                return keychainCredentials
            }
        } catch {
            AppLog.provider.error("OpenAI QuotaBar keychain credentials were unusable; falling back to Codex auth file: \(error.localizedDescription, privacy: .public)")
        }

        return try self.loadFromCodexAuthFile()
    }

    public static func recoverFromCodexAuthFile(after refreshError: any Error, staleCredentials: OpenAICredentials) throws -> OpenAICredentials {
        let codexCredentials = try self.loadFromCodexAuthFile()
        guard !self.hasSameTokenSet(codexCredentials, staleCredentials) else {
            throw refreshError
        }
        do {
            try self.saveRefreshed(codexCredentials)
        } catch {
            AppLog.provider.error("OpenAI Codex auth recovery could not update QuotaBar keychain: \(error.localizedDescription, privacy: .public)")
        }
        return codexCredentials
    }

    static func loadFromCodexAuthFile() throws -> OpenAICredentials {
        let data = try Data(contentsOf: authPath)
        let decoded = try JSONDecoder.iso8601.decode(OpenAIAuthFile.self, from: data)

        if let apiKey = decoded.OPENAI_API_KEY?.trimmed, !apiKey.isEmpty {
            _ = apiKey
            throw OpenAIProviderError.apiKeyUnsupported
        }

        guard let tokens = decoded.tokens, let accessToken = tokens.accessToken?.trimmed, !accessToken.isEmpty else {
            throw OpenAIProviderError.credentialsMissing
        }

        return OpenAICredentials(
            accessToken: accessToken,
            refreshToken: tokens.refreshToken?.trimmed,
            accountID: tokens.accountID?.trimmed,
            idToken: tokens.idToken?.trimmed,
            lastRefresh: decoded.lastRefresh
        )
    }

    private static func hasSameTokenSet(_ lhs: OpenAICredentials, _ rhs: OpenAICredentials) -> Bool {
        lhs.accessToken == rhs.accessToken
            && lhs.refreshToken == rhs.refreshToken
            && lhs.accountID == rhs.accountID
            && lhs.idToken == rhs.idToken
    }

    public static func saveRefreshed(_ credentials: OpenAICredentials) throws {
        #if os(macOS)
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw OpenAIProviderError.keychainWriteFailed(updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw OpenAIProviderError.keychainWriteFailed(addStatus)
        }
        #endif
    }

    public static func refresh(_ credentials: OpenAICredentials) async throws -> OpenAICredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else { return credentials }

        let body = RefreshRequest(
            clientID: clientID,
            grantType: "refresh_token",
            refreshToken: refreshToken,
            scope: "openid profile email"
        )

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIProviderError.invalidResponse
        }
        guard http.statusCode == 200 else {
            throw OpenAIProviderError.refreshFailed(
                statusCode: http.statusCode,
                body: openAIResponseBodySnippet(data)
            )
        }

        let refreshed: RefreshResponse
        do {
            refreshed = try JSONDecoder().decode(RefreshResponse.self, from: data)
        } catch {
            throw OpenAIProviderError.refreshDecodeFailed(
                reason: error.localizedDescription,
                body: openAIResponseBodySnippet(data)
            )
        }
        return OpenAICredentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? credentials.refreshToken,
            accountID: credentials.accountID,
            idToken: refreshed.idToken ?? credentials.idToken,
            lastRefresh: Date()
        )
    }

    private static func loadFromKeychain() throws -> OpenAICredentials? {
        #if os(macOS)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return try JSONDecoder.iso8601.decode(OpenAICredentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw OpenAIProviderError.keychainReadFailed(status)
        }
        #else
        return nil
        #endif
    }
}

public enum OpenAIUsageFetcher {
    public static func fetchUsage(credentials: OpenAICredentials) async throws -> OpenAIUsageResponse {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/usage") else {
            throw OpenAIProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaBar", forHTTPHeaderField: "User-Agent")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIProviderError.invalidResponse
        }
        guard http.statusCode != 401 else {
            throw OpenAIProviderError.unauthorized(body: openAIResponseBodySnippet(data))
        }
        guard 200 ..< 300 ~= http.statusCode else {
            throw OpenAIProviderError.httpError(
                statusCode: http.statusCode,
                body: openAIResponseBodySnippet(data)
            )
        }

        do {
            return try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)
        } catch {
            throw OpenAIProviderError.usageDecodeFailed(
                reason: error.localizedDescription,
                body: openAIResponseBodySnippet(data)
            )
        }
    }
}

public enum OpenAIProviderError: LocalizedError {
    case credentialsMissing
    case apiKeyUnsupported
    case refreshFailed(statusCode: Int, body: String)
    case refreshDecodeFailed(reason: String, body: String)
    case usageDecodeFailed(reason: String, body: String)
    case invalidResponse
    case unauthorized(body: String)
    case httpError(statusCode: Int, body: String)
    case keychainReadFailed(OSStatus)
    case keychainWriteFailed(OSStatus)

    public var isUnauthorized: Bool {
        switch self {
        case .unauthorized: true
        default: false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .credentialsMissing: "OpenAI credentials missing. Run codex login."
        case .apiKeyUnsupported: "OPENAI_API_KEY auth is not supported for ChatGPT usage polling; use codex OAuth login."
        case let .refreshFailed(statusCode, body):
            if body.isEmpty {
                "OpenAI token refresh failed with HTTP \(statusCode)."
            } else {
                "OpenAI token refresh failed with HTTP \(statusCode): \(body)"
            }
        case let .refreshDecodeFailed(reason, body):
            if body.isEmpty {
                "OpenAI token refresh response could not be decoded: \(reason)"
            } else {
                "OpenAI token refresh response could not be decoded: \(reason). Body: \(body)"
            }
        case let .usageDecodeFailed(reason, body):
            if body.isEmpty {
                "OpenAI usage response could not be decoded: \(reason)"
            } else {
                "OpenAI usage response could not be decoded: \(reason). Body: \(body)"
            }
        case .invalidResponse: "OpenAI usage response was invalid."
        case let .unauthorized(body):
            if body.isEmpty {
                "OpenAI usage request was unauthorized."
            } else {
                "OpenAI usage request was unauthorized: \(body)"
            }
        case let .httpError(statusCode, body):
            if body.isEmpty {
                "OpenAI usage request failed with HTTP \(statusCode)."
            } else {
                "OpenAI usage request failed with HTTP \(statusCode): \(body)"
            }
        case let .keychainReadFailed(status): "OpenAI keychain read failed with OSStatus \(status)."
        case let .keychainWriteFailed(status): "OpenAI keychain write failed with OSStatus \(status)."
        }
    }
}

private func openAIResponseBodySnippet(_ data: Data) -> String {
    guard !data.isEmpty else { return "" }
    let raw = String(data: data, encoding: .utf8) ?? data.base64EncodedString()
    let singleLine = raw
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\r", with: " ")
        .trimmed
    guard singleLine.count > 1_000 else { return singleLine }
    return "\(singleLine.prefix(1_000))..."
}

public struct OpenAIUsageResponse: Codable, Sendable {
    public let planType: String?
    public let rateLimit: RateLimit?
    public let credits: Credits?

    public struct RateLimit: Codable, Sendable {
        public let primaryWindow: Window?
        public let secondaryWindow: Window?

        public struct Window: Codable, Sendable {
            public let usedPercent: Double
            public let limitWindowSeconds: Int
            public let resetAt: Int

            enum CodingKeys: String, CodingKey {
                case usedPercent = "used_percent"
                case limitWindowSeconds = "limit_window_seconds"
                case resetAt = "reset_at"
            }
        }

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    public struct Credits: Codable, Sendable {
        public let balance: String?
    }

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }
}

struct OpenAIAuthFile: Codable {
    let authMode: String?
    let lastRefresh: Date?
    let OPENAI_API_KEY: String?
    let tokens: Tokens?

    struct Tokens: Codable {
        let accessToken: String?
        let accountID: String?
        let idToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountID = "account_id"
            case idToken = "id_token"
            case refreshToken = "refresh_token"
        }
    }

    enum CodingKeys: String, CodingKey {
        case authMode = "auth_mode"
        case lastRefresh = "last_refresh"
        case OPENAI_API_KEY
        case tokens
    }
}

private struct RefreshRequest: Codable {
    let clientID: String
    let grantType: String
    let refreshToken: String
    let scope: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
        case grantType = "grant_type"
        case refreshToken = "refresh_token"
        case scope
    }
}

private struct RefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
    }
}

private extension String {
    var trimmed: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
