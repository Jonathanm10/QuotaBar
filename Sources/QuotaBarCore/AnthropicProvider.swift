import Foundation
#if os(macOS)
import Security
#endif

public struct AnthropicProvider: UsageProvider {
    public let providerID: ProviderID = .anthropic
    private static let keychainService = "Claude Code-credentials"
    private static let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshEndpoint = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    public init() {}

    public func fetchSnapshot(now: Date) async throws -> ProviderSnapshot {
        var credentials = try Self.loadCredentials()
        if credentials.isExpired {
            credentials = try await Self.refresh(credentials)
            try Self.saveCredentials(credentials)
        }

        do {
            return try await Self.fetchSnapshot(credentials: credentials, now: now)
        } catch let error as AnthropicProviderError where error.isUnauthorized {
            credentials = try await Self.refresh(credentials)
            try Self.saveCredentials(credentials)
            return try await Self.fetchSnapshot(credentials: credentials, now: now)
        }
    }

    private static func loadCredentials() throws -> ClaudeOAuthCredentials {
        let output = try runSecurityCommand(arguments: ["find-generic-password", "-s", keychainService, "-w"])
        let decoded = try JSONDecoder().decode(ClaudeCredentialEnvelope.self, from: output)
        return decoded.claudeAiOauth
    }

    private static func refresh(_ credentials: ClaudeOAuthCredentials) async throws -> ClaudeOAuthCredentials {
        guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
            throw AnthropicProviderError.refreshFailed
        }

        var request = URLRequest(url: refreshEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = URLComponents(string: "https://unused.invalid")!
            .withQueryItems([
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken),
                URLQueryItem(name: "client_id", value: clientID),
            ])
            .percentEncodedQuery?
            .data(using: .utf8)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AnthropicProviderError.refreshFailed
        }

        let refreshed = try JSONDecoder().decode(ClaudeRefreshResponse.self, from: data)
        return ClaudeOAuthCredentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken ?? credentials.refreshToken,
            expiresAt: refreshed.expiresAtDate,
            scopes: refreshed.scopes ?? credentials.scopes,
            rateLimitTier: refreshed.rateLimitTier ?? credentials.rateLimitTier
        )
    }

    private static func saveCredentials(_ credentials: ClaudeOAuthCredentials) throws {
        let payload = ClaudeCredentialEnvelope(claudeAiOauth: credentials)
        let data = try JSONEncoder().encode(payload)
        #if os(macOS)
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
            throw AnthropicProviderError.keychainWriteFailed("OSStatus \(updateStatus)")
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw AnthropicProviderError.keychainWriteFailed("OSStatus \(addStatus)")
        }
        #else
        throw AnthropicProviderError.keychainWriteFailed("Keychain writes require macOS Security.framework.")
        #endif
    }

    private static func fetchSnapshot(credentials: ClaudeOAuthCredentials, now: Date) async throws -> ProviderSnapshot {
        var request = URLRequest(url: usageEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.112", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AnthropicProviderError.invalidResponse
        }
        guard http.statusCode != 401 else {
            throw AnthropicProviderError.unauthorized
        }
        guard 200 ..< 300 ~= http.statusCode else {
            throw AnthropicProviderError.httpError(http.statusCode)
        }

        let usage = try JSONDecoder().decode(AnthropicUsageResponse.self, from: data)
        guard let fiveHour = usage.fiveHour, let fiveHourUtilization = fiveHour.utilization else {
            throw AnthropicProviderError.invalidResponse
        }

        let shortWindow = UsageWindow(
            label: "5h",
            usedPercent: fiveHourUtilization,
            sourceWindowMinutes: 5 * 60,
            resetsAt: fiveHour.resetsAtDate,
            source: .oauth
        )
        let weekly = usage.sevenDay.flatMap { weekly -> UsageWindow? in
            guard let utilization = weekly.utilization else { return nil }
            return UsageWindow(
                label: "Weekly",
                usedPercent: utilization,
                sourceWindowMinutes: 7 * 24 * 60,
                resetsAt: weekly.resetsAtDate,
                source: .oauth
            )
        }

        return ProviderSnapshot(
            provider: .anthropic,
            daily: shortWindow,
            weekly: weekly,
            reserve: nil,
            source: "oauth",
            fetchedAt: now
        )
    }

    private static func runSecurityCommand(arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown error"
            throw AnthropicProviderError.keychainReadFailed(error)
        }

        return stdout.fileHandleForReading.readDataToEndOfFile()
    }
}

public struct ClaudeOAuthCredentials: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let scopes: [String]
    public let rateLimitTier: String?

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

public enum AnthropicProviderError: LocalizedError {
    case keychainReadFailed(String)
    case keychainWriteFailed(String)
    case invalidResponse
    case unauthorized
    case refreshFailed
    case httpError(Int)

    public var isUnauthorized: Bool {
        if case .unauthorized = self { return true }
        return false
    }

    public var errorDescription: String? {
        switch self {
        case let .keychainReadFailed(message): "Anthropic keychain read failed: \(message)"
        case let .keychainWriteFailed(message): "Anthropic keychain write failed: \(message)"
        case .invalidResponse: "Anthropic usage response was invalid."
        case .unauthorized: "Anthropic usage request was unauthorized."
        case .refreshFailed: "Anthropic token refresh failed."
        case let .httpError(code): "Anthropic usage request failed with HTTP \(code)."
        }
    }
}

public struct AnthropicUsageResponse: Codable, Sendable {
    public let fiveHour: UsageWindowPayload?
    public let sevenDay: UsageWindowPayload?
    public let extraUsage: ExtraUsage?

    public struct UsageWindowPayload: Codable, Sendable {
        public let utilization: Double?
        public let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        public var resetsAtDate: Date? {
            resetsAt.flatMap { ISO8601DateFormatter.flexible().date(from: $0) }
        }
    }

    public struct ExtraUsage: Codable, Sendable {
        public let isEnabled: Bool?
        public let monthlyLimit: Double?
        public let usedCredits: Double?
        public let currency: String?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case currency
        }
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case extraUsage = "extra_usage"
    }
}

private struct ClaudeCredentialEnvelope: Codable {
    let claudeAiOauth: ClaudeOAuthCredentials
}

private struct ClaudeRefreshResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let scope: String?
    let rateLimitTier: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
        case rateLimitTier = "rate_limit_tier"
    }

    var expiresAtDate: Date? {
        guard let expiresIn else { return nil }
        return Date().addingTimeInterval(expiresIn)
    }

    var scopes: [String]? {
        scope?
            .split(separator: " ")
            .map(String.init)
    }
}

private extension URLComponents {
    func withQueryItems(_ items: [URLQueryItem]) -> URLComponents {
        var copy = self
        copy.queryItems = items
        return copy
    }
}

private extension ISO8601DateFormatter {
    static func flexible() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
