import Foundation
import OSLog

public enum AppLog {
    public static let refresh = Logger(subsystem: "com.jonathan.QuotaBar", category: "refresh")
    public static let provider = Logger(subsystem: "com.jonathan.QuotaBar", category: "provider")
    public static let cache = Logger(subsystem: "com.jonathan.QuotaBar", category: "cache")
}
