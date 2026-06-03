import XCTest
@testable import ClaudeUsageTrackerBar

final class AppSettingsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "showInMenuBar")
        UserDefaults.standard.removeObject(forKey: "menuBarDisplay")
    }

    func test_showInMenuBar_defaultsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.showInMenuBar)
    }

    func test_showInMenuBar_persists() {
        let settings = AppSettings()
        settings.setShowInMenuBar(true)
        let settings2 = AppSettings()
        XCTAssertTrue(settings2.showInMenuBar)
    }

    func test_menuBarDisplay_defaultsCost() {
        let settings = AppSettings()
        XCTAssertEqual(settings.menuBarDisplay, .cost)
    }

    func test_menuBarDisplay_persists() {
        let settings = AppSettings()
        settings.setMenuBarDisplay(.tokens)
        let settings2 = AppSettings()
        XCTAssertEqual(settings2.menuBarDisplay, .tokens)
    }
}
