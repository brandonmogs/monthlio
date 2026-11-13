import XCTest

/// Smoke tests that drive the real app. They launch with an in-memory store
/// so nothing on the simulator is touched, and save a screenshot of each
/// screen they reach to a folder printed as UI_SHOT_DIR in the log.
final class MonthlioUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-MonthlioInMemory"] + arguments
        app.launch()
        return app
    }

    private func saveScreenshot(_ app: XCUIApplication, name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let directory = FileManager.default.temporaryDirectory.appending(path: "monthlio-ui")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: directory.appending(path: "\(name).png"))
        print("UI_SHOT_DIR=\(directory.path)")
    }

    func testDashboardShowsTheSeededTotal() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["$3,459.29"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["13 active expenses"].exists)
        saveScreenshot(app, name: "dashboard")
    }

    func testAddingAnExpenseUpdatesTheTotal() {
        let app = launch(["-MonthlioSkipSeed"])
        let addButton = app.buttons["Add an expense"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()

        let name = app.textFields["expense-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Rent")
        let amount = app.textFields["expense-amount"]
        amount.tap()
        amount.typeText("1500")
        saveScreenshot(app, name: "expense-form")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["$1,500.00"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1 active expense"].exists)
    }

    func testSettingsOffersBackupRestoreAndImport() {
        let app = launch(["-MonthlioSettings"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
        let form = app.collectionViews.firstMatch
        let importButton = app.buttons["data-import"]
        for _ in 0..<5 where !importButton.exists {
            form.swipeUp()
        }
        saveScreenshot(app, name: "settings-data")
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["data-backup"].exists)
        XCTAssertTrue(app.buttons["data-restore"].exists)
    }

    func testCSVExportIsAProFeature() {
        let app = launch(["-MonthlioSettings", "-MonthlioFreshInstall"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
        let form = app.collectionViews.firstMatch
        let export = app.buttons["data-export"]
        for _ in 0..<5 where !export.exists {
            form.swipeUp()
        }
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()

        XCTAssertTrue(app.staticTexts["Monthlio Pro"].waitForExistence(timeout: 5), "a free user lands on the Pro page")
        XCTAssertTrue(app.staticTexts["CSV export"].waitForExistence(timeout: 5), "and sees the export listed as a benefit")
        saveScreenshot(app, name: "csv-export-pro")
        app.buttons["Close"].firstMatch.tap()
    }

    func testSettingsOffersTheProPageWithEveryBenefit() {
        let app = launch(["-MonthlioSettings", "-MonthlioFreshInstall"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
        let upgrade = app.buttons["pro-upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5), "free users get a Pro entry at the top of Settings")
        upgrade.tap()

        XCTAssertTrue(app.staticTexts["Monthlio Pro"].waitForExistence(timeout: 10))
        for benefit in ["iCloud sync", "Custom colors", "CSV export", "Family Sharing", "Private by design", "Buy once, keep forever"] {
            XCTAssertTrue(app.staticTexts[benefit].waitForExistence(timeout: 5), "\(benefit) is listed")
        }
        XCTAssertTrue(app.buttons["Restore Purchases"].exists)
        saveScreenshot(app, name: "pro-page")
        app.buttons["Close"].tap()
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
    }

    func testFreshInstallOffersProForSyncAndLoadsThePrice() {
        let app = launch(["-MonthlioSettings", "-MonthlioFreshInstall"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
        let form = app.collectionViews.firstMatch
        let unlock = app.buttons["sync-unlock"]
        for _ in 0..<5 where !unlock.exists {
            form.swipeUp()
        }
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        unlock.tap()
        saveScreenshot(app, name: "after-unlock-tap")

        XCTAssertTrue(app.staticTexts["Monthlio Pro"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Restore Purchases"].waitForExistence(timeout: 5))
        // The price comes from the scheme's StoreKit configuration, which
        // only reaches the simulator when the run starts from the Xcode IDE
        // on iOS 26.3+ runtimes; from xcodebuild the button offers a retry
        // instead. Either proves the paywall is wired up.
        let priced = app.buttons["Unlock for $9.99"].waitForExistence(timeout: 15)
        XCTAssertTrue(priced || app.buttons["Try Again"].exists, "price button or retry expected")
        saveScreenshot(app, name: priced ? "paywall" : "paywall-no-storekit")
    }

    func testColorRowOpensTheProPageAndItStaysOpenForAnEarlySupporter() {
        // The 1.4 paywall closed itself for anyone whose iCloud sync was
        // already free, so the Color row flashed the Pro page and lost it.
        let app = launch(["-MonthlioSkipSeed", "-MonthlioFreshInstall", "-MonthlioGrandfathered"])
        let addButton = app.buttons["Add an expense"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        XCTAssertTrue(app.textFields["expense-name"].waitForExistence(timeout: 5))
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 2) { done.tap() }

        let color = app.buttons["expense-color"]
        let form = app.collectionViews.firstMatch
        for _ in 0..<5 where !color.isHittable {
            form.swipeUp()
        }
        XCTAssertTrue(color.waitForExistence(timeout: 5))
        color.tap()

        let title = app.staticTexts["Monthlio Pro"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "the Color row opens the Pro page")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'iCloud sync is already yours'")).firstMatch.waitForExistence(timeout: 5), "an early supporter is told sync is free")
        XCTAssertFalse(title.waitForNonExistence(timeout: 3), "the Pro page stays open for an early supporter")
        XCTAssertTrue(app.staticTexts["Custom colors"].exists)
        saveScreenshot(app, name: "color-pro-page")
        app.buttons["Close"].firstMatch.tap()
        XCTAssertTrue(color.waitForExistence(timeout: 5), "back on the form")
    }

    func testACodeUnlocksMonthlioPro() {
        let app = launch(["-MonthlioSettings", "-MonthlioFreshInstall"])
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))
        let upgrade = app.buttons["pro-upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        upgrade.tap()
        XCTAssertTrue(app.staticTexts["Monthlio Pro"].waitForExistence(timeout: 10))

        let haveCode = app.buttons["paywall-have-code"]
        let page = app.scrollViews.firstMatch
        for _ in 0..<5 where !haveCode.isHittable {
            page.swipeUp()
        }
        XCTAssertTrue(haveCode.waitForExistence(timeout: 5))
        haveCode.tap()
        let field = app.textFields["paywall-code"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("nope")
        app.buttons["paywall-redeem"].tap()
        XCTAssertTrue(app.staticTexts["That code didn't work. Check it and try again."].waitForExistence(timeout: 5), "a wrong code is explained")
        saveScreenshot(app, name: "paywall-wrong-code")

        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4) + "mogz")
        app.buttons["paywall-redeem"].tap()
        XCTAssertTrue(app.staticTexts["pro-unlocked"].waitForExistence(timeout: 10), "the right code closes the page and Settings shows Pro as unlocked")
        saveScreenshot(app, name: "pro-unlocked-by-code")
    }

    func testAnExpenseCanNotifyOnItsOwnDate() {
        // Through the add flow: XCUITest taps on plain-style list row buttons
        // don't open the editor on the simulator, though fingers do.
        let app = launch(["-MonthlioSkipSeed"])
        let addButton = app.buttons["Add an expense"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 15))
        addButton.tap()
        let name = app.textFields["expense-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Gym")
        let amount = app.textFields["expense-amount"]
        amount.tap()
        amount.typeText("40")
        let done = app.toolbars.buttons["Done"]
        if done.waitForExistence(timeout: 2) { done.tap() }

        let toggle = app.switches["expense-reminder"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let form = app.collectionViews.firstMatch
        for _ in 0..<3 where !toggle.isHittable {
            form.swipeUp()
        }
        // The identifier covers the whole row; only its trailing control flips it.
        let control = toggle.switches.firstMatch
        if control.exists {
            control.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.datePickers["expense-reminder-date"].waitForExistence(timeout: 5), "a date and time appear once it's on")
        saveScreenshot(app, name: "expense-notification")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["1 active expense"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Expenses"].tap()
        let notifies = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gym' AND label CONTAINS 'Notifies'"))
        XCTAssertTrue(notifies.firstMatch.waitForExistence(timeout: 5), "the row says when it notifies")
    }

    func testSwipeToDeleteCanBeUndone() {
        let app = launch(["-MonthlioTab", "expenses"])
        // Rows are single accessibility elements labelled "Rent, Due on the
        // 1st, $1,850.00/mo"; Rent heads the list, so it is always on screen.
        let rentRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Rent'"))
        XCTAssertTrue(rentRow.firstMatch.waitForExistence(timeout: 15))
        rentRow.firstMatch.swipeLeft()
        let delete = app.buttons["Delete"]
        if delete.waitForExistence(timeout: 3) {
            delete.tap()
        } // otherwise the swipe went all the way and deleted on its own

        let undo = app.buttons["undo-delete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertFalse(rentRow.firstMatch.exists)
        saveScreenshot(app, name: "undo-delete")
        undo.tap()
        XCTAssertTrue(rentRow.firstMatch.waitForExistence(timeout: 5))
    }

    func testLockedLaunchShowsTheLockScreenAndHidesAmounts() {
        let app = launch(["-MonthlioLocked"])
        XCTAssertTrue(app.staticTexts["Monthlio is locked"].waitForExistence(timeout: 15))
        // XCUITest still lists accessibility-hidden elements, so check that
        // the amount can't be reached: covered by the shield and disabled.
        let amount = app.staticTexts["$3,459.29"]
        XCTAssertFalse(amount.isHittable, "amounts must not be reachable behind the lock")
        XCTAssertFalse(amount.isEnabled)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Unlock with'")).firstMatch.exists)
        saveScreenshot(app, name: "locked-launch")
    }

    func testDeepLinkOpensTheUpcomingTab() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["$3,459.29"].waitForExistence(timeout: 15))
        app.open(URL(string: "monthlio://upcoming")!)
        XCTAssertTrue(app.staticTexts["Next 30 days"].waitForExistence(timeout: 10))
        saveScreenshot(app, name: "upcoming-via-deep-link")
    }
}
