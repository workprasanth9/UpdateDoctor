#if !canImport(XCTest)
import Foundation

func runAll() {
    let p = ParserTests()
    let d = DoctorTests()
    let m = MenuModelTests()
    let tests: [(String, () throws -> Void)] = [
        ("testVersionCompare", p.testVersionCompare),
        ("testSwVers", p.testSwVers),
        ("testDeviceIdentifiers", p.testDeviceIdentifiers),
        ("testGDMFLatestForDevice", p.testGDMFLatestForDevice),
        ("testSoftwareUpdateList", p.testSoftwareUpdateList),
        ("testPmset", p.testPmset),
        ("testDiskutil", p.testDiskutil),
        ("testProfiles", p.testProfiles),
        ("testRecordedMacIsBehindAndAtRisk", d.testRecordedMacIsBehindAndAtRisk),
        ("testNotRootSkipsBootstrapOnManagedMac", d.testNotRootSkipsBootstrapOnManagedMac),
        ("testRootManagedMissingBootstrapBlocks", d.testRootManagedMissingBootstrapBlocks),
        ("testHealthyMac", d.testHealthyMac),
        ("testLowDiskAndDDMErrorFail", d.testLowDiskAndDDMErrorFail),
        ("testDeferralIsReported", d.testDeferralIsReported),
        ("testNetworkDownFails", d.testNetworkDownFails),
        ("testQuickAndOfflineSkip", d.testQuickAndOfflineSkip),
        ("testStaleScanWarns", d.testStaleScanWarns),
        ("testJSONRoundTrip", d.testJSONRoundTrip),
        ("testNeverRunsWritingCommands", d.testNeverRunsWritingCommands),
        ("testVerdictMapsToIconColor", m.testVerdictMapsToIconColor),
        ("testRecordedMacShowsAtRiskWithEveryCheck", m.testRecordedMacShowsAtRiskWithEveryCheck),
        ("testNonRootManagedMacShowsNeedsAdmin", m.testNonRootManagedMacShowsNeedsAdmin),
        ("testBlockedAndHealthyReports", m.testBlockedAndHealthyReports),
        ("testAdminJSONDecodesAndScriptIsQuoted", m.testAdminJSONDecodesAndScriptIsQuoted),
        ("testLastCheckedAndErrors", m.testLastCheckedAndErrors),
    ]
    for (name, test) in tests {
        currentTest = name
        let before = failures
        do { try test() } catch { failures += 1; print("  FAIL \(name) threw \(error)") }
        print("\(failures == before ? "ok  " : "FAIL") \(name)")
    }
    print("\(tests.count) tests, \(failures) failure(s)")
    exit(failures == 0 ? 0 : 1)
}
runAll()
#else
print("XCTest is available here. Use `swift test` instead.")
#endif
