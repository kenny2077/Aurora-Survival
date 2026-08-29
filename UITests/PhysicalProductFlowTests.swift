import XCTest

final class PhysicalProductFlowTests: XCTestCase {
    private let catalogURL = "http://192.168.3.51:8765/catalog.json"
    private let betaCatalogURL = "https://pub-6ac45181bc644cc3b7827299486a5230.r2.dev/beta/catalog.json"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func makeApp(acceptAgreement: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        if acceptAgreement {
            app.launchEnvironment["AURORA_UI_ACCEPT_AGREEMENT"] = "1"
        }
        return app
    }

    func testChatLiquidGlassEmptyStateAndLiteCapability() {
        let app = makeApp()
        app.launch()

        XCTAssertTrue(
            app.staticTexts["chat.greeting"].waitForExistence(timeout: 20)
        )
        let modelMenu = app.buttons["chat.modelSelection"]
        XCTAssertTrue(modelMenu.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Load Lite"].exists)
        XCTAssertTrue(app.textFields["chat.composer"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["chat.composerSurface"].exists
        )
        XCTAssertTrue(app.buttons["chat.attach"].exists)
        XCTAssertLessThan(modelMenu.frame.midX, app.frame.midX)
        XCTAssertTrue(
            app.navigationBars.buttons.allElementsBoundByIndex
                .filter { $0.frame.midX > app.frame.midX }
                .isEmpty
        )

        let greeting = app.staticTexts["chat.greeting"]
        let greetingY = greeting.frame.minY
        app.swipeUp()
        XCTAssertEqual(greeting.frame.minY, greetingY, accuracy: 2)
        app.swipeDown()
        XCTAssertEqual(greeting.frame.minY, greetingY, accuracy: 2)

        for removedText in [
            "Aurora",
            "Offline intelligence for the outdoors",
            "My car will not start",
            "How do I make water safer?",
            "What should I do if I am lost?",
            "Load an offline model to ask Aurora",
        ] {
            XCTAssertFalse(app.staticTexts[removedText].exists, removedText)
        }
        XCTAssertFalse(app.buttons["Voice input"].exists)

        modelMenu.tap()
        XCTAssertTrue(app.buttons["Load Lite"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Set Up Expert"].exists)
        keepScreenshot(named: "Chat model dropdown", app: app)
        app.staticTexts["chat.greeting"].tap()

        app.buttons["chat.attach"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["chat.liteAttachmentSheet"]
                .waitForExistence(timeout: 10)
        )
        let camera = app.buttons["chat.liteAttachment.camera"]
        let photo = app.buttons["chat.liteAttachment.photo"]
        XCTAssertTrue(camera.exists)
        XCTAssertTrue(photo.exists)
        XCTAssertFalse(camera.isEnabled)
        XCTAssertFalse(photo.isEnabled)
        XCTAssertTrue(camera.label.contains("Expert mode"))
        XCTAssertTrue(photo.label.contains("Expert mode"))
        XCTAssertFalse(app.staticTexts["Add a photo"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
        keepScreenshot(named: "Chat liquid glass empty state", app: app)
    }

    func testChatComposerDismissesKeyboardAndPreservesDraft() {
        let app = makeApp()
        app.launch()

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        composer.tap()
        let draft = "Keep this draft"
        composer.typeText(draft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        keepScreenshot(named: "Chat focused glass composer", app: app)

        app.staticTexts["chat.greeting"].tap()

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 5)
        )
        XCTAssertEqual(composer.value as? String, draft)
    }

    func testChatPhysicalLiteLoadAndConversation() {
        let app = makeApp()
        app.launch()

        let modelMenu = app.buttons["chat.modelSelection"]
        XCTAssertTrue(modelMenu.waitForExistence(timeout: 30))
        modelMenu.tap()
        let loadLite = app.buttons["Load Lite"]
        XCTAssertTrue(
            loadLite.waitForExistence(timeout: 30),
            "A validated Lite package must be installed for the physical gate."
        )
        loadLite.tap()
        XCTAssertTrue(
            app.buttons["Model: Lite"].waitForExistence(timeout: 90)
        )
        let loadedModelMenu = app.buttons["Model: Lite"]
        loadedModelMenu.tap()
        let unloadLite = app.buttons["Unload Lite"]
        if !unloadLite.waitForExistence(timeout: 5) {
            loadedModelMenu.tap()
        }
        XCTAssertTrue(unloadLite.waitForExistence(timeout: 5))
        app.staticTexts["chat.greeting"].tap()

        let composer = app.textFields["chat.composer"]
        composer.tap()
        composer.typeText("Where can I find water?")
        app.buttons["chat.send"].tap()

        let response = app.descendants(matching: .any)[
            "chat.message.assistant"
        ]
        XCTAssertTrue(response.waitForExistence(timeout: 180))
        let thinking = app.descendants(matching: .any)["chat.thinking"]
            .firstMatch
        XCTAssertTrue(thinking.waitForExistence(timeout: 5))
        keepScreenshot(named: "Chat thinking above response", app: app)
        XCTAssertTrue(
            response.staticTexts["Lite"].waitForExistence(timeout: 180)
        )
        XCTAssertLessThan(response.frame.minY, app.frame.midY)
        keepScreenshot(named: "Chat physical Lite conversation", app: app)

        tabButton("Tools", in: app).tap()
        let toolsUnloadLite = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@",
                "tools.model.unload.lite",
                "Unload Lite"
            )
        ).firstMatch
        XCTAssertTrue(
            toolsUnloadLite.waitForExistence(timeout: 10)
        )
        keepScreenshot(named: "Tools Lite runtime control", app: app)
    }

    func testToolsCompactLiteControlsAndExpertGate() {
        let app = makeApp()
        app.launch()
        openTools(in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["tools.offlineAI"]
                .waitForExistence(timeout: 20)
        )
        let loadLite = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@",
                "tools.model.load.lite",
                "Load Lite"
            )
        ).firstMatch
        XCTAssertTrue(
            loadLite.waitForExistence(timeout: 30),
            "A validated Lite package must be installed for this device check."
        )
        XCTAssertLessThan(loadLite.frame.width, 60)
        XCTAssertTrue(
            app.staticTexts["Requires a newer device"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertFalse(app.buttons["tools.model.load.vision_expert"].exists)
        XCTAssertFalse(app.buttons["tools.model.download.vision_expert"].exists)
        loadLite.tap()

        let unloadLite = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@ OR label == %@",
                "tools.model.unload.lite",
                "Unload Lite"
            )
        ).firstMatch
        XCTAssertTrue(unloadLite.waitForExistence(timeout: 90))
        XCTAssertLessThan(unloadLite.frame.width, 60)
        unloadLite.tap()
        XCTAssertTrue(loadLite.waitForExistence(timeout: 30))
    }

    func testOnboardingCleanLaunchUsesAuroraBrandAndConsolidatedLegalHub() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(acceptAgreement: false)
        app.launchEnvironment["AURORA_UI_RESET_AGREEMENT"] = "1"
        app.launch()

        let screen = app.descendants(matching: .any)["onboarding.screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Meet Aurora"].exists)
        XCTAssertTrue(
            app.staticTexts[
                "Offline AI help for the outdoors."
            ].exists
        )
        let disclosure = app.staticTexts.matching(
            NSPredicate(
                format: "label == %@",
                "Aurora can be wrong, so check critical guidance and seek help when possible; by continuing, you agree to Aurora’s Terms and acknowledge the Privacy Notice."
            )
        ).firstMatch
        XCTAssertTrue(disclosure.exists)
        let pageIndicator = app.descendants(matching: .any)[
            "onboarding.pageIndicator"
        ]
        XCTAssertTrue(pageIndicator.exists)
        XCTAssertEqual(pageIndicator.label, "Page 1 of 3")
        XCTAssertFalse(
            app.descendants(matching: .any)["onboarding.features"].exists
        )
        keepScreenshot(named: "Aurora onboarding page 1", app: app)

        app.buttons["Legal & Privacy"].tap()
        XCTAssertTrue(
            app.navigationBars["Legal & Privacy"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.buttons["Aurora Terms & AI Use"].exists)
        XCTAssertTrue(app.buttons["Privacy Notice"].exists)
        XCTAssertTrue(app.buttons["Model Licenses & Notices"].exists)
        keepScreenshot(named: "Onboarding legal and privacy hub", app: app)

        app.navigationBars["Legal & Privacy"].buttons.firstMatch.tap()
        app.buttons["onboarding.accept"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding.features"]
                .waitForExistence(timeout: 10)
        )
    }

    func testOnboardingThreePageNavigationAndModelsRouting() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(acceptAgreement: false)
        app.launchEnvironment["AURORA_UI_RESET_AGREEMENT"] = "1"
        app.launchEnvironment["AURORA_CATALOG_URL"] = betaCatalogURL
        app.launch()

        XCTAssertTrue(
            app.buttons["onboarding.accept"].waitForExistence(timeout: 20)
        )
        app.buttons["onboarding.accept"].tap()
        XCTAssertTrue(
            app.staticTexts["Ready when the network isn’t"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Works offline"].exists)
        XCTAssertTrue(app.staticTexts["Source-backed"].exists)
        XCTAssertTrue(app.staticTexts["Private by design"].exists)
        keepScreenshot(named: "Aurora onboarding page 2", app: app)

        app.buttons["Back"].tap()
        XCTAssertTrue(app.staticTexts["Meet Aurora"].waitForExistence(timeout: 10))
        app.buttons["onboarding.accept"].tap()
        XCTAssertTrue(
            app.buttons["onboarding.continue"].waitForExistence(timeout: 10)
        )
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(
            app.staticTexts["Choose what to take offline"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Aurora Lite"].exists)
        XCTAssertTrue(app.staticTexts["Aurora Expert"].exists)
        XCTAssertFalse(
            app.staticTexts["Download a model now or set it up later."].exists
        )
        XCTAssertFalse(
            app.staticTexts[
                "Large downloads use Wi-Fi by default. Both models keep working after download."
            ].exists
        )
        let liteDownload = app.buttons["onboarding.download.lite"]
        let expertDownload = app.buttons["onboarding.download.vision_expert"]
        XCTAssertTrue(liteDownload.waitForExistence(timeout: 10))
        XCTAssertTrue(expertDownload.exists)
        let downloadsEnabled = expectation(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: liteDownload
        )
        let expertDownloadEnabled = expectation(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: expertDownload
        )
        wait(for: [downloadsEnabled, expertDownloadEnabled], timeout: 30)
        keepScreenshot(named: "Aurora onboarding page 3", app: app)

        liteDownload.tap()
        XCTAssertTrue(tabButton("Tools", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(tabButton("Tools", in: app).isSelected)
    }

    func testOnboardingExpertDownloadAndSetUpLaterPersistence() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = makeApp(acceptAgreement: false)
        app.launchEnvironment["AURORA_UI_RESET_AGREEMENT"] = "1"
        app.launchEnvironment["AURORA_CATALOG_URL"] = betaCatalogURL
        app.launch()

        XCTAssertTrue(
            app.buttons["onboarding.accept"].waitForExistence(timeout: 20)
        )
        app.buttons["onboarding.accept"].tap()
        XCTAssertTrue(
            app.buttons["onboarding.continue"].waitForExistence(timeout: 10)
        )
        app.buttons["onboarding.continue"].tap()
        let expertDownload = app.buttons["onboarding.download.vision_expert"]
        XCTAssertTrue(expertDownload.waitForExistence(timeout: 10))
        let expertDownloadEnabled = expectation(
            for: NSPredicate(format: "enabled == true"),
            evaluatedWith: expertDownload
        )
        wait(for: [expertDownloadEnabled], timeout: 30)
        expertDownload.tap()
        XCTAssertTrue(tabButton("Tools", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(tabButton("Tools", in: app).isSelected)

        app.terminate()
        app.launch()
        XCTAssertTrue(
            app.buttons["onboarding.accept"].waitForExistence(timeout: 20)
        )
        app.buttons["onboarding.accept"].tap()
        XCTAssertTrue(
            app.buttons["onboarding.continue"].waitForExistence(timeout: 10)
        )
        app.buttons["onboarding.continue"].tap()
        XCTAssertTrue(
            app.buttons["onboarding.skipModels"].waitForExistence(timeout: 10)
        )
        app.buttons["onboarding.skipModels"].tap()

        XCTAssertTrue(tabButton("Ask", in: app).waitForExistence(timeout: 20))
        XCTAssertTrue(tabButton("Manual", in: app).exists)
        XCTAssertTrue(tabButton("Maps", in: app).exists)
        XCTAssertTrue(tabButton("Tools", in: app).exists)

        app.terminate()
        app.launchEnvironment.removeValue(forKey: "AURORA_UI_RESET_AGREEMENT")
        app.launch()
        XCTAssertTrue(tabButton("Ask", in: app).waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.screen"].exists)
    }

    func testLiteDownloadShowsProgressWithoutStartingExpert() throws {
        let app = makeApp()
        app.launch()
        openTools(in: app)

        let lite = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Download Lite + Knowledge")
        ).firstMatch
        let expert = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Download Expert + Knowledge")
        ).firstMatch
        XCTAssertTrue(lite.waitForExistence(timeout: 30))
        XCTAssertTrue(expert.waitForExistence(timeout: 30))
        XCTAssertTrue(lite.label.contains("MB"))
        XCTAssertTrue(expert.label.contains("GB"))

        lite.tap()
        let liteProgress = app.descendants(matching: .any)[
            "tools.model.progress.lite"
        ]
        let liteProgressLabel = app.staticTexts[
            "tools.model.progressLabel.lite"
        ]
        XCTAssertTrue(liteProgress.waitForExistence(timeout: 30))
        XCTAssertTrue(liteProgressLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(liteProgressLabel.label.hasSuffix("%"))

        XCTAssertTrue(expert.exists)
        XCTAssertFalse(
            app.descendants(matching: .any)[
                "tools.model.progress.vision_expert"
            ].exists
        )
        XCTAssertFalse(app.buttons["tools.model.pause.vision_expert"].exists)

        let pause = app.buttons.matching(
            NSPredicate(format: "label == %@", "Pause Lite download")
        ).firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 30))
        pause.tap()
    }

    func testToolsDashboardLiquidGlassSimplicity() {
        let app = makeApp()
        app.launch()
        openTools(in: app)

        XCTAssertTrue(app.navigationBars["Tools"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Tools settings"].exists)
        XCTAssertTrue(app.staticTexts["Offline Models"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["tools.tier.lite"].exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["tools.tier.vision_expert"].exists
        )

        let emergency = app.buttons["tools.emergency"]
        for _ in 0..<2 where !emergency.exists { app.swipeUp() }
        XCTAssertTrue(emergency.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Field tools"].exists)
        XCTAssertFalse(app.staticTexts["EMERGENCY CENTER"].exists)
        for removedBadge in ["Ready", "Loaded", "Available", "Unavailable"] {
            XCTAssertFalse(app.staticTexts[removedBadge].exists)
        }
        keepScreenshot(named: "Tools liquid glass dashboard", app: app)
    }

    func testToolsSettingsSimplicity() {
        let app = makeApp()
        app.launch()
        openTools(in: app)

        let settings = app.buttons["tools.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 20))
        settings.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Version"].exists)
        XCTAssertTrue(app.staticTexts["Selected model"].exists)
        XCTAssertFalse(app.staticTexts["Loaded model"].exists)
        XCTAssertFalse(app.staticTexts["Installed AI"].exists)
        XCTAssertTrue(app.staticTexts["Legal"].exists)

        app.swipeUp()
        XCTAssertTrue(app.buttons["tools.reset"].waitForExistence(timeout: 10))
        keepScreenshot(named: "Tools simplified settings", app: app)
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
            XCTAssertFalse(app.buttons["Replace"].exists)
            XCTAssertFalse(app.buttons["Remove"].exists)
            XCTAssertTrue(app.buttons["chat.attachment.remove"].exists)
            app.buttons["chat.attachment.preview"].tap()
            XCTAssertTrue(
                app.descendants(matching: .any)["chat.photoPreview"]
                    .waitForExistence(timeout: 5)
            )
            app.buttons["chat.photoPreview.close"].tap()
            app.buttons["chat.send"].tap()
            XCTAssertTrue(
                app.staticTexts["Photo attached"].waitForNonExistence(timeout: 2)
            )
            XCTAssertTrue(
                app.buttons["chat.message.photoPreview"].waitForExistence(timeout: 10)
            )
            app.buttons["chat.message.photoPreview"].tap()
            XCTAssertTrue(app.buttons["chat.photoPreview.close"].waitForExistence(timeout: 5))
            app.buttons["chat.photoPreview.close"].tap()
        }

        XCTContext.runActivity(named: "2. Choose an existing photo") { _ in
            app.buttons["Attach photo"].tap()
            app.buttons["Choose Existing Photo"].tap()
            selectFirstPhoto(in: app)
            XCTAssertTrue(app.staticTexts["Photo attached"].waitForExistence(timeout: 20))
            app.buttons["chat.attachment.remove"].tap()
            XCTAssertTrue(
                app.staticTexts["Photo attached"].waitForNonExistence(timeout: 2)
            )
        }

        app.terminate()
        app.launchEnvironment["AURORA_UI_FORCE_CAPTURE_SAVE_FAILURE"] = "1"
        app.launchEnvironment["AURORA_DEBUG_OCR_FIXTURE_BASE64"] = Self.fixturePNGBase64
        app.launch()

        XCTContext.runActivity(named: "3. Failed save discards capture") { _ in
            XCTAssertTrue(app.staticTexts["Photo attached"].waitForExistence(timeout: 20))
            app.buttons["Attach photo"].tap()
            app.buttons["Take Photo"].tap()
            captureAndUsePhoto(in: app)
            XCTAssertTrue(
                app.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] %@", "could not be saved and was discarded")
                ).firstMatch.waitForExistence(timeout: 20)
            )
            XCTAssertTrue(app.staticTexts["Photo attached"].exists)
            XCTAssertTrue(app.buttons["chat.attachment.preview"].exists)
        }
    }

    func testFourTabShellAndFocusedModelCenter() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
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
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
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
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        XCTAssertTrue(
            app.descendants(matching: .any)["chat.modelRequired"]
                .waitForExistence(timeout: 20)
        )
        XCTAssertTrue(app.images["chat.survivalGuideIcon"].exists)
        XCTAssertTrue(app.staticTexts["Survival Guide"].exists)
        for chapter in [
            "fire": "Fire",
            "water": "Water",
            "shelter": "Shelter",
            "first_aid": "First Aid",
            "navigation": "Navigation",
            "food": "Food",
        ] {
            let block = app.buttons["chat.manual-chapter.\(chapter.key)"]
            XCTAssertTrue(block.exists, "Missing \(chapter.value) chapter")
            XCTAssertEqual(block.label, chapter.value)
        }
        for removedText in [
            "How can I help?",
            "Browse the Field Guide",
            "Choose an immediate need. No model or download is required.",
            "Offline model required",
        ] {
            XCTAssertFalse(app.staticTexts[removedText].exists, removedText)
        }
        keepScreenshot(named: "No-model glass chapter links", app: app)

        let shortcut = app.buttons["chat.manual-chapter.fire"]
        shortcut.tap()
        XCTAssertTrue(tabButton("Manual", in: app).isSelected)
        XCTAssertTrue(
            app.descendants(matching: .any)["manual.chapter.fire"]
                .waitForExistence(timeout: 10)
        )
    }

    func testMapsTopChromeAndCompactOfflinePanel() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()

        openMaps(in: app)
        let canvas = app.descendants(matching: .any)["maps.canvas"]
        let scale = app.descendants(matching: .any)["maps.scale"]
        let source = app.buttons["maps.source"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        XCTAssertTrue(scale.waitForExistence(timeout: 10))
        XCTAssertTrue(source.exists)
        XCTAssertFalse(app.navigationBars["Maps"].exists)
        XCTAssertEqual(scale.frame.midX, app.frame.midX, accuracy: 8)
        XCTAssertLessThan(scale.frame.minY, source.frame.maxY)
        XCTAssertFalse(scale.frame.intersects(source.frame))

        app.buttons["maps.mode.offlineMaps"].tap()
        let description = app.staticTexts[
            "Use downloaded maps without service."
        ]
        let manage = app.buttons["maps.download.manage"]
        XCTAssertFalse(description.exists)
        XCTAssertTrue(manage.exists)
        XCTAssertEqual(manage.label, "Downloads")
        XCTAssertLessThan(manage.frame.width, app.frame.width * 0.55)
        keepScreenshot(named: "Top scale and compact offline panel", app: app)
    }

    func testMapsCleanChromeAndGestureIsolation() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()
        openMaps(in: app)

        let canvas = app.descendants(matching: .any)["maps.canvas"]
        let chrome = app.descendants(matching: .any)["maps.chrome"]
        let source = app.buttons["maps.source"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        XCTAssertTrue(chrome.waitForExistence(timeout: 10))

        canvas.swipeLeft()
        XCTAssertTrue(chrome.exists)
        canvas.rotate(.pi / 6, withVelocity: 1)
        XCTAssertTrue(chrome.exists)

        app.buttons["maps.mode.record"].tap()
        let pause = app.buttons["Pause"]
        let resume = app.buttons["Resume"]
        let start = app.buttons["Start"]
        if !pause.exists {
            if resume.waitForExistence(timeout: 2) {
                resume.tap()
            } else {
                XCTAssertTrue(start.waitForExistence(timeout: 8))
                start.tap()
            }
        }
        XCTAssertTrue(pause.waitForExistence(timeout: 10))

        let togglePoint = canvas.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.32)
        )
        togglePoint.tap()
        XCTAssertTrue(chrome.waitForNonExistence(timeout: 10))
        XCTAssertTrue(source.waitForNonExistence(timeout: 10))
        XCTAssertTrue(
            app.descendants(matching: .any)["maps.scale"]
                .waitForNonExistence(timeout: 10)
        )
        XCTAssertTrue(tabButton("Maps", in: app).exists)
        keepScreenshot(named: "Clean map with chrome hidden", app: app)

        togglePoint.tap()
        XCTAssertTrue(chrome.waitForExistence(timeout: 10))
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        app.buttons["Finish"].tap()

        app.buttons["maps.mode.waypoints"].tap()
        let placement = canvas.coordinate(
            withNormalizedOffset: CGVector(dx: 0.35, dy: 0.35)
        )
        placement.press(forDuration: 0.6)
        XCTAssertTrue(
            app.navigationBars["New Waypoint"].waitForExistence(timeout: 10)
        )
        app.buttons["Cancel"].tap()
        XCTAssertTrue(
            app.navigationBars["New Waypoint"].waitForNonExistence(timeout: 10)
        )
        XCTAssertTrue(chrome.exists)

        let savedWaypoint = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "maps.waypoint.saved."
            )
        ).firstMatch
        XCTAssertTrue(savedWaypoint.waitForExistence(timeout: 10))
        canvas.swipeLeft()
        canvas.swipeLeft()
        let pannedCenter = canvas.value as? String
        XCTAssertNotNil(pannedCenter)
        savedWaypoint.tap()
        let recentered = NSPredicate(
            format: "value != %@",
            pannedCenter ?? ""
        )
        expectation(for: recentered, evaluatedWith: canvas)
        waitForExpectations(timeout: 10)
        keepScreenshot(named: "Saved waypoint recentered", app: app)
    }

    func testMapsCompactInstalledMapRouting() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()
        openMaps(in: app)

        app.buttons["maps.mode.offlineMaps"].tap()
        let manage = app.buttons["maps.download.manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.tap()
        XCTAssertTrue(
            app.navigationBars["Offline Maps"].waitForExistence(timeout: 20)
        )

        let openButtons = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "downloads.map.open."
            )
        )
        let open = openButtons.firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        XCTAssertGreaterThan(openButtons.count, 0)
        for button in openButtons.allElementsBoundByIndex {
            XCTAssertLessThan(button.frame.height, 50)
            XCTAssertLessThan(button.frame.width, 150)
        }

        let mapID = String(
            open.identifier.dropFirst("downloads.map.open.".count)
        )
        let name = app.descendants(matching: .any)[
            "downloads.map.name.\(mapID)"
        ]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.frame.midY, open.frame.midY, accuracy: 8)
        keepScreenshot(named: "Compact installed map rows", app: app)

        open.tap()
        let layer = app.buttons.matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@",
                "downloads.map.layer."
            )
        ).firstMatch
        if layer.waitForExistence(timeout: 2) {
            layer.tap()
        }
        XCTAssertTrue(
            app.navigationBars["Offline Maps"].waitForNonExistence(timeout: 20)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["maps.canvas"]
                .waitForExistence(timeout: 10)
        )
    }

    func testManualSimplicityHome() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()
        openManual(in: app)

        XCTAssertTrue(app.navigationBars["Field Guide"].exists)
        XCTAssertTrue(app.searchFields["Search skills"].exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["manual.orientation"].exists
        )

        for chapter in [
            "fire", "water", "shelter", "first_aid", "navigation", "food",
        ] {
            let link = app.descendants(matching: .any)[
                "manual.chapter-link.\(chapter)"
            ]
            for _ in 0..<8 where !link.exists {
                app.swipeUp()
            }
            XCTAssertTrue(link.exists, "Missing chapter link: \(chapter)")
        }

        for removedText in [
            "Start here",
            "Always offline",
            "Six essential chapters",
            "Survival priority card",
            "Six skills to master before you go",
            "Essential Wilderness Skills",
        ] {
            XCTAssertFalse(app.staticTexts[removedText].exists, removedText)
        }
        app.swipeDown()
        app.swipeDown()
        keepScreenshot(named: "Manual compact glass home", app: app)
    }

    func testManualCompactSearchAndRouting() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()
        openManual(in: app)

        let search = app.searchFields["Search skills"]
        XCTAssertTrue(search.exists)
        search.tap()
        search.typeText("water")

        let result = app.descendants(matching: .any)[
            "manual.search-result.water.find"
        ]
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()

        XCTAssertTrue(
            app.descendants(matching: .any)["manual.skill.water.find"]
                .waitForExistence(timeout: 10)
        )
        XCTAssertTrue(app.staticTexts["Find Water"].exists)
        XCTAssertTrue(app.staticTexts["Search terrain in this order:"].exists)
    }

    func testManualVisualIndicatorMatchesBundledImage() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
        app.launch()
        openManual(in: app)

        let fire = app.descendants(matching: .any)["manual.chapter-link.fire"]
        XCTAssertTrue(fire.waitForExistence(timeout: 10))
        fire.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["manual.chapter.fire"]
                .waitForExistence(timeout: 10)
        )

        let visualSkill = app.descendants(matching: .any)[
            "manual.skill-link.fire.basic_fire"
        ]
        let textSkill = app.descendants(matching: .any)[
            "manual.skill-link.fire.extinguish"
        ]
        XCTAssertTrue(visualSkill.exists)
        for _ in 0..<5 where !textSkill.exists {
            app.swipeUp()
        }
        XCTAssertTrue(textSkill.exists)
        XCTAssertEqual(visualSkill.value as? String, "Includes visual guide")
        XCTAssertEqual(textSkill.value as? String, "Text guide")

        app.swipeDown()
        visualSkill.tap()
        let visual = app.descendants(matching: .any)[
            "manual.visual.fire_basic_build"
        ]
        XCTAssertTrue(visual.waitForExistence(timeout: 10))
        visual.tap()
        XCTAssertTrue(
            app.buttons["manual.visual.close"].waitForExistence(timeout: 10)
        )
    }

    func testManualSixChaptersAndNoResultsAtLargestType() throws {
        let app = makeApp()
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
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
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
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
        app.launchEnvironment["AURORA_CATALOG_URL"] = catalogURL
        app.launchEnvironment["AURORA_UI_FORCE_NO_MODEL"] = "1"
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
