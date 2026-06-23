import XCTest
@testable import ClaudeUsageTrackerBar

final class AppSettingsTests: XCTestCase {

    private let keys = ["showInMenuBar", "menuBarDisplay", "launchAtLogin", "debugMode", "animateUpdates", "costMode", "showToday", "showLast30Days", "showAllTime"]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }

    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
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

    func test_showToday_defaultsTrue() {
        let settings = AppSettings()
        XCTAssertTrue(settings.showToday)
    }

    func test_showToday_persists() {
        let settings = AppSettings()
        settings.setShowToday(false)
        let settings2 = AppSettings()
        XCTAssertFalse(settings2.showToday)
    }

    func test_showLast30Days_defaultsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.showLast30Days)
    }

    func test_showLast30Days_persists() {
        let settings = AppSettings()
        settings.setShowLast30Days(false)
        let settings2 = AppSettings()
        XCTAssertFalse(settings2.showLast30Days)
    }

    func test_showAllTime_defaultsFalse() {
        let settings = AppSettings()
        XCTAssertFalse(settings.showAllTime)
    }

    func test_showAllTime_persists() {
        let settings = AppSettings()
        settings.setShowAllTime(false)
        let settings2 = AppSettings()
        XCTAssertFalse(settings2.showAllTime)
    }
}
