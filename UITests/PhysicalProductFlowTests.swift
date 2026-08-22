import XCTest

final class PhysicalProductFlowTests: XCTestCase {
    private let catalogURL = "http://192.168.3.51:8765/catalog.json"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(acceptAgreement: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if acceptAgreement {
            app.launchEnvironment["TRAILGUARD_UI_ACCEPT_AGREEMENT"] = "1"
        }
        return app
    }

    func testRiskAcknowledgementRefusalAcceptanceAndPersistence() throws {
        let app = makeApp(acceptAgreement: false)
        app.launchEnvironment["TRAILGUARD_UI_RESET_AGREEMENT"] = "1"
        app.launch()

        let screen = app.descendants(matching: .any)["agreement.screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20))
        app.buttons["agreement.notNow"].tap()
        XCTAssertTrue(screen.exists)
        app.buttons["agreement.accept"].tap()
        XCTAssertTrue(tabButton("Ask", in: app).waitForExistence(timeout: 20))

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "TRAILGUARD_UI_RESET_AGREEMENT")
        app.launch()
        XCTAssertTrue(tabButton("Ask", in: app).waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["agreement.screen"].exists)
    }

    func testToolsUsesEmergencyFirstDashboardWithoutLegacyAccessSections() {
        let app = makeApp()
        app.launch()
        openTools(in: app)
        XCTAssertTrue(app.staticTexts["EMERGENCY CENTER"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Tools settings"].exists)
        XCTAssertFalse(app.staticTexts["Photo privacy"].exists)
        XCTAssertFalse(app.staticTexts["Download Access"].exists)
        XCTAssertFalse(app.buttons["Auto"].exists)
    }

    func testExplicitLiteLoadAndRelaunchStartsUnloaded() throws {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Load an offline model to ask Aurora"].waitForExistence(timeout: 20))
        guard app.buttons["Load Lite"].waitForExistence(timeout: 5) else {
            throw XCTSkip("The signed Lite + shared RAG setup is not installed on this device.")
        }
        app.buttons["Load Lite"].tap()
        XCTAssertTrue(app.buttons["Model: Lite"].waitForExistence(timeout: 90))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Load an offline model to ask Aurora"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["Load Lite"].exists)
        XCTAssertFalse(app.buttons["Model: Lite"].exists)
    }

    func testPhysicalSurvivalToolsCoreFlow() {
        let app = makeApp()
        app.launch()
        openTools(in: app)

        var flashlight = app.staticTexts["SOS Flashlight"]
        for _ in 0..<3 where !flashlight.exists { app.swipeUp() }
        flashlight = app.staticTexts["SOS Flashlight"]
        XCTAssertTrue(flashlight.waitForExistence(timeout: 20))
        flashlight.tap()
        XCTAssertTrue(app.buttons["Start SOS Signal"].waitForExistence(timeout: 10))
        app.buttons["Start SOS Signal"].tap()
        XCTAssertTrue(app.buttons["STOP SIGNAL"].waitForExistence(timeout: 10))
        app.buttons["STOP SIGNAL"].tap()
        app.navigationBars.buttons["Tools"].tap()

        var checklist = app.staticTexts["Checklist"]
        for _ in 0..<2 where !checklist.exists { app.swipeUp() }
        checklist = app.staticTexts["Checklist"]
        XCTAssertTrue(checklist.waitForExistence(timeout: 10))
        checklist.tap()
        XCTAssertTrue(app.navigationBars["Trip Checklist"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Add checklist item"].exists)
    }

    func testCameraAttachmentThreePhysicalJourneys() throws {
        let app = makeApp()
        app.launch()
        guard app.buttons["Attach photo"].waitForExistence(timeout: 30) else {
            throw XCTSkip("Expert is not active on this physical destination.")
        }

        let permissionMonitor = addUIInterruptionMonitor(
            withDescription: "Camera and Photo Library authorization"
        ) { alert in
            for label in ["Allow Full Access", "Allow", "OK"]
                where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(permissionMonitor) }

        XCTContext.runActivity(named: "1. Camera save and attach") { _ in
            app.buttons["Attach photo"].tap()
            XCTAssertTrue(app.buttons["Take Photo"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Choose Existing Photo"].exists)
            app.buttons["Take Photo"].tap()
            app.tap()
            captureAndUsePhoto(in: app)
            XCTAssertTrue(app.staticTexts["Photo attached"].waitForExistence(timeout: 20))
            app.buttons["chat.send"].tap()
            XCTAssertTrue(
                app.staticTexts["Photo attached"].waitForNonExistence(timeout: 2)
            )
            XCTAssertTrue(app.images["Sent photo"].waitForExistence(timeout: 10))
        }

        XCTContext.runActivity(named: "2. Choose an existing photo") { _ in
            app.buttons["Attach photo"].tap()
            app.buttons["Choose Existing Photo"].tap()
            selectFirstPhoto(in: app)
            XCTAssertTrue(app.staticTexts["Photo attached"].waitForExistence(timeout: 20))
        }

        app.terminate()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_CAPTURE_SAVE_FAILURE"] = "1"
        app.launchEnvironment["TRAILGUARD_DEBUG_OCR_FIXTURE_BASE64"] = Self.fixturePNGBase64
        app.launch()

        XCTContext.runActivity(named: "3. Failed save discards capture") { _ in
            XCTAssertTrue(app.staticTexts["Photo attached"].waitForExistence(timeout: 20))
            app.buttons["Replace"].tap()
            app.buttons["Take Photo"].tap()
            captureAndUsePhoto(in: app)
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "could not be saved and was discarded")
                ).firstMatch.waitForExistence(timeout: 20)
            )
            XCTAssertTrue(app.staticTexts["Photo attached"].exists)
            XCTAssertTrue(app.images["Attached photo preview"].exists)
        }
    }

    func testFourTabShellAndFocusedModelCenter() throws {
        let app = makeApp()
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
        let app = makeApp()
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

    func testFieldGuideRemainsAvailableWithoutModel() throws {
        let app = makeApp()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        let shortcut = app.buttons["chat.manual-chapter.fire"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 20))
        shortcut.tap()
        XCTAssertTrue(tabButton("Manual", in: app).isSelected)
        XCTAssertFalse(app.staticTexts["Start here"].exists)
        let lesson = app.staticTexts["Build a Basic Fire"].firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10))
        lesson.tap()
        XCTAssertTrue(
            app.navigationBars["Build a Basic Fire"]
                .waitForExistence(timeout: 10)
        )
        let visual = app.buttons["manual.visual.fire_basic_build"]
        XCTAssertTrue(visual.exists)
        visual.tap()
        let close = app.buttons["manual.visual.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        let next = app.buttons["manual.next.fire.wet_conditions"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.navigationBars["Fire in Wet Conditions"].waitForExistence(timeout: 10))

        app.terminate()
        app.launch()
        openManual(in: app)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("broken bone splint")
        let result = app.staticTexts["Support a Fracture"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        result.tap()
        XCTAssertTrue(
            app.navigationBars["Support a Fracture"]
                .waitForExistence(timeout: 20)
        )
    }

    func testMapsIsDirectFourthProductArea() throws {
        let app = makeApp()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        openMaps(in: app)
        XCTAssertTrue(tabButton("Maps", in: app).isSelected)
        XCTAssertTrue(app.navigationBars["Maps"].waitForExistence(timeout: 20))
        XCTAssertTrue(
            app.descendants(matching: .any)["maps.home"]
                .waitForExistence(timeout: 10)
        )
        keepScreenshot(named: "Maps overlay layout", app: app)
        let record = app.buttons["Record"].firstMatch
        let offline = app.buttons["Offline Maps"].firstMatch
        let waypoints = app.buttons["Waypoints"].firstMatch
        record.tap()
        XCTAssertTrue(app.staticTexts["Trail Recording"].waitForExistence(timeout: 2))
        offline.tap()
        XCTAssertTrue(app.staticTexts["Offline Maps"].waitForExistence(timeout: 2))
        waypoints.tap()
        XCTAssertTrue(
            app.staticTexts["Survival Waypoints"].waitForExistence(timeout: 2)
        )
        let source = app.buttons["Map type"].firstMatch
        XCTAssertTrue(source.exists)
        source.tap()
        XCTAssertTrue(app.buttons["Standard"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Satellite"].exists)
        keepScreenshot(named: "Map type menu", app: app)
    }

    func testManualSixChaptersAndNoResultsAtLargestType() throws {
        let app = makeApp()
        app.launchEnvironment["TRAILGUARD_UI_FORCE_NO_MODEL"] = "1"
        app.launchArguments += [
            "-AppleInterfaceStyle", "Dark",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()
        openManual(in: app)

        let chapters = ["Fire", "Water", "Shelter", "First Aid", "Navigation", "Food"]
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
        keepScreenshot(named: "Six chapter Manual dark largest type", app: app)
    }

    func testModelCenterDarkModeAndLargestDynamicType() throws {
        let app = makeApp()
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
        let app = makeApp()
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
        let app = makeApp()
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
        let app = makeApp()
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
        let app = makeApp()
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

    private func captureAndUsePhoto(in app: XCUIApplication) {
        let shutterCandidates = [
            app.buttons["PhotoCapture"],
            app.buttons["Take Picture"],
            app.buttons["Take Photo"],
        ]
        guard let shutter = shutterCandidates.first(where: {
            $0.waitForExistence(timeout: 15)
        }) else {
            XCTFail("The system camera shutter did not appear.")
            return
        }
        shutter.tap()
        let usePhoto = app.buttons["Use Photo"]
        XCTAssertTrue(usePhoto.waitForExistence(timeout: 15))
        usePhoto.tap()
    }

    private func selectFirstPhoto(in app: XCUIApplication) {
        let photosNavigation = app.navigationBars["Photos"]
        _ = photosNavigation.waitForExistence(timeout: 15)
        let photo = app.images.matching(
            identifier: "PXGGridLayout-Info"
        ).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        let frame = photo.frame
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
        let add = app.buttons["Add"]
        if add.waitForExistence(timeout: 2) { add.tap() }
    }

    private static let fixturePNGBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="

    private func launchPreparedApp() -> XCUIApplication {
        let app = makeApp()
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
            app.descendants(matching: .any)["manual.home"]
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
