import XCTest

/// Walks through a Test Hills run in the simulator, saving a screenshot at each step for review. Local only (not
/// part of `make check`): run with `make ui-test`.
@MainActor
final class RunFlowUITests: XCTestCase {
    func testTestHillsRun() throws {
        let app = XCUIApplication()
        app.launch()
        snapshot("1-course-list")

        app.staticTexts["Test Hills"].tap()
        XCTAssertTrue(app.buttons["start"].waitForExistence(timeout: 5))
        // Fastest speed so the first change (200 m) comes in about 36 s.
        for _ in 0..<8 { app.buttons["speed-step-10"].tap() }
        snapshot("2-setup")

        app.buttons["start"].tap()
        sleep(1)
        snapshot("3-countdown")

        XCTAssertTrue(app.buttons["pause-resume"].waitForExistence(timeout: 6))
        sleep(4)
        snapshot("4-running")

        sleep(24)  // into the 10 s warning window before the 200 m change
        snapshot("5-warning")

        sleep(9)  // just after the change
        snapshot("6-change")

        app.buttons["pause-resume"].tap()
        snapshot("7-paused")
        app.buttons["overlay-resume"].tap()

        app.buttons["end"].tap()
        snapshot("8-end-confirmation")
        // The confirmation's End button, not the run screen's.
        app.buttons.matching(NSPredicate(format: "label == 'End' AND identifier != 'end'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 5))
        snapshot("9-summary")
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
