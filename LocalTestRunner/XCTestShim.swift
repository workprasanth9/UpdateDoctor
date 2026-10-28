// A tiny stand in for XCTest so the same fixture tests run on a Mac that only
// has the Command Line Tools (which ship without XCTest). CI runs the real
// XCTest target with `swift test`; this runner is `swift run fixture-tests`.
#if !canImport(XCTest)
import Foundation

class XCTestCase {
    required init() {}
}

var failures = 0
var currentTest = ""

func record(_ ok: Bool, _ message: String, _ file: StaticString, _ line: UInt) {
    if !ok {
        failures += 1
        print("  FAIL \(currentTest) \(file):\(line) \(message)")
    }
}

func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    let x = try? a(), y = try? b()
    record(x == y, "\(String(describing: x)) != \(String(describing: y)) \(message())", file, line)
}
func XCTAssertTrue(_ v: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    record((try? v()) == true, "expected true \(message())", file, line)
}
func XCTAssertFalse(_ v: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    record((try? v()) == false, "expected false \(message())", file, line)
}
func XCTAssertNil<T>(_ v: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(((try? v()) ?? nil) == nil, "expected nil \(message())", file, line)
}
func XCTAssertNotNil<T>(_ v: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    record(((try? v()) ?? nil) != nil, "expected non nil \(message())", file, line)
}
func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #filePath, line: UInt = #line) {
    guard let x = try? a(), let y = try? b() else { return record(false, "threw", file, line) }
    record(x > y, "\(x) <= \(y) \(message())", file, line)
}
#endif
