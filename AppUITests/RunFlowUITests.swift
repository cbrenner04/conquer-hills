import XCTest

/// Walks through the course screens and a Test Hills run in the simulator, saving a screenshot at each step for
/// review. Local only (not part of `make check`): run with `make ui-test`.
@MainActor
final class RunFlowUITests: XCTestCase {
    func testCoursesAndRun() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-silentSpeech"]  // no spoken prompts through the Mac's speakers
        app.launch()
        snapshot("01-course-list")

        // About and data credits.
        app.buttons["about"].tap()
        XCTAssertTrue(
            app.staticTexts["Data credits"].waitForExistence(timeout: 5) || app.staticTexts["DATA CREDITS"].exists)
        snapshot("02-about")
        app.navigationBars.buttons.firstMatch.tap()

        // Boston: the course screen, then Newton Hills, then a custom segment.
        app.staticTexts["Boston Marathon"].tap()
        XCTAssertTrue(app.buttons["segment-full-course"].waitForExistence(timeout: 5))
        snapshot("03-course-boston")

        scrollTo(app.buttons["segment-newton-hills"], in: app)
        app.buttons["segment-newton-hills"].tap()
        scrollToTop(app)
        snapshot("04-course-newton-hills")

        scrollTo(app.buttons["segment-custom"], in: app)
        app.buttons["segment-custom"].tap()
        let startLater = app.buttons["custom-start-10"]
        scrollTo(startLater, in: app)
        startLater.tap()
        app.buttons["custom-end--1"].tap()
        snapshot("05-course-custom")
        scrollToTop(app)
        snapshot("05b-course-custom-chart")

        scrollTo(app.buttons["start"], in: app)
        snapshot("06-course-preview")
        app.navigationBars.buttons.firstMatch.tap()

        // Test Hills run at top speed, so the first change (200 m) comes in about 36 s.
        app.staticTexts["Test Hills"].tap()
        scrollTo(app.buttons["speed-step-10"], in: app)
        for _ in 0..<8 { app.buttons["speed-step-10"].tap() }
        scrollTo(app.buttons["start"], in: app)
        snapshot("07-setup")

        app.buttons["start"].tap()
        sleep(1)
        snapshot("08-countdown")

        XCTAssertTrue(app.buttons["pause-resume"].waitForExistence(timeout: 6))
        sleep(4)
        snapshot("09-running")

        sleep(24)  // into the 10 s warning window before the 200 m change
        snapshot("10-warning")

        sleep(9)  // just after the change
        snapshot("11-change")

        app.buttons["pause-resume"].tap()
        snapshot("12-paused")
        app.buttons["overlay-resume"].tap()
        sleep(28)  // past a minute of running, so the run is saved to history

        app.buttons["end"].tap()
        snapshot("13-end-confirmation")
        // The confirmation's End button, not the run screen's.
        app.buttons.matching(NSPredicate(format: "label == 'End' AND identifier != 'end'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Saved to history"].exists)
        snapshot("14-summary")

        app.buttons["done"].tap()
        app.buttons["history"].tap()
        let run = app.buttons["history-run"].firstMatch
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        snapshot("15-history")

        run.tap()
        XCTAssertTrue(app.staticTexts["Incline"].waitForExistence(timeout: 5))
        snapshot("16-run-detail")
    }

    /// Swipes up until `element` is on screen and tappable (forms load rows lazily).
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "Couldn't scroll to \(element)")
    }

    private func scrollToTop(_ app: XCUIApplication) {
        for _ in 0..<4 { app.swipeDown() }
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
