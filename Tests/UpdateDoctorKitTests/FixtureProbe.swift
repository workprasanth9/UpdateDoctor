import Foundation
@testable import UpdateDoctorKit

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
    return try! Data(contentsOf: url)
}

func fixtureText(_ name: String) -> String { String(decoding: fixture(name), as: UTF8.self) }

/// Replays recorded command output. Nothing touches the real system.
final class FixtureProbe: SystemProbe {
    var isRoot = false
    var commands: [String: String] = [:]
    var files: [String: Data] = [:]
    var reachable = true
    var gdmf: Data? = fixture("gdmf_pmv.json")
    private(set) var ran: [String] = []

    static func recordedMac() -> FixtureProbe {
        let p = FixtureProbe()
        p.commands = [
            "/usr/bin/sw_vers": fixtureText("sw_vers.txt"),
            "/usr/sbin/ioreg": fixtureText("ioreg_applesilicon.txt"),
            "/usr/sbin/sysctl": "Mac16,12\n",
            "/usr/sbin/softwareupdate": fixtureText("softwareupdate_list.txt"),
            "/usr/sbin/diskutil": fixtureText("diskutil.plist"),
            "/usr/bin/pmset": fixtureText("pmset_battery.txt"),
            "/usr/bin/profiles status -type enrollment": fixtureText("enrollment_none.txt"),
            "/usr/bin/fdesetup": "FileVault is On.\n",
        ]
        p.files = [Doctor.suPrefs: fixture("SoftwareUpdate.plist")]
        return p
    }

    func run(_ path: String, _ args: [String], timeout: TimeInterval) -> String? {
        let full = ([path] + args).joined(separator: " ")
        ran.append(full)
        return commands[full] ?? commands[path]
    }
    func readFile(_ path: String) -> Data? { files[path] }
    func fileExists(_ path: String) -> Bool { files[path] != nil }
    func httpStatus(_ url: URL, timeout: TimeInterval) -> Int? { reachable ? 200 : nil }
    func httpGet(_ url: URL, timeout: TimeInterval) -> Data? { reachable ? gdmf : nil }
}

let fixedNow = ISO8601DateFormatter().date(from: "2026-10-28T15:00:00Z")!

func runDoctor(_ probe: FixtureProbe, quick: Bool = false, offline: Bool = false) -> Report {
    var o = DoctorOptions()
    o.quick = quick
    o.offline = offline
    o.now = fixedNow
    return Doctor(probe: probe, options: o).run()
}

extension Report {
    func check(_ id: String) -> CheckResult { checks.first { $0.id == id }! }
}
