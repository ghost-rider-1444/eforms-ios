import XCTest

final class AppReviewFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testFoldersAttendanceAndNativeFormAreReachable() {
        XCTAssertTrue(app.staticTexts["eForms"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Attendance overdue"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.searchFields["Search forms"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Forms'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Drafts'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Outbox'")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Sent'")).firstMatch.exists)

        app.buttons["Attendance overdue"].tap()
        XCTAssertTrue(app.navigationBars["Attendance sessions"].waitForExistence(timeout: 3))
        XCTAssertGreaterThanOrEqual(app.cells.count, 3)
        app.buttons["Close"].tap()

        let form = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Example placement attendance'")).firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        form.tap()
        XCTAssertTrue(app.navigationBars["Example placement attendance"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Population'")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Student name'")).firstMatch.exists)
        for _ in 0..<6 where !app.buttons["Clear signature"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["Clear signature"].exists)
        XCTAssertTrue(app.buttons["Done"].exists)
    }

    func testSearchAndPrivacyFooter() {
        let search = app.searchFields["Search forms"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("placement")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Example placement attendance'")).firstMatch.exists)
        if search.buttons["Clear text"].exists { search.buttons["Clear text"].tap() }

        let privacy = app.buttons["Privacy & data use"]
        for _ in 0..<8 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.isHittable)
        privacy.tap()
        XCTAssertTrue(app.navigationBars["Privacy"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open App Review demo"].exists)
    }
}
