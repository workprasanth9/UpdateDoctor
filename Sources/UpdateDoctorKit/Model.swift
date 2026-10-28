import Foundation

public enum CheckStatus: String, Codable, Comparable {
    case pass, info, warn, fail, skipped

    var rank: Int {
        switch self {
        case .pass: return 0
        case .skipped: return 1
        case .info: return 2
        case .warn: return 3
        case .fail: return 4
        }
    }

    public static func < (lhs: CheckStatus, rhs: CheckStatus) -> Bool { lhs.rank < rhs.rank }
}

public struct CheckResult: Codable, Equatable {
    public let id: String
    public let title: String
    public let status: CheckStatus
    public let detail: String
    public let fix: String?

    public init(id: String, title: String, status: CheckStatus, detail: String, fix: String? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.detail = detail
        self.fix = fix
    }
}

public struct Report: Codable {
    public let tool: String
    public let version: String
    public let generatedAt: String
    public let runningAsRoot: Bool
    public let verdict: String
    public let summary: String
    public let checks: [CheckResult]

    public static func make(checks: [CheckResult], runningAsRoot: Bool, date: Date = Date()) -> Report {
        let worst = checks.map(\.status).max() ?? .pass
        let verdict: String
        switch worst {
        case .fail: verdict = "BLOCKED"
        case .warn: verdict = "AT_RISK"
        default: verdict = "HEALTHY"
        }
        let failing = checks.filter { $0.status == .fail || $0.status == .warn }
        let summary: String
        if failing.isEmpty {
            summary = "No blocking problems found."
        } else {
            summary = failing.map { "\($0.id): \($0.detail.hasSuffix(".") ? String($0.detail.dropLast()) : $0.detail)" }.joined(separator: "; ")
        }
        let fmt = ISO8601DateFormatter()
        return Report(tool: "updatedoctor", version: UpdateDoctorVersion.current,
                      generatedAt: fmt.string(from: date), runningAsRoot: runningAsRoot,
                      verdict: verdict, summary: summary, checks: checks)
    }
}
