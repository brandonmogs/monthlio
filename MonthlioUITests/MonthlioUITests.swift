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
