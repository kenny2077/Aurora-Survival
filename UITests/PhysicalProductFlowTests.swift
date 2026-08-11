import XCTest

final class PhysicalProductFlowTests: XCTestCase {
    private let catalogURL = "http://192.168.3.51:8765/catalog.json"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFourTabShellAndFocusedModelCenter() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        for tab in ["Ask", "Manual", "Maps", "Tools"] {
            XCTAssertTrue(tabButton(tab, in: app).exists)
        }
        XCTAssertTrue(
            app.descendants(matching: .any)["chat.modelRequired"]
                .waitForExistence(timeout: 20)
        )
        XCTAssertFalse(app.buttons["Emergency"].exists)
        XCTAssertFalse(app.buttons["Clear"].exists)

        openTools(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["tools.tier.lite"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["tools.tier.vision_expert"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["Validation pending"].exists)
        for retired in [
            "Offline readiness", "Trip sheet", "Vehicle profile",
            "Read-only OBD", "System status",
        ] {
            XCTAssertFalse(app.staticTexts[retired].exists)
        }
        keepScreenshot(named: "Four-tab focused model center", app: app)
    }

    func testModelRequiredActionOpensTools() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        let setup = app.buttons["Set up models"]
        XCTAssertTrue(setup.waitForExistence(timeout: 20))
        setup.tap()

        XCTAssertTrue(tabButton("Tools", in: app).isSelected)
        XCTAssertTrue(
            app.descendants(matching: .any)["tools.modelHero"]
                .waitForExistence(timeout: 10)
        )
    }

    func testManualCourseAndUnifiedReferenceRemainAvailableWithoutModel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        openManual(in: app)
        XCTAssertFalse(app.staticTexts["Start here"].exists)
        let chapter = app.staticTexts["Survival Basics"].firstMatch
        XCTAssertTrue(chapter.waitForExistence(timeout: 10))
        chapter.tap()
        let lesson = app.staticTexts["Stop and Control Panic"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()
        XCTAssertTrue(
            app.navigationBars["Stop and Control Panic"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Do this now"].exists)
        XCTAssertTrue(app.staticTexts["Critical warnings"].exists)

        app.terminate()
        app.launch()
        openManual(in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("water purifier boiling")
        let result = app.staticTexts["Boil Water Correctly"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        result.tap()
        XCTAssertTrue(
            app.navigationBars["Boil Water Correctly"]
                .waitForExistence(timeout: 20)
        )
    }

    func testMapsIsDirectFourthProductArea() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        openMaps(in: app)
        XCTAssertTrue(tabButton("Maps", in: app).isSelected)
        XCTAssertTrue(app.navigationBars["Offline Maps"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)["maps.home"]
                .waitForExistence(timeout: 10)
        )
        let setup = app.textFields["Signed catalog URL"]
        let manage = app.buttons["Manage map downloads"]
        XCTAssertTrue(setup.exists || manage.exists)
        keepScreenshot(named: "Dedicated Maps tab", app: app)
    }

    func testManualTenChaptersAndNoResultsAtLargestType() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launchArguments += [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        openManual(in: app)

        let chapters = [
            "Survival Basics", "Find and Treat Water", "Start a Fire",
            "Build a Shelter", "Find Food Safely", "Navigate When Lost",
            "Signal for Rescue", "Wilderness First Aid",
            "Weather and Wildlife", "Car Breakdown",
        ]
        for title in chapters {
            for _ in 0..<12 where !app.staticTexts[title].exists {
                app.swipeUp()
            }
            XCTAssertTrue(app.staticTexts[title].exists, "Missing chapter: \(title)")
        }

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("qxvplm zznort")
        XCTAssertTrue(
            app.descendants(matching: .any)["manual.search.no-results"]
                .waitForExistence(timeout: 10)
        )
        keepScreenshot(named: "Ten chapter Manual dark largest type", app: app)
    }

    func testModelCenterDarkModeAndLargestDynamicType() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launchArguments += [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        openTools(in: app)
        XCTAssertTrue(app.staticTexts["Offline intelligence"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Lite"].exists)
        for _ in 0..<5 where !app.staticTexts["Expert"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["Expert"].exists)
        keepScreenshot(named: "Model center dark largest type", app: app)
    }

    func testPhysicalInstalledLiteChatAndExactManualLink() throws {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textFields["chat.composer"]
        guard composer.waitForExistence(timeout: 30) else {
            throw XCTSkip("A validated Lite package is not installed on this destination.")
        }
        XCTAssertFalse(app.buttons["Attach photo"].exists)
        XCTAssertFalse(app.buttons["Emergency"].exists)
        XCTAssertFalse(app.buttons["Clear"].exists)
        XCTAssertFalse(app.staticTexts["Fully offline · Gemma + Field Manual"].exists)
        XCTAssertFalse(
            app.staticTexts["Manual context is used for relevant survival questions"].exists
        )

        composer.tap()
        composer.typeText("Where can I find water?")
        app.buttons["chat.send"].tap()
        let response = app.descendants(matching: .any)["chat.message.assistant"]
        XCTAssertTrue(response.waitForExistence(timeout: 180))
        XCTAssertTrue(response.staticTexts["Lite"].exists)
        let manualLink = response.buttons["chat.manual-link"]
        XCTAssertTrue(manualLink.waitForExistence(timeout: 10))
        let citedTitle = manualLink.staticTexts.firstMatch.label
        XCTAssertFalse(citedTitle.isEmpty)
        manualLink.tap()
        XCTAssertTrue(tabButton("Manual", in: app).isSelected)
        XCTAssertTrue(app.navigationBars[citedTitle].waitForExistence(timeout: 20))
        keepScreenshot(named: "Lite exact Manual link after redesign", app: app)
    }

    func testPhysicalLiteIncidentFallbackDoesNotReuseWaterContext() throws {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textFields["chat.composer"]
        guard composer.waitForExistence(timeout: 30) else {
            throw XCTSkip("A validated Lite package is not installed on this destination.")
        }
        composer.tap()
        composer.typeText("Where can I find water?")
        app.buttons["chat.send"].tap()
        let responses = app.descendants(matching: .any).matching(
            identifier: "chat.message.assistant"
        )
        XCTAssertTrue(responses.firstMatch.waitForExistence(timeout: 180))

        composer.tap()
        composer.typeText("How are you doing?")
        app.buttons["chat.send"].tap()
        let second = responses.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 180))
        XCTAssertFalse(second.buttons["chat.manual-link"].exists)
        let fallbackWords = second.staticTexts["chat.answer"].label
            .split(whereSeparator: \.isWhitespace).count
        XCTAssertTrue((24...75).contains(fallbackWords))
        for leaked in [
            "Do not invent steps",
            "citation markers",
            "Lite couldn’t run right now",
        ] {
            XCTAssertFalse(second.staticTexts.matching(NSPredicate(
                format: "label CONTAINS[c] %@", leaked
            )).firstMatch.exists)
        }
        keepScreenshot(named: "Lite stateless incident fallback", app: app)
    }

    func testPhysicalLiteDatabaseFirstGroundedAndFallbackCases() throws {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textFields["chat.composer"]
        guard composer.waitForExistence(timeout: 30) else {
            throw XCTSkip("A validated 160-token Lite package is not installed.")
        }
        let responses = app.descendants(matching: .any).matching(
            identifier: "chat.message.assistant"
        )
        for question in [
            "Flat tire",
            "How to stop the bleed",
            "Where can I find water?",
            "I am lost on a trail. What should I do?",
            "A bear is nearby. What should I do?",
        ] {
            let index = responses.count
            composer.tap()
            composer.typeText(question)
            app.buttons["chat.send"].tap()
            let response = responses.element(boundBy: index)
            XCTAssertTrue(response.waitForExistence(timeout: 180), question)
            let text = response.staticTexts["chat.answer"].label
            let words = text.split(whereSeparator: \.isWhitespace).count
            XCTAssertTrue((22...70).contains(words), "\(question): \(text)")
            XCTAssertTrue(
                response.buttons["chat.manual-link"].waitForExistence(timeout: 10),
                question
            )
        }

        for question in [
            "Hi",
            "How to fix my car",
            "I’m drunk",
            "I dropped my phone",
            "I feel anxious",
        ] {
            let index = responses.count
            composer.tap()
            composer.typeText(question)
            app.buttons["chat.send"].tap()
            let response = responses.element(boundBy: index)
            XCTAssertTrue(response.waitForExistence(timeout: 180), question)
            let text = response.staticTexts["chat.answer"].label
            let words = text.split(whereSeparator: \.isWhitespace).count
            XCTAssertTrue((24...75).contains(words), "\(question): \(text)")
            XCTAssertFalse(response.buttons["chat.manual-link"].exists, question)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("REVIEWED EXCERPT"))
            if question == "I’m drunk" {
                XCTAssertFalse(text.localizedCaseInsensitiveContains("I’m feeling"))
            }
            if question == "How to fix my car" {
                XCTAssertFalse(text.localizedCaseInsensitiveContains("snow"))
            }
        }
        keepScreenshot(named: "Lite database-first grounded and fallback", app: app)
    }

    func testPhysicalLiteGenericCarRequestUsesIncidentFallback() throws {
        let app = XCUIApplication()
        app.launch()

        let composer = app.textFields["chat.composer"]
        guard composer.waitForExistence(timeout: 30) else {
            throw XCTSkip("A validated 160-token Lite package is not installed.")
        }
        composer.tap()
        composer.typeText("How to fix my car")
        app.buttons["chat.send"].tap()
        let response = app.descendants(matching: .any)["chat.message.assistant"]
        XCTAssertTrue(response.waitForExistence(timeout: 180))
        let text = response.staticTexts["chat.answer"].label
        XCTAssertTrue((24...75).contains(text.split(whereSeparator: \.isWhitespace).count), text)
        XCTAssertFalse(response.buttons["chat.manual-link"].exists)
        XCTAssertFalse(text.localizedCaseInsensitiveContains("snow"))
    }

    func testPreparedCatalogSeparatesModelsAndMaps() throws {
        let app = launchPreparedApp()
        openTools(in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["tools.tier.lite"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.staticTexts["Offline maps"].exists)

        openMaps(in: app)
        XCTAssertTrue(app.navigationBars["Offline Maps"].waitForExistence(timeout: 20))
        keepScreenshot(named: "Separated model and map downloads", app: app)
    }

    func testPhysicalInstallLatestLiteFromPreparedCatalog() throws {
        let app = launchPreparedApp()
        let download = app.buttons["Download Lite"]
        if download.waitForExistence(timeout: 10) {
            download.tap()
        }
        XCTAssertTrue(
            app.buttons["Use Lite"].waitForExistence(timeout: 900),
            "The signed Lite package did not finish installing."
        )
    }

    private func launchPreparedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_CATALOG_URL"] = catalogURL
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()
        openTools(in: app)

        let access = app.buttons["Download access"]
        XCTAssertTrue(access.waitForExistence(timeout: 10))
        access.tap()
        let mode = app.switches["download.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        if mode.value as? String != "1" {
            mode.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let verify = app.buttons["catalog.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: 10))
        verify.tap()
        let status = app.staticTexts["catalog.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 30))
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Verified catalog"),
            evaluatedWith: status
        )
        waitForExpectations(timeout: 30)
        return app
    }

    private func openManual(in app: XCUIApplication) {
        let tab = tabButton("Manual", in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        XCTAssertTrue(
            app.staticTexts["Wilderness Survival"]
                .waitForExistence(timeout: 20)
        )
    }

    private func openMaps(in app: XCUIApplication) {
        let tab = tabButton("Maps", in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    private func openTools(in app: XCUIApplication) {
        let tab = tabButton("Tools", in: app)
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
    }

    private func keepScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tabButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let phoneTab = app.tabBars.buttons[label]
        return phoneTab.exists ? phoneTab : app.buttons[label].firstMatch
    }
}
