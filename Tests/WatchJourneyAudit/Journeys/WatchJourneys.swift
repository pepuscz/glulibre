import XCTest

final class WatchJourneys: XCTestCase {
    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-tree"; tree.lifetime = .keepAlways; add(tree)
    }
    func testNowMealAndConnection() {
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
        for _ in 0..<4 {
            if app.buttons["watch.refresh"].isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["watch.refresh"].waitForExistence(timeout: 5))
        capture("Connection", app: app)
        app.buttons["watch.refresh"].tap()
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
                XCTAssertTrue(app.staticTexts["Open GluLibre on your iPhone. Your sensor stays connected there."].exists)
            }
            capture(name, app: app)
            if name == "Stale" || name == "Empty" { XCTAssertEqual(app.staticTexts["watch.glucose"].label, "—") }
            app.terminate()
        }
    }

    func testLargeTextAndPrivacy() {
        let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug.watchkitapp")
        for page in ["", "--watch-meal", "--watch-connection"] {
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
            if page == "--watch-connection" {
                for _ in 0..<4 {
                    if app.buttons["watch.refresh"].isHittable { break }
                    app.swipeUp()
                }
                XCTAssertTrue(app.buttons["watch.refresh"].isHittable)
                app.buttons["watch.refresh"].tap()
            }
            app.terminate()
        }
        app.launchArguments = ["--watch-demo", "--watch-dimmed"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Raise wrist to view"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["watch.glucose"].exists)
        capture("Privacy-redacted", app: app)
    }
}
