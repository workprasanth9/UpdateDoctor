import Foundation
import UpdateDoctorKit

/// Overall state shown by the menu bar icon.
public enum MenuHealth: String, Equatable {
    case healthy, atRisk, blocked, unknown

    public init(verdict: String) {
        switch verdict {
        case "HEALTHY": self = .healthy
        case "AT_RISK": self = .atRisk
        case "BLOCKED": self = .blocked
        default: self = .unknown
        }
    }

    public var title: String {
        switch self {
        case .healthy: return "Healthy"
        case .atRisk: return "At risk"
        case .blocked: return "Blocked"
        case .unknown: return "Not checked yet"
        }
    }

    /// Icon color name: green, yellow, red, or gray.
    public var colorName: String {
        switch self {
        case .healthy: return "green"
        case .atRisk: return "yellow"
        case .blocked: return "red"
        case .unknown: return "gray"
        }
    }
}

/// One line in the dropdown, derived from a CheckResult.
public struct CheckRow: Equatable {
    public let id: String
    public let title: String
    public let statusLabel: String
    public let detail: String
    public let fix: String?
    public let needsAdmin: Bool
    public let status: CheckStatus
}

public enum StatusMapping {
    /// True when a check was skipped only because the process was not root.
    public static func needsAdmin(_ check: CheckResult) -> Bool {
        check.status == .skipped && check.detail.lowercased().contains("needs root")
    }

    public static func label(_ check: CheckResult) -> String {
        switch check.status {
        case .pass: return "OK"
        case .info: return "Info"
        case .warn: return "Warning"
        case .fail: return "Failed"
        case .skipped: return needsAdmin(check) ? "Needs admin" : "Skipped"
        }
    }

    public static func row(_ check: CheckResult) -> CheckRow {
        let admin = needsAdmin(check)
        let detail = admin ? "Needs admin. Use Run full check (admin) to include it." : check.detail
        return CheckRow(id: check.id, title: check.title, statusLabel: label(check),
                        detail: detail, fix: check.fix, needsAdmin: admin, status: check.status)
    }

    public static func rows(_ report: Report) -> [CheckRow] { report.checks.map(row) }
}

/// AppleScript that runs the bundled CLI as root through the standard macOS
/// administrator prompt. The CLI exits 2 when BLOCKED, so `|| true` keeps the JSON.
public enum AdminRunner {
    public static func appleScript(cliPath: String) -> String {
        let escaped = cliPath.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script (quoted form of \"\(escaped)\") & \" doctor --json || true\" "
            + "with prompt \"UpdateDoctor needs administrator access to run the full check, including the Bootstrap Token check. It only reads.\" "
            + "with administrator privileges"
    }

    public static func decode(_ data: Data) throws -> Report {
        try JSONDecoder().decode(Report.self, from: data)
    }
}

/// State behind the menu. UI code reads it, it never runs checks itself.
public final class MenuViewModel {
    public private(set) var report: Report?
    public private(set) var lastChecked: Date?
    public private(set) var isChecking = false
    public private(set) var lastError: String?
    public private(set) var lastRunWasAdmin = false

    public init() {}

    public var health: MenuHealth { report.map { MenuHealth(verdict: $0.verdict) } ?? .unknown }
    public var rows: [CheckRow] { report.map(StatusMapping.rows) ?? [] }
    public var needsAdminCount: Int { rows.filter(\.needsAdmin).count }

    public var headline: String {
        if isChecking && report == nil { return "UpdateDoctor: checking..." }
        return "UpdateDoctor: \(health.title)"
    }

    public func beginCheck() { isChecking = true }

    public func apply(_ report: Report, at date: Date = Date(), admin: Bool = false) {
        self.report = report
        lastChecked = date
        lastError = nil
        isChecking = false
        lastRunWasAdmin = admin
    }

    public func fail(_ message: String) {
        lastError = message
        isChecking = false
    }

    public func lastCheckedText(now: Date = Date()) -> String {
        guard let last = lastChecked else { return isChecking ? "Checking..." : "Last checked: never" }
        let seconds = Int(now.timeIntervalSince(last))
        let ago: String
        if seconds < 60 { ago = "just now" }
        else if seconds < 3600 { ago = "\(seconds / 60) min ago" }
        else { ago = "\(seconds / 3600) h ago" }
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        let suffix = lastRunWasAdmin ? ", full check as admin" : ""
        return "Last checked: \(fmt.string(from: last)) (\(ago)\(suffix))"
    }
}
