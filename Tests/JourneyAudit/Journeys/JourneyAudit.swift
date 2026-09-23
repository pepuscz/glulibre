import XCTest

/// Uses only simulator synthetic data. No sensor activation, purchases or real API requests.
final class JourneyAudit: XCTestCase {
    let app = XCUIApplication(bundleIdentifier: "com.652PWHFDA9.libredebug")

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--journal-ui-testing", "--food-preview", "--journal-health-demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
    }

    func capture(_ name: String) {
        // UIKit sheet animations can outlive an accessibility snapshot becoming available.
        Thread.sleep(forTimeInterval: 0.7)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-elements"; tree.lifetime = .keepAlways; add(tree)
    }

    @discardableResult func tap(_ label: String, scroll: Bool = false) -> Bool {
        for _ in 0..<(scroll ? 6 : 1) {
            let elements = [app.buttons[label].firstMatch, app.staticTexts[label].firstMatch]
            if let element = elements.first(where: { $0.exists && $0.isHittable }) { element.tap(); return true }
            if scroll { app.swipeUp() }
        }
        capture("missing-" + label)
        return false
    }

    func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }

    func testOfflineLicensesRemainAvailable() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(tap("About & licenses", scroll: true))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "GluLibre")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Source code"].exists)
        XCTAssertTrue(app.buttons["Upstream xDrip4iOS"].exists)
        XCTAssertFalse(app.debugDescription.contains("Libre Debug"))
        capture("about-licenses")
        XCTAssertTrue(tap("GNU GPL v3", scroll: true))
        let text = app.staticTexts["journal.legal.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.label.contains("GNU GENERAL PUBLIC LICENSE"))
        XCTAssertTrue(text.label.contains("Version 3, 29 June 2007"))
        back()
        XCTAssertTrue(tap("Third-party notices", scroll: true))
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        for name in ["ActionClosurable", "CryptoSwift", "PieCharts", "SwiftCharts", "Icons8"] {
            XCTAssertTrue(text.label.contains(name))
        }
        XCTAssertFalse(text.label.contains("missing from this build"))
    }

    func testTodayChartIsVisibleWithoutScrolling() {
        func verifyLanding(_ name: String) {
            let plot = app.otherElements["journal.chart.plot"]
            let captureButton = app.buttons["journal.capture"]
            XCTAssertTrue(plot.waitForExistence(timeout: 10))
            XCTAssertGreaterThan(plot.frame.height, 200)
            XCTAssertLessThan(plot.frame.maxY, app.tabBars.firstMatch.frame.minY)
            XCTAssertTrue(captureButton.isHittable)
            XCTAssertLessThan(captureButton.frame.maxY, app.tabBars.firstMatch.frame.minY)
            XCTAssertFalse(app.staticTexts["Latest glucose"].exists)
            XCTAssertFalse(app.staticTexts["Touch and drag to inspect"].exists)
            capture(name)
        }
        // Existing food fixture intentionally has a gap at the end. Keep that unambiguous.
        XCTAssertTrue(app.staticTexts["Past reading"].exists)
        verifyLanding("today-stale-chart-first")
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo", "--journal-health-demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Past reading"].exists)
        XCTAssertFalse(app.staticTexts["Updated just now"].exists)
        verifyLanding("today-fresh-chart-first")
        XCTAssertTrue(tap("Log a meal"))
        XCTAssertTrue(app.buttons["Close camera"].waitForExistence(timeout: 5))
        app.buttons["Close camera"].tap()
    }

    func testEditableMealModelPersistsWithoutAPIRequest() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(tap("Meal analysis", scroll: true))
        let field = app.textFields["journal.ai.model"]
        let save = app.buttons["journal.ai.saveModel"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let original = field.value as? String ?? ""
        XCTAssertFalse(original.isEmpty)
        XCTAssertFalse(save.isEnabled)

        func replace(_ value: String) {
            field.tap()
            let existing = field.value as? String ?? ""
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count) + value)
        }
        replace(" ")
        XCTAssertFalse(save.isEnabled)
        // An arbitrary future ID must survive save/relaunch without a hardcoded allowlist.
        replace("  future-meal-vision-test  ")
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertEqual(field.value as? String, "future-meal-vision-test")
        XCTAssertTrue(app.staticTexts["Model saved"].waitForExistence(timeout: 3))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(tap("Meal analysis", scroll: true))
        XCTAssertEqual(field.value as? String, "future-meal-vision-test")
        replace(original)
        save.tap()
        XCTAssertEqual(field.value as? String, original)
        capture("editable-meal-model")
    }

    func testLandscapeKeepsJournalAndChartSelection() {
        defer { XCUIDevice.shared.orientation = .portrait }
        app.terminate()
        app.launchArguments += ["--journal-rotation-testing"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 15))
        XCTAssertTrue(tap("12h", scroll: true))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["journal.today.landscape"].waitForExistence(timeout: 10))
        capture("landscape-left-today")
        XCTAssertTrue(app.buttons["12h"].isSelected)
        XCTAssertFalse(app.buttons["Log a meal"].exists)
        XCTAssertFalse(app.staticTexts["Your journal"].exists)
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.otherElements["journal.today.landscape"].waitForExistence(timeout: 10))
        capture("landscape-right-today")
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(tap("Sensor", scroll: true))
        capture("landscape-sensor")
        back()
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.otherElements["journal.today.landscape"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(app.buttons["journal.capture"].waitForExistence(timeout: 5))
        capture("portrait-after-landscape")
        XCTAssertFalse(app.otherElements["journal.today.landscape"].exists)
        XCTAssertTrue(app.buttons["12h"].isSelected)
        XCTAssertTrue(tap("Log a meal", scroll: true))
        XCTAssertTrue(app.buttons["Close camera"].waitForExistence(timeout: 5))
        app.buttons["Close camera"].tap()
    }

    func testLandscapeColdLaunchAndTabs() {
        defer { XCUIDevice.shared.orientation = .portrait }
        app.terminate()
        XCUIDevice.shared.orientation = .landscapeRight
        app.launchArguments += ["--journal-rotation-testing"]
        app.launch()
        XCTAssertTrue(app.otherElements["journal.today.landscape"].waitForExistence(timeout: 15))
        capture("landscape-cold-launch")
        for title in ["Journal", "Insights", "Settings", "Today"] {
            app.tabBars.buttons[title].tap()
            capture("landscape-tab-" + title)
        }
        XCTAssertFalse(app.buttons["Log a meal"].exists)
        XCTAssertTrue(app.otherElements["journal.today.landscape"].exists)
    }

    func testChartInspectionAndLandscapeFocus() {
        defer { XCUIDevice.shared.orientation = .portrait }
        app.terminate()
        app.launchArguments += ["--journal-rotation-testing"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.otherElements["journal.today.landscape"].waitForExistence(timeout: 15))
        XCTAssertTrue(tap("6h"))
        let plot = app.otherElements["journal.chart.plot"]
        XCTAssertTrue(plot.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Touch and drag to inspect"].exists)
        XCTAssertFalse(app.staticTexts["journal.chart.readout"].exists)
        XCTAssertGreaterThan(plot.frame.width, app.frame.width * 0.65)
        XCTAssertGreaterThan(plot.frame.height, 150)
        // The simulator fixture has a real reading exactly 2 hours before now.
        plot.coordinate(withNormalizedOffset: CGVector(dx: 2.0 / 3.0, dy: 0.5)).tap()
        let readout = app.staticTexts["journal.chart.readout"]
        XCTAssertFalse(readout.label.contains("No reading"))
        XCTAssertTrue(readout.label.contains("mg/dL") || readout.label.contains("mmol"))
        let first = readout.label
        plot.coordinate(withNormalizedOffset: CGVector(dx: 2.0 / 3.0, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: plot.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertNotEqual(readout.label, first)
        capture("chart-crosshairs-landscape")
        // Empty tail of the same fixture: do not invent a current reading.
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        XCTAssertTrue(readout.label.contains("No reading"))
        capture("chart-missing-reading")
        XCTAssertTrue(tap("Clear selected reading"))
        XCTAssertFalse(readout.exists)
        XCUIDevice.shared.orientation = .portrait
        app.swipeUp() // Bring the whole plot above the floating tab bar before inspecting it.
        XCTAssertTrue(tap("6h", scroll: true))
        XCTAssertTrue(app.otherElements["journal.chart.plot"].exists)
        app.otherElements["journal.chart.plot"].coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Clear selected reading"].exists)
        capture("chart-crosshairs-portrait")
        let portraitPlot = app.otherElements["journal.chart.plot"]
        let originalY = portraitPlot.frame.minY
        // Scroll back toward the top: the preceding swipe may already be at the
        // bottom of the page, where another upward drag cannot move the content.
        portraitPlot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: portraitPlot.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.3)))
        XCTAssertGreaterThan(portraitPlot.frame.minY, originalY + 20, "Chart inspection must not block vertical page scrolling")
    }

    func testTodayAndCapture() {
        capture("01-today")
        XCTAssertTrue(tap("Log a meal", scroll: true))
        capture("02-camera")
        XCTAssertTrue(tap("Choose a photo"))
        let systemClose = app.buttons.matching(NSPredicate(format: "label == 'Close' OR label == 'Cancel'")).firstMatch
        XCTAssertTrue(systemClose.waitForExistence(timeout: 25))
        capture("02b-photo-library")
        systemClose.tap()
        capture("02c-after-system-close")
        // The system picker can first dismiss its own introductory/privacy overlay.
        if !app.buttons["Close camera"].isHittable, app.buttons["Close"].firstMatch.isHittable {
            app.buttons["Close"].firstMatch.tap()
        }
        let cameraVisible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["Close camera"])
        XCTAssertEqual(XCTWaiter.wait(for: [cameraVisible], timeout: 10), .completed)
        XCTAssertTrue(tap("Close camera") || tap("close"))
        app.tabBars.buttons["Journal"].tap()
        capture("03-journal")
        XCTAssertTrue(tap("Banana", scroll: true))
        capture("04-meal-detail")
        app.swipeUp()
        capture("05-meal-detail-bottom")
    }

    func testFoodComparisons() {
        app.tabBars.buttons["Insights"].tap()
        capture("10-food-library")
        XCTAssertTrue(tap("Banana"))
        capture("11-food-detail")
        XCTAssertTrue(tap("Compare meals", scroll: true))
        capture("12-comparison-picker")
        XCTAssertTrue(tap("Banana & plain yogurt"))
        capture("13-comparison")
        app.swipeUp(); capture("14-comparison-bottom")
    }

    func testActivityAndReadingInformation() {
        app.tabBars.buttons["Insights"].tap()
        XCTAssertTrue(tap("Activity"))
        capture("20-activity")
        XCTAssertTrue(tap("Sample run"))
        capture("21-workout")
        back()
        XCTAssertTrue(tap("About your readings", scroll: true))
        capture("22-reading-information")
    }

    func testSettingsInventory() {
        app.tabBars.buttons["Settings"].tap()
        capture("30-settings")
        // The initial audit records labels before hard-coding deeper journeys.
        app.swipeUp(); capture("31-settings-bottom")
    }

    func testEveryEverydaySettingsDestination() {
        app.tabBars.buttons["Settings"].tap()
        for (index, label) in ["Sensor", "Notifications", "Apple Watch", "Apple Health", "Meal analysis", "Privacy & data", "Other connections", "Saved records", "Help & sensor care"].enumerated() {
            app.swipeDown()
            XCTAssertTrue(tap(label, scroll: true), label)
            capture("40-\(index)-\(label)")
            if label == "Notifications" {
                XCTAssertTrue(tap("Customize alarms", scroll: true))
                capture("41-alarm-customization")
                XCTAssertTrue(app.navigationBars["Alarms"].exists)
                capture("41b-native-alarms")
                back()
            }
            if label == "Meal analysis" {
                XCTAssertTrue(tap("Add OpenAI API key"))
                capture("42-key-entry")
                XCTAssertFalse(app.buttons["Save"].firstMatch.isEnabled)
                XCTAssertTrue(tap("Cancel"))
                XCTAssertTrue(tap("Model & key management", scroll: true))
                capture("43-analysis-advanced")
            }
            app.swipeUp(); capture("44-\(label)-bottom")
            back()
        }
    }

    func testAdvancedDestinationsReadOnly() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertFalse(app.buttons["Advanced"].exists)
        XCTAssertTrue(tap("Other connections", scroll: true))
        for label in ["Nightscout", "Dexcom Share", "Spoken readings", "Calendar", "Contact image", "Reading source"] {
            XCTAssertTrue(tap(label, scroll: true))
            capture("50-\(label)")
            app.swipeUp(); capture("51-\(label)-bottom")
            back()
        }
        back()
        XCTAssertFalse(app.buttons["Classic dashboard"].exists)
    }

    func testChartControlsAndSensorStatus() {
        XCTAssertTrue(tap("Check sensor"))
        capture("60-delayed-sensor")
        XCTAssertTrue(tap("Done"))
        XCTAssertTrue(tap("Chart options", scroll: true))
        capture("61-chart-options")
        XCTAssertTrue(tap("About readings"))
        capture("62-chart-reference-information")
    }

    func testMealCorrectionAndSavedCapture() {
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo", "--journal-meal"]
        app.launch()
        XCTAssertTrue(app.buttons["Edit meal"].waitForExistence(timeout: 20))
        XCTAssertTrue(tap("Edit meal"))
        capture("70-edit-meal")
        XCTAssertTrue(tap("Add food", scroll: true))
        let name = app.descendants(matching: .any).matching(identifier: "Food name").allElementsBoundByIndex.last!
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Audit oats")
        let portion = app.descendants(matching: .any).matching(identifier: "Food portion").allElementsBoundByIndex.last!
        portion.tap(); portion.typeText("1 bowl")
        app.buttons["meal.edit.save"].tap()
        XCTAssertTrue(app.buttons["Edit meal"].waitForExistence(timeout: 5))
        XCTAssertTrue(tap("Edit meal"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "Food name").allElementsBoundByIndex.contains { $0.value as? String == "Audit oats" })
        capture("71-edit-persisted")
        XCTAssertTrue(tap("Cancel"))
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-quick-preview"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Saved"].waitForExistence(timeout: 20))
        capture("72-saved-photo-time")
        XCTAssertTrue(app.datePickers["Eating time"].exists)
        app.textViews["Optional meal note"].tap(); app.textViews["Optional meal note"].typeText(" UI audit note")
        capture("73-saved-note-keyboard")
        XCTAssertTrue(tap("Done"))
    }

    func testEmptyJourneys() {
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-empty", "--journal-health-demo"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20))
        capture("80-empty-today")
        app.tabBars.buttons["Journal"].tap()
        capture("81-empty-journal")
        XCTAssertTrue(tap("Log your first meal"))
        XCTAssertTrue(tap("Close camera"))
        app.tabBars.buttons["Insights"].tap()
        capture("82-empty-foods")
        XCTAssertTrue(tap("Log a meal"))
        XCTAssertTrue(tap("Close camera"))
        XCTAssertTrue(tap("Activity"))
        capture("83-empty-activity")
        XCTAssertTrue(tap("Health access", scroll: true))
        capture("84-health-recovery")
    }

    func testNutritionReviewRemainsAvailable() {
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo", "--journal-meal"]
        app.launch()
        XCTAssertTrue(app.buttons["Edit meal"].waitForExistence(timeout: 20))
        XCTAssertTrue(tap("Nutrition & Apple Health", scroll: true))
        XCTAssertTrue(tap("Review nutrition & Health", scroll: true))
        capture("90-nutrition-review")
        app.swipeUp(); capture("91-nutrition-review-bottom")
        // Do not confirm an estimate or write synthetic food into Apple Health.
    }

    func testLegacyReadOnlySubscreens() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(tap("Sensor"))
        XCTAssertTrue(tap("Set up a sensor", scroll: true) || tap("Replace or finish sensor setup", scroll: true))
        capture("95-native-sensor-setup")
        XCTAssertTrue(tap("Start a new sensor", scroll: true))
        capture("96-new-sensor-confirmation")
        XCTAssertTrue(tap("Cancel"))
        back(); back()
        XCTAssertTrue(tap("Notifications", scroll: true))
        XCTAssertTrue(tap("Customize alarms", scroll: true))
        XCTAssertTrue(tap("Low Alarm", scroll: true))
        capture("97-native-alarm-periods")
        XCTAssertTrue(tap("From midnight", scroll: true))
        capture("98-native-alarm-editor")
        XCTAssertTrue(app.textFields["alarm.threshold"].exists)
        back()
        XCTAssertTrue(tap("Add period"))
        capture("98b-add-alarm-period")
        XCTAssertTrue(tap("Cancel"))
        back(); back(); back()
        XCTAssertTrue(tap("Privacy & data", scroll: true))
        XCTAssertTrue(tap("Storage & export", scroll: true))
        capture("99-storage")
        XCTAssertTrue(tap("Keep glucose history"))
        capture("99b-retention")
        XCTAssertTrue(tap("Cancel"))
    }

    func testAccessibilityLayouts() {
        capture("100-accessibility-today")
        app.tabBars.buttons["Insights"].tap()
        capture("101-accessibility-foods")
        XCTAssertTrue(tap("Banana", scroll: true))
        capture("102-accessibility-food-detail")
        XCTAssertTrue(tap("Compare meals", scroll: true))
        capture("103-accessibility-picker")
        XCTAssertTrue(tap("Banana & plain yogurt", scroll: true))
        capture("104-accessibility-comparison")
        app.swipeUp(); capture("105-accessibility-comparison-bottom")
    }

    func testAlarmTapOpensTodayWithoutSnoozePicker() {
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo", "--journal-alarm-response"]
        app.launch()
        XCTAssertTrue(app.otherElements["journal.chart.plot"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.buttons["Today"].isSelected)
        XCTAssertFalse(app.staticTexts["Select Snooze Time"].exists)
        XCTAssertFalse(app.navigationBars["Low Alarm"].exists)
        XCTAssertTrue(app.tabBars.buttons["Today"].isHittable)
        capture("110-alarm-opens-chart")
    }

    func testMultiCourseMealKeepsObservedCurveWithOverlap() {
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--food-preview", "--food-occasions", "--food-occasion-detail"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Meal"].waitForExistence(timeout: 20))
        func reveal(_ label: String) {
            for _ in 0..<8 {
                if app.staticTexts[label].firstMatch.exists && app.staticTexts[label].firstMatch.isHittable { return }
                app.swipeUp()
            }
        }
        reveal("Together at this meal")
        XCTAssertTrue(app.staticTexts["Together at this meal"].exists)
        XCTAssertTrue(app.staticTexts["Toast course"].exists)
        capture("meal-occasion-courses")
        reveal("Observed peak")
        XCTAssertTrue(app.staticTexts["Observed peak"].exists)
        XCTAssertTrue(app.staticTexts["Overlapping meals"].exists)
        XCTAssertFalse(app.staticTexts["Another logged meal overlaps this window. The response cannot be separated."].exists)
        capture("meal-occasion-observed-overlap")
    }

    func testForegroundAlarmDoesNotInterruptMealCapture() {
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo", "--journal-alarm-foreground"]
        app.launch()
        XCTAssertTrue(app.buttons["Close camera"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Close camera"].isHittable)
        XCTAssertFalse(app.staticTexts["Select Snooze Time"].exists)
        XCTAssertFalse(app.navigationBars["Low Alarm"].exists)
        capture("111-alarm-keeps-camera-usable")
        app.buttons["Close camera"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].isHittable)
    }

    func testWatchSettingsAreDirectAndPreserveChoice() {
        // Simulator-only reset: tests never modify a physical phone or Watch.
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo", "--journal-watch-default"]
        app.launch()
        func openWatchSettings() {
            XCTAssertTrue(app.tabBars.buttons["Settings"].waitForExistence(timeout: 15))
            app.tabBars.buttons["Settings"].tap()
            XCTAssertTrue(app.buttons["settings.watch"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["settings.watch"].isHittable)
            app.buttons["settings.watch"].tap()
            XCTAssertTrue(app.navigationBars["Apple Watch"].waitForExistence(timeout: 5))
        }
        func toggle(_ control: XCUIElement) {
            let thumb = control.switches.firstMatch
            if thumb.exists { thumb.tap() } else { control.tap() }
        }
        openWatchSettings()
        let control = app.switches["watch.readings"]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertEqual(control.value as? String, "1")
        capture("111-watch-default-on")
        toggle(control)
        XCTAssertEqual(control.value as? String, "0")
        XCTAssertFalse(app.buttons["Cancel"].exists)
        app.terminate()
        app.launchArguments = ["--journal-ui-testing", "--journal-demo"]
        app.launch()
        openWatchSettings()
        XCTAssertEqual(control.value as? String, "0", "An explicit off choice must survive relaunch")
        capture("112-watch-off-preserved")
        toggle(control)
        XCTAssertEqual(control.value as? String, "1")
        XCTAssertFalse(app.buttons["Cancel"].exists)
        capture("113-watch-enabled")
    }
}
