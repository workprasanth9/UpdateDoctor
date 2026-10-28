import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import UpdateDoctorKit
@testable import UpdateDoctorMenuCore

final class MenuModelTests: XCTestCase {
    func testVerdictMapsToIconColor() {
        XCTAssertEqual(MenuHealth(verdict: "HEALTHY").colorName, "green")
        XCTAssertEqual(MenuHealth(verdict: "AT_RISK").colorName, "yellow")
        XCTAssertEqual(MenuHealth(verdict: "BLOCKED").colorName, "red")
        XCTAssertEqual(MenuHealth(verdict: "nonsense"), .unknown)
    }

    func testRecordedMacShowsAtRiskWithEveryCheck() {
        let report = runDoctor(.recordedMac())
        let model = MenuViewModel()
        XCTAssertEqual(model.health, .unknown)
        model.apply(report, at: fixedNow)
        XCTAssertEqual(model.health, .atRisk)
        XCTAssertEqual(model.headline, "UpdateDoctor: At risk")
        XCTAssertEqual(model.rows.count, report.checks.count)
        XCTAssertEqual(model.rows.first { $0.id == "os_version" }?.statusLabel, "Warning")
    }

    func testNonRootManagedMacShowsNeedsAdmin() {
        let p = FixtureProbe.recordedMac()
        p.commands["/usr/bin/profiles status -type enrollment"] = fixtureText("synthetic_enrollment_ade.txt")
        let model = MenuViewModel()
        model.apply(runDoctor(p), at: fixedNow)
        let row = model.rows.first { $0.id == "bootstrap_token" }
        XCTAssertEqual(row?.statusLabel, "Needs admin")
        XCTAssertTrue(row?.needsAdmin ?? false)
        XCTAssertEqual(model.needsAdminCount, 1)
    }

    func testBlockedAndHealthyReports() {
        let blocked = FixtureProbe.recordedMac()
        blocked.isRoot = true
        blocked.commands["/usr/bin/profiles status -type enrollment"] = fixtureText("synthetic_enrollment_ade.txt")
        blocked.commands["/usr/bin/profiles status -type bootstraptoken"] = fixtureText("synthetic_bootstrap_missing.txt")
        let model = MenuViewModel()
        model.apply(runDoctor(blocked), at: fixedNow, admin: true)
        XCTAssertEqual(model.health, .blocked)
        XCTAssertEqual(model.rows.first { $0.id == "bootstrap_token" }?.statusLabel, "Failed")
        XCTAssertEqual(model.needsAdminCount, 0)
        XCTAssertTrue(model.lastCheckedText(now: fixedNow).contains("full check as admin"))
    }

    func testAdminJSONDecodesAndScriptIsQuoted() throws {
        let report = runDoctor(.recordedMac())
        let decoded = try AdminRunner.decode(Data(Output.json(report).utf8))
        XCTAssertEqual(decoded.verdict, report.verdict)
        let script = AdminRunner.appleScript(cliPath: "/Applications/Update \"Doctor\".app/Contents/Resources/updatedoctor")
        XCTAssertTrue(script.contains("quoted form of \"/Applications/Update \\\"Doctor\\\".app/Contents/Resources/updatedoctor\""))
        XCTAssertTrue(script.contains("doctor --json || true"))
        XCTAssertTrue(script.hasSuffix("with administrator privileges"))
    }

    func testLastCheckedAndErrors() {
        let model = MenuViewModel()
        XCTAssertEqual(model.lastCheckedText(now: fixedNow), "Last checked: never")
        model.beginCheck()
        XCTAssertTrue(model.isChecking)
        model.fail("Full check cancelled.")
        XCTAssertFalse(model.isChecking)
        XCTAssertEqual(model.lastError, "Full check cancelled.")
        model.apply(runDoctor(.recordedMac()), at: fixedNow.addingTimeInterval(-600))
        XCTAssertNil(model.lastError)
        XCTAssertTrue(model.lastCheckedText(now: fixedNow).contains("10 min ago"))
    }
}
