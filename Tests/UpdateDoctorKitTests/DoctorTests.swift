import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import UpdateDoctorKit

final class DoctorTests: XCTestCase {
    func testRecordedMacIsBehindAndAtRisk() {
        let report = runDoctor(.recordedMac())
        XCTAssertEqual(report.check("os_version").status, .warn)
        XCTAssertTrue(report.check("os_version").detail.contains("26.7.2"))
        XCTAssertEqual(report.check("pending_updates").status, .info)
        XCTAssertEqual(report.check("mdm_enrollment").status, .info)
        XCTAssertEqual(report.check("bootstrap_token").status, .skipped)
        XCTAssertEqual(report.check("ddm_errors").status, .pass)
        XCTAssertTrue(report.check("su_history").detail.contains("beta catalog"))
        XCTAssertEqual(report.verdict, "AT_RISK")
    }

    func testNotRootSkipsBootstrapOnManagedMac() {
        let p = FixtureProbe.recordedMac()
        p.commands["/usr/bin/profiles status -type enrollment"] = fixtureText("synthetic_enrollment_ade.txt")
        let report = runDoctor(p)
        XCTAssertEqual(report.check("mdm_enrollment").status, .pass)
        XCTAssertEqual(report.check("bootstrap_token").status, .skipped)
        XCTAssertTrue(report.check("bootstrap_token").detail.contains("root"))
        XCTAssertFalse(p.ran.contains("/usr/bin/profiles status -type bootstraptoken"))
    }

    func testRootManagedMissingBootstrapBlocks() {
        let p = FixtureProbe.recordedMac()
        p.isRoot = true
        p.commands["/usr/bin/profiles status -type enrollment"] = fixtureText("synthetic_enrollment_ade.txt")
        p.commands["/usr/bin/profiles status -type bootstraptoken"] = fixtureText("synthetic_bootstrap_missing.txt")
        let report = runDoctor(p)
        XCTAssertEqual(report.check("bootstrap_token").status, .fail)
        XCTAssertEqual(report.verdict, "BLOCKED")
        XCTAssertEqual(Output.jamfEA(report), "<result>BLOCKED: bootstrap_token</result>")
    }

    func testHealthyMac() {
        let p = FixtureProbe.recordedMac()
        p.isRoot = true
        p.commands["/usr/bin/sw_vers"] = "ProductName:\t\tmacOS\nProductVersion:\t\t26.7.2\nBuildVersion:\t\t25G332\n"
        p.commands["/usr/sbin/softwareupdate"] = fixtureText("synthetic_softwareupdate_none.txt")
        p.commands["/usr/bin/pmset"] = fixtureText("synthetic_pmset_ac.txt")
        p.commands["/usr/bin/profiles status -type enrollment"] = fixtureText("synthetic_enrollment_ade.txt")
        p.commands["/usr/bin/profiles status -type bootstraptoken"] = fixtureText("synthetic_bootstrap_escrowed.txt")
        let report = runDoctor(p)
        XCTAssertEqual(report.verdict, "HEALTHY", Output.text(report))
        XCTAssertEqual(Output.jamfEA(report), "<result>HEALTHY</result>")
    }

    func testLowDiskAndDDMErrorFail() {
        let p = FixtureProbe.recordedMac()
        p.commands["/usr/sbin/diskutil"] = fixtureText("synthetic_diskutil_low.plist")
        p.files[Doctor.suPrefs] = fixture("synthetic_SoftwareUpdate_ddm_error.plist")
        let report = runDoctor(p)
        XCTAssertEqual(report.check("disk_space").status, .fail)
        XCTAssertEqual(report.check("ddm_errors").status, .fail)
        XCTAssertTrue(report.check("ddm_errors").detail.contains("8406"))
        XCTAssertEqual(Output.jamfEA(report), "<result>BLOCKED: disk_space, ddm_errors</result>")
    }

    func testDeferralIsReported() {
        let p = FixtureProbe.recordedMac()
        p.files[Doctor.managedRestrictions] = fixture("synthetic_applicationaccess_deferral.plist")
        let check = runDoctor(p).check("deferral")
        XCTAssertEqual(check.status, .info)
        XCTAssertTrue(check.detail.contains("14 day"))
    }

    func testNetworkDownFails() {
        let p = FixtureProbe.recordedMac()
        p.reachable = false
        let report = runDoctor(p)
        XCTAssertEqual(report.check("network").status, .fail)
        XCTAssertEqual(report.check("os_version").status, .warn)
    }

    func testQuickAndOfflineSkip() {
        let p = FixtureProbe.recordedMac()
        let report = runDoctor(p, quick: true, offline: true)
        XCTAssertEqual(report.check("pending_updates").status, .skipped)
        XCTAssertEqual(report.check("network").status, .skipped)
        XCTAssertFalse(p.ran.contains { $0.hasPrefix("/usr/sbin/softwareupdate") })
    }

    func testStaleScanWarns() {
        var o = DoctorOptions()
        o.now = fixedNow.addingTimeInterval(30 * 86_400)
        let report = Doctor(probe: FixtureProbe.recordedMac(), options: o).run()
        XCTAssertEqual(report.check("su_history").status, .warn)
    }

    func testJSONRoundTrip() throws {
        let report = runDoctor(.recordedMac())
        let decoded = try JSONDecoder().decode(Report.self, from: Data(Output.json(report).utf8))
        XCTAssertEqual(decoded.checks, report.checks)
    }

    func testNeverRunsWritingCommands() {
        let p = FixtureProbe.recordedMac()
        p.isRoot = true
        _ = runDoctor(p)
        for cmd in p.ran {
            XCTAssertFalse(cmd.contains("--install") || cmd.contains("--download") || cmd.contains(" -i") || cmd.contains("install -type"), cmd)
        }
    }
}
