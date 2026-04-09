import XCTest

final class AIIslandAppBootstrapTests: XCTestCase {
    func testUnitTestBundleLoadsWithoutHostApp() {
        XCTAssertEqual(Bundle(for: Self.self).bundleURL.pathExtension, "xctest")
    }
}
