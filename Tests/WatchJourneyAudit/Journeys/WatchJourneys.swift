import XCTest

final class WatchJourneys: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Synthetic Watch journeys must never run on a physical device")
        #endif
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testNowAndMealWithoutConnectionPage() {
        let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug.watchkitapp")
        app.launchArguments = ["--watch-demo"]
        app.launch()
        XCTAssertTrue(app.staticTexts["watch.glucose"].waitForExistence(timeout: 10))
        capture("Now", app: app)
        for _ in 0..<4 {
            if app.staticTexts["Avocado toast"].isHittable { break }
            app.swipeUp()
        }
        capture("After-swiping-to-food", app: app)
        XCTAssertTrue(app.staticTexts["Avocado toast"].isHittable)
        for _ in 0..<3 { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["watch.meal.date"].isHittable)
        XCTAssertFalse(app.buttons["watch.refresh"].exists)
        XCTAssertFalse(app.staticTexts["Connection"].exists)
        capture("Last-page-is-meal", app: app)
        for _ in 0..<4 {
            if app.staticTexts["watch.glucose"].isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(app.staticTexts["watch.glucose"].isHittable)
    }

    func testDigitalCrownScrollsMealAndReturnsToGlucose() {
        let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug.watchkitapp")
        for (name, flags) in [("Standard", [String]()), ("Large-long-meal", ["--watch-large", "--watch-long-meal"])] {
            app.launchArguments = ["--watch-demo"] + flags
            app.launch()
            let reading = app.staticTexts["watch.glucose"]
            capture("Crown-start-" + name, app: app)
            XCTAssertTrue(reading.waitForExistence(timeout: 10))
            XCTAssertTrue(reading.isHittable)
            let mealEnd = app.staticTexts["watch.meal.date"]
            // Native Crown events, no taps/swipes/focus workaround before scrolling.
            for _ in 0..<12 {
                if mealEnd.exists && mealEnd.isHittable { break }
                XCUIDevice.shared.rotateDigitalCrown(delta: 0.3, velocity: .slow)
            }
            XCTAssertTrue(mealEnd.isHittable, "Crown must reach the end of the meal, including long content")
            capture("Crown-meal-" + name, app: app)
            XCUIDevice.shared.rotateDigitalCrown(delta: 0.5, velocity: .slow)
            XCTAssertTrue(mealEnd.isHittable, "Further scrolling must stay at the last content page")
            XCTAssertFalse(app.buttons["watch.refresh"].exists)
            XCTAssertFalse(app.staticTexts["Connection"].exists)
            for _ in 0..<12 {
                if reading.exists && reading.isHittable { break }
                XCUIDevice.shared.rotateDigitalCrown(delta: -0.3, velocity: .slow)
            }
            XCTAssertTrue(reading.isHittable, "Reversing the Crown must return to glucose without a touch gesture")
            capture("Crown-glucose-" + name, app: app)
            app.terminate()
        }
    }

    func testChartIsReadableWithoutScrolling() {
        let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug.watchkitapp")
        for (name, flags) in [("Chart-mmol", [String]()), ("Chart-mgdl", ["--watch-mgdl"])] {
            app.launchArguments = ["--watch-demo"] + flags
            app.launch()
            let reading = app.staticTexts["watch.glucose"]
            XCTAssertTrue(reading.waitForExistence(timeout: 10))
            let chart = app.descendants(matching: .any)["watch.chart"].firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(chart.frame.height, 70)
            XCTAssertGreaterThanOrEqual(chart.frame.minY, reading.frame.maxY)
            XCTAssertLessThanOrEqual(chart.frame.maxY, app.frame.maxY - 12)
            XCTAssertTrue(chart.isHittable)
            XCTAssertTrue(app.staticTexts["watch.chart.end"].isHittable)
            capture(name, app: app)
            app.terminate()
        }
    }

    func testEmptyStaleAndMealStates() {
        let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug.watchkitapp")
        for (name, flags, label) in [
            ("Empty", ["--watch-empty"], "Waiting for iPhone"),
            ("Stale", ["--watch-stale"], "Reading out of date"),
            ("Meal", ["--watch-meal"], "Avocado toast"),
            ("Collecting", ["--watch-meal", "--watch-collecting"], "Avocado toast"),
            ("Limited", ["--watch-meal", "--watch-limited"], "Response unavailable"),
            ("mgdl", ["--watch-mgdl"], "mg/dL")
        ] {
            app.launchArguments = ["--watch-demo"] + flags
            app.launch()
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5))
            if name == "Empty" {
                XCTAssertTrue(app.staticTexts["Open GluLibre on iPhone."].exists)
            }
            capture(name, app: app)
            if name == "Stale" || name == "Empty" { XCTAssertEqual(app.staticTexts["watch.glucose"].label, "—") }
            app.terminate()
        }
    }

    func testLargeTextAndPrivacy() {
        let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug.watchkitapp")
        for page in ["", "--watch-meal"] {
            app.launchArguments = ["--watch-demo", "--watch-large", page]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
            if page.isEmpty {
                let reading = app.staticTexts["watch.glucose"]
                XCTAssertTrue(reading.waitForExistence(timeout: 5))
                XCTAssertTrue(reading.isHittable)
                XCTAssertGreaterThanOrEqual(reading.frame.height, 38)
            }
            capture("Large-" + page, app: app)
            app.terminate()
        }
        app.launchArguments = ["--watch-demo", "--watch-dimmed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Raise wrist to view"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["watch.glucose"].exists)
        capture("Privacy-redacted", app: app)
    }
}
