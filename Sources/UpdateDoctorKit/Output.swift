import Foundation

public enum Output {
    public static func text(_ report: Report) -> String {
        var lines: [String] = []
        lines.append("UpdateDoctor \(report.version)  \(report.generatedAt)")
        lines.append("Verdict: \(report.verdict)")
        lines.append("")
        for c in report.checks {
            let tag: String
            switch c.status {
            case .pass: tag = "[PASS]"
            case .info: tag = "[INFO]"
            case .warn: tag = "[WARN]"
            case .fail: tag = "[FAIL]"
            case .skipped: tag = "[SKIP]"
            }
            lines.append("\(tag) \(c.title)")
            lines.append("       \(c.detail)")
            if let fix = c.fix, c.status == .fail || c.status == .warn || c.status == .info {
                lines.append("       Fix: \(fix)")
            }
        }
        let skipped = report.checks.filter { $0.status == .skipped }.map(\.id)
        lines.append("")
        if !skipped.isEmpty { lines.append("Skipped: \(skipped.joined(separator: ", "))") }
        if !report.runningAsRoot { lines.append("Not running as root. Run with sudo for the Bootstrap Token check.") }
        lines.append("Summary: \(report.summary)")
        return lines.joined(separator: "\n")
    }

    public static func json(_ report: Report) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(report) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// One line for a Jamf Pro Extension Attribute, for example
    /// <result>BLOCKED: disk_space, bootstrap_token</result>
    public static func jamfEA(_ report: Report) -> String {
        let bad = report.checks.filter { $0.status == .fail }.map(\.id)
        let risky = report.checks.filter { $0.status == .warn }.map(\.id)
        var value = report.verdict
        if !bad.isEmpty { value += ": " + bad.joined(separator: ", ") }
        else if !risky.isEmpty { value += ": " + risky.joined(separator: ", ") }
        return "<result>\(value)</result>"
    }
}
