import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import UpdateDoctorKit

final class ParserTests: XCTestCase {
    func testVersionCompare() {
        XCTAssertEqual(Parsers.compareVersions("26.7", "26.7.2"), .orderedAscending)
        XCTAssertEqual(Parsers.compareVersions("26.10", "26.9"), .orderedDescending)
        XCTAssertEqual(Parsers.compareVersions("26.7.0", "26.7"), .orderedSame)
    }

    func testSwVers() {
        XCTAssertEqual(Parsers.swVers(fixtureText("sw_vers.txt")), .init(productVersion: "26.7", buildVersion: "25G229"))
    }

    func testDeviceIdentifiers() {
        XCTAssertEqual(Parsers.deviceIdentifiers(ioreg: fixtureText("ioreg_applesilicon.txt")), ["J713AP"])
        XCTAssertEqual(Parsers.deviceIdentifiers(ioreg: fixtureText("synthetic_ioreg_intel.txt")), ["Mac-827FB448E656EC26"])
    }

    func testGDMFLatestForDevice() {
        let releases = Parsers.gdmfReleases(fixture("gdmf_pmv.json"))!
        XCTAssertFalse(releases.isEmpty)
        let latest = Parsers.latestRelease(releases, major: 26, devices: ["J713AP"])
        XCTAssertEqual(latest?.version, "26.7.2")
        XCTAssertEqual(latest?.build, "25G332")
        XCTAssertNil(Parsers.latestRelease(releases, major: 26, devices: ["NOPE999"]))
    }

    func testSoftwareUpdateList() {
        let list = Parsers.softwareUpdateList(fixtureText("softwareupdate_list.txt"))
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[1].label, "macOS Tahoe 26.7.2-25G332")
        XCTAssertTrue(list[1].requiresRestart)
        XCTAssertFalse(list[0].requiresRestart)
        XCTAssertTrue(Parsers.softwareUpdateList(fixtureText("synthetic_softwareupdate_none.txt")).isEmpty)
    }

    func testPmset() {
        let batt = Parsers.pmsetBattery(fixtureText("pmset_battery.txt"))
        XCTAssertFalse(batt.onACPower)
        XCTAssertNotNil(batt.batteryPercent)
        XCTAssertEqual(Parsers.pmsetBattery(fixtureText("synthetic_pmset_ac.txt")), .init(onACPower: true, batteryPercent: 100))
    }

    func testDiskutil() {
        XCTAssertGreaterThan(Parsers.containerFreeBytes(diskutilPlist: fixture("diskutil.plist")) ?? 0, 1_000_000_000)
        XCTAssertEqual(Parsers.containerFreeBytes(diskutilPlist: fixture("synthetic_diskutil_low.plist")), 9_000_000_000)
    }

    func testProfiles() {
        XCTAssertEqual(Parsers.enrollment(fixtureText("enrollment_none.txt")), .init(enrolledViaDEP: false, mdmEnrolled: false, userApproved: false))
        XCTAssertEqual(Parsers.enrollment(fixtureText("synthetic_enrollment_ade.txt")), .init(enrolledViaDEP: true, mdmEnrolled: true, userApproved: true))
        XCTAssertEqual(Parsers.bootstrapToken(fixtureText("synthetic_bootstrap_escrowed.txt")), .init(supportedOnServer: true, escrowed: true))
        XCTAssertEqual(Parsers.bootstrapToken(fixtureText("synthetic_bootstrap_missing.txt")).escrowed, false)
        XCTAssertEqual(Parsers.fileVaultOn("FileVault is Off.\n"), false)
    }
}
