import Foundation

public struct DoctorOptions {
    /// Skip `softwareupdate -l`, which can take a minute.
    public var quick = false
    /// Skip every network request (GDMF feed and host reachability).
    public var offline = false
    /// Count softwareupdated and mobileassetd errors in the unified log (slow, needs root for full results).
    public var includeLogs = false
    public var now = Date()
    public init() {}
}

/// Hosts Apple documents for macOS software updates
/// (support.apple.com/101555, "Use Apple products on enterprise networks").
public let appleUpdateHosts = [
    "gdmf.apple.com",
    "mesu.apple.com",
    "swscan.apple.com",
    "swcdn.apple.com",
    "swdist.apple.com",
    "updates.cdn-apple.com",
]

public let gdmfURL = URL(string: "https://gdmf.apple.com/v2/pmv")!

public struct Doctor {
    let probe: SystemProbe
    let options: DoctorOptions

    public init(probe: SystemProbe, options: DoctorOptions = DoctorOptions()) {
        self.probe = probe
        self.options = options
    }

    public static let suPrefs = "/Library/Preferences/com.apple.SoftwareUpdate.plist"
    public static let managedSU = "/Library/Managed Preferences/com.apple.SoftwareUpdate.plist"
    public static let managedRestrictions = "/Library/Managed Preferences/com.apple.applicationaccess.plist"

    public func run() -> Report {
        var checks: [CheckResult] = []
        let os = probe.run("/usr/bin/sw_vers", [], timeout: 10).flatMap(Parsers.swVers)
        let ioreg = probe.run("/usr/sbin/ioreg", ["-rd1", "-c", "IOPlatformExpertDevice"], timeout: 10) ?? ""
        let devices = Parsers.deviceIdentifiers(ioreg: ioreg)
        let model = probe.run("/usr/sbin/sysctl", ["-n", "hw.model"], timeout: 5)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"

        checks.append(osCheck(os: os, devices: devices, model: model))
        checks.append(pendingCheck())
        checks.append(diskCheck())
        checks.append(powerCheck())
        checks.append(networkCheck())
        let enrollment = enrollmentCheck()
        checks.append(enrollment.result)
        checks.append(bootstrapCheck(mdm: enrollment.mdm))
        checks.append(fileVaultCheck())
        checks.append(contentsOf: softwareUpdatePrefsChecks())
        checks.append(managedDeferralCheck())
        checks.append(logsCheck())
        return Report.make(checks: checks, runningAsRoot: probe.isRoot, date: options.now)
    }

    // MARK: OS version versus Apple's feed

    func osCheck(os: Parsers.OSInfo?, devices: [String], model: String) -> CheckResult {
        let id = "os_version", title = "macOS version vs Apple GDMF feed"
        guard let os else {
            return CheckResult(id: id, title: title, status: .fail, detail: "Could not read sw_vers.", fix: "Run /usr/bin/sw_vers manually.")
        }
        let here = "macOS \(os.productVersion) (\(os.buildVersion)) on \(model)"
        if options.offline {
            return CheckResult(id: id, title: title, status: .skipped, detail: "\(here). Offline mode, feed not checked.")
        }
        guard let data = probe.httpGet(gdmfURL, timeout: 15), let releases = Parsers.gdmfReleases(data) else {
            return CheckResult(id: id, title: title, status: .warn,
                               detail: "\(here). Could not download or parse \(gdmfURL.absoluteString).",
                               fix: "Check that gdmf.apple.com is allowed and not behind TLS inspection. Macs use this feed to learn which updates exist.")
        }
        let major = Parsers.majorVersion(os.productVersion)
        guard let latest = Parsers.latestRelease(releases, major: major, devices: devices) else {
            return CheckResult(id: id, title: title, status: .info,
                               detail: "\(here). No macOS \(major) release in the feed lists this device (\(devices.joined(separator: ", "))).")
        }
        var newerMajor = ""
        let lowered = Set(devices.map { $0.lowercased() })
        if let next = releases.filter({ Parsers.majorVersion($0.version) > major && $0.supportedDevices.contains { lowered.contains($0.lowercased()) } })
            .max(by: { Parsers.compareVersions($0.version, $1.version) == .orderedAscending }) {
            newerMajor = " A newer major release, macOS \(next.version), also supports this Mac."
        }
        switch Parsers.compareVersions(os.productVersion, latest.version) {
        case .orderedAscending:
            return CheckResult(id: id, title: title, status: .warn,
                               detail: "\(here) is behind macOS \(latest.version) (\(latest.build)), posted \(latest.postingDate).\(newerMajor)",
                               fix: "Install the update from System Settings > General > Software Update, or let your MDM's DDM software update declaration enforce it. Resolve any failing checks below first.")
        default:
            return CheckResult(id: id, title: title, status: .pass,
                               detail: "\(here) matches the newest macOS \(major) release in Apple's feed.\(newerMajor)")
        }
    }

    // MARK: softwareupdate -l

    func pendingCheck() -> CheckResult {
        let id = "pending_updates", title = "Updates offered by softwareupdate"
        if options.quick {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Quick mode, softwareupdate -l not run.")
        }
        guard let out = probe.run("/usr/sbin/softwareupdate", ["-l"], timeout: 120) else {
            return CheckResult(id: id, title: title, status: .warn, detail: "softwareupdate -l did not finish within 120 seconds.",
                               fix: "softwareupdated may be stuck. Check `log show --last 1h --predicate 'process == \"softwareupdated\"'` as an admin.")
        }
        if out.contains("No new software available") {
            return CheckResult(id: id, title: title, status: .pass, detail: "No new software available.")
        }
        let updates = Parsers.softwareUpdateList(out)
        if updates.isEmpty {
            let firstLine = out.split(separator: "\n").last.map(String.init) ?? ""
            return CheckResult(id: id, title: title, status: .warn, detail: "softwareupdate -l returned no list. Last line: \(firstLine)",
                               fix: "Catalog scans can fail from network filtering or a custom CatalogURL. Compare with the network check.")
        }
        let names = updates.map { $0.title + ($0.version.isEmpty || $0.title.contains($0.version) ? "" : " \($0.version)") + ($0.requiresRestart ? " (restart)" : "") }
        return CheckResult(id: id, title: title, status: .info, detail: "\(updates.count) offered: " + names.joined(separator: ", "))
    }

    // MARK: Disk

    /// Apple does not publish one exact number. These thresholds are conservative
    /// heuristics: minor updates often need about 15 to 20 GB of working space.
    static let diskWarnBytes: Int64 = 25_000_000_000
    static let diskFailBytes: Int64 = 15_000_000_000

    func diskCheck() -> CheckResult {
        let id = "disk_space", title = "Free space in the APFS container"
        guard let out = probe.run("/usr/sbin/diskutil", ["info", "-plist", "/"], timeout: 15),
              let free = Parsers.containerFreeBytes(diskutilPlist: Data(out.utf8)) else {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Could not read diskutil info for /.")
        }
        let gb = String(format: "%.1f GB", Double(free) / 1_000_000_000)
        let fix = "Free up space (Storage settings, old installers, Xcode caches, local Time Machine snapshots via `tmutil listlocalsnapshots /`)."
        if free < Self.diskFailBytes {
            return CheckResult(id: id, title: title, status: .fail, detail: "Only \(gb) free. Updates commonly fail to prepare below about 15 GB.", fix: fix)
        }
        if free < Self.diskWarnBytes {
            return CheckResult(id: id, title: title, status: .warn, detail: "\(gb) free. Enough for a small update, tight for a full or major one.", fix: fix)
        }
        return CheckResult(id: id, title: title, status: .pass, detail: "\(gb) free.")
    }

    // MARK: Power

    func powerCheck() -> CheckResult {
        let id = "power", title = "Power source and battery"
        guard let out = probe.run("/usr/bin/pmset", ["-g", "batt"], timeout: 10) else {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Could not run pmset.")
        }
        let power = Parsers.pmsetBattery(out)
        if power.onACPower {
            return CheckResult(id: id, title: title, status: .pass, detail: "On AC power" + (power.batteryPercent.map { ", battery \($0)%." } ?? "."))
        }
        guard let pct = power.batteryPercent else {
            return CheckResult(id: id, title: title, status: .info, detail: "No battery detected and not reported as AC. Desktop Macs usually show AC Power.")
        }
        if pct < 50 {
            return CheckResult(id: id, title: title, status: .warn, detail: "On battery at \(pct)%. Laptops may postpone installing until plugged in or charged.",
                               fix: "Connect to power before the enforced install time.")
        }
        return CheckResult(id: id, title: title, status: .pass, detail: "On battery at \(pct)%.")
    }

    // MARK: Network

    func networkCheck() -> CheckResult {
        let id = "network", title = "Reachability of Apple update hosts"
        if options.offline {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Offline mode.")
        }
        var unreachable: [String] = []
        for host in appleUpdateHosts {
            if probe.httpStatus(URL(string: "https://\(host)/")!, timeout: 8) == nil { unreachable.append(host) }
        }
        if unreachable.isEmpty {
            return CheckResult(id: id, title: title, status: .pass, detail: "All \(appleUpdateHosts.count) hosts answered over HTTPS.")
        }
        let status: CheckStatus = unreachable.count == appleUpdateHosts.count ? .fail : .warn
        return CheckResult(id: id, title: title, status: status,
                           detail: "No HTTPS answer from: \(unreachable.joined(separator: ", ")).",
                           fix: "Allow these hosts through firewalls and proxies, and exclude them from TLS inspection (Apple support article 101555).")
    }

    // MARK: MDM

    func enrollmentCheck() -> (result: CheckResult, mdm: Bool) {
        let id = "mdm_enrollment", title = "MDM enrollment"
        guard let out = probe.run("/usr/bin/profiles", ["status", "-type", "enrollment"], timeout: 15) else {
            return (CheckResult(id: id, title: title, status: .skipped, detail: "Could not run profiles."), false)
        }
        let e = Parsers.enrollment(out)
        if !e.mdmEnrolled {
            return (CheckResult(id: id, title: title, status: .info,
                                detail: "Not MDM enrolled, so no DDM software update enforcement applies. MDM specific checks are skipped."), false)
        }
        if !e.userApproved && !e.enrolledViaDEP {
            return (CheckResult(id: id, title: title, status: .warn,
                                detail: "Enrolled, but not User Approved or via Automated Device Enrollment.",
                                fix: "Approve the MDM profile in System Settings > Privacy & Security > Profiles. Unapproved enrollment limits what MDM can enforce."), true)
        }
        return (CheckResult(id: id, title: title, status: .pass,
                            detail: "Enrolled" + (e.enrolledViaDEP ? " via Automated Device Enrollment." : ", User Approved.")), true)
    }

    func bootstrapCheck(mdm: Bool) -> CheckResult {
        let id = "bootstrap_token", title = "Bootstrap Token escrow"
        if !mdm {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Skipped, Mac is not MDM enrolled.")
        }
        if !probe.isRoot {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Skipped, needs root. Run with sudo or from Jamf.")
        }
        guard let out = probe.run("/usr/bin/profiles", ["status", "-type", "bootstraptoken"], timeout: 15) else {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Could not run profiles.")
        }
        let t = Parsers.bootstrapToken(out)
        if t.supportedOnServer == false {
            return CheckResult(id: id, title: title, status: .warn, detail: "The MDM server does not report Bootstrap Token support.",
                               fix: "Without a Bootstrap Token, Apple silicon Macs may need a user to authorize MDM enforced updates.")
        }
        if t.escrowed != true {
            return CheckResult(id: id, title: title, status: .fail, detail: "Bootstrap Token is not escrowed to the MDM server.",
                               fix: "Have a Secure Token admin sign in, or run `sudo profiles install -type bootstraptoken`. Apple silicon Macs need it to install enforced updates without a user password.")
        }
        return CheckResult(id: id, title: title, status: .pass, detail: "Escrowed to the MDM server.")
    }

    func fileVaultCheck() -> CheckResult {
        let id = "filevault", title = "FileVault"
        guard let out = probe.run("/usr/bin/fdesetup", ["status"], timeout: 10), let on = Parsers.fileVaultOn(out) else {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Could not read fdesetup status.")
        }
        return CheckResult(id: id, title: title, status: .info,
                           detail: on ? "On. Unattended restarts for updates depend on the Bootstrap Token or a user authorizing them."
                                      : "Off. Does not block updates.")
    }

    // MARK: Software Update preferences

    func softwareUpdatePrefsChecks() -> [CheckResult] {
        guard let prefs = Parsers.plist(probe.readFile(Self.suPrefs)) else {
            return [CheckResult(id: "su_history", title: "Software Update history", status: .skipped,
                                detail: "Could not read \(Self.suPrefs).")]
        }
        var results: [CheckResult] = []

        // DDM persisted errors
        let ddmID = "ddm_errors", ddmTitle = "DDM software update errors"
        if let errors = prefs["DDMPersistedErrorKey"] as? [String: Any], !errors.isEmpty {
            let text = errors.map { "\($0.key)=\(String(describing: $0.value))" }.sorted().joined(separator: "; ")
            results.append(CheckResult(id: ddmID, title: ddmTitle, status: .fail,
                                       detail: "softwareupdated recorded DDM errors: \(String(text.prefix(400)))",
                                       fix: "Check the software update declaration in your MDM (target version, build, date) and that the target version is valid for this Mac in the GDMF feed."))
        } else if prefs["DDMPersistedErrorKey"] != nil {
            results.append(CheckResult(id: ddmID, title: ddmTitle, status: .pass, detail: "No persisted DDM errors."))
        } else {
            results.append(CheckResult(id: ddmID, title: ddmTitle, status: .info, detail: "No DDM error record present."))
        }

        // Last result and last successful check
        let histID = "su_history", histTitle = "Software Update scan history"
        let code = (prefs["LastResultCode"] as? NSNumber)?.intValue
        let last = prefs["LastSuccessfulDate"] as? Date
        var notes: [String] = []
        var status: CheckStatus = .pass
        var fix: String?
        if let last {
            let days = Int(options.now.timeIntervalSince(last) / 86_400)
            notes.append("Last successful scan \(days) day(s) ago")
            if days > 7 {
                status = .warn
                fix = "The Mac has not checked Apple's catalog in over a week. Run `softwareupdate -l` and look at the network check."
            }
        } else {
            notes.append("No successful scan recorded")
            status = .warn
            fix = "Run `softwareupdate -l` to see whether catalog scans work at all."
        }
        if let code {
            notes.append("LastResultCode \(code)")
            if code != 0 && status == .pass { status = .info }
        }
        if let url = prefs["CatalogURL"] as? String, !url.contains("swscan.apple.com") {
            notes.append("custom CatalogURL \(url)")
            status = max(status, .warn)
            fix = fix ?? "A non Apple CatalogURL is set. Remove it from the managing profile, or delete the CatalogURL key from /Library/Preferences/com.apple.SoftwareUpdate.plist, if it is not intentional."
        } else if let url = prefs["CatalogURL"] as? String, url.contains("beta") {
            notes.append("beta catalog in use, so beta builds may be offered")
            if status == .pass { status = .info }
            fix = fix ?? "To leave beta updates, set Beta Updates to Off in System Settings > General > Software Update."
        }
        results.append(CheckResult(id: histID, title: histTitle, status: status, detail: notes.joined(separator: ", ") + ".", fix: fix))

        // Automatic update settings
        let autoID = "auto_settings", autoTitle = "Automatic update settings"
        let managed = Parsers.plist(probe.readFile(Self.managedSU)) ?? [:]
        func flag(_ key: String) -> Bool? { (managed[key] as? Bool) ?? (prefs[key] as? Bool) }
        let keys = ["AutomaticCheckEnabled", "AutomaticDownload", "AutomaticallyInstallMacOSUpdates"]
        let off = keys.filter { flag($0) == false }
        if off.isEmpty {
            results.append(CheckResult(id: autoID, title: autoTitle, status: .pass, detail: "Automatic check, download and install are not turned off."))
        } else {
            results.append(CheckResult(id: autoID, title: autoTitle, status: .info,
                                       detail: "Turned off: \(off.joined(separator: ", ")). DDM enforcement still applies at its deadline, but nothing happens on its own before then."))
        }
        return results
    }

    func managedDeferralCheck() -> CheckResult {
        let id = "deferral", title = "Managed update deferral"
        guard let r = Parsers.plist(probe.readFile(Self.managedRestrictions)) else {
            return CheckResult(id: id, title: title, status: .pass, detail: "No managed restrictions profile delays updates.")
        }
        var notes: [String] = []
        if r["forceDelayedSoftwareUpdates"] as? Bool == true {
            notes.append("minor updates delayed \((r["enforcedSoftwareUpdateMinorOSDeferredInstallDelay"] as? NSNumber ?? r["enforcedSoftwareUpdateDelay"] as? NSNumber)?.intValue ?? 30) day(s)")
        }
        if r["forceDelayedMajorSoftwareUpdates"] as? Bool == true {
            notes.append("major upgrades delayed \((r["enforcedSoftwareUpdateMajorOSDeferredInstallDelay"] as? NSNumber)?.intValue ?? 30) day(s)")
        }
        if notes.isEmpty {
            return CheckResult(id: id, title: title, status: .pass, detail: "Restrictions profile present, no update delay set.")
        }
        return CheckResult(id: id, title: title, status: .info,
                           detail: "A restrictions profile hides new updates: \(notes.joined(separator: ", ")). This can explain why the Mac does not see the newest release yet.")
    }

    // MARK: Unified log

    func logsCheck() -> CheckResult {
        let id = "update_logs", title = "Recent update errors in the unified log"
        if !options.includeLogs {
            return CheckResult(id: id, title: title, status: .skipped, detail: "Not requested. Add --logs to include it.")
        }
        let predicate = "(process == \"softwareupdated\" OR process == \"mobileassetd\") AND messageType == error"
        guard let out = probe.run("/usr/bin/log", ["show", "--last", "24h", "--style", "compact", "--predicate", predicate], timeout: 180) else {
            return CheckResult(id: id, title: title, status: .skipped, detail: "log show did not finish within 180 seconds.")
        }
        let lines = out.split(separator: "\n").filter { !$0.hasPrefix("Timestamp") && !$0.hasPrefix("Filtering") && !$0.isEmpty }
        let rootNote = probe.isRoot ? "" : " Not root, so some entries may be hidden."
        if lines.isEmpty {
            return CheckResult(id: id, title: title, status: .pass, detail: "No softwareupdated or mobileassetd errors in the last 24 hours.\(rootNote)")
        }
        let sample = lines.suffix(3).map { String($0.prefix(200)) }.joined(separator: " | ")
        return CheckResult(id: id, title: title, status: .info,
                           detail: "\(lines.count) error line(s) in the last 24 hours. Latest: \(sample)\(rootNote)",
                           fix: "Many of these are routine. Look for repeated errors near the time an install was due.")
    }
}
