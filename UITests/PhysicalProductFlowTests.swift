import XCTest
import UIKit

final class PhysicalProductFlowTests: XCTestCase {
    private let catalogURL = "http://192.168.3.51:8765/catalog.json"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTwinCitiesDownloadAndOfflineMapOpen() throws {
        let app = launchPreparedApp()
        let package = scrollToPackage(
            "package.map.twin-cities@1.0.0",
            in: app
        )
        let download = package.buttons["Download"]
        if download.exists {
            download.tap()
        }
        XCTAssertTrue(
            package.staticTexts["Installed & active"]
                .waitForExistence(timeout: 300)
        )

        openOfflineMaps(in: app)
        let canvas = app.otherElements["offline.map.canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 30))
        XCTAssertTrue(canvas.label.contains("Twin Cities"))

        keepScreenshot(named: "iPhone 13 Twin Cities offline map", app: app)
    }

    func testMinnesotaAndReviewedGuideDownload() throws {
        let app = launchPreparedApp()

        let guide = scrollToPackage(
            "package.knowledge.wilderness.starter@1.0.0",
            in: app
        )
        if guide.buttons["Download"].exists {
            guide.buttons["Download"].tap()
        }
        XCTAssertTrue(
            guide.staticTexts["Installed & active"]
                .waitForExistence(timeout: 60)
        )

        let minnesota = scrollToPackage(
            "package.map.minnesota@1.0.0",
            in: app
        )
        if minnesota.buttons["Download"].exists {
            minnesota.buttons["Download"].tap()
        }
        XCTAssertTrue(
            minnesota.staticTexts["Installed & active"]
                .waitForExistence(timeout: 300)
        )

        app.tabBars.buttons["Guide"].tap()
        XCTAssertTrue(
            app.staticTexts["Make backcountry water safer"]
                .waitForExistence(timeout: 20)
        )

        openOfflineMaps(in: app)
        let minnesotaPicker = app.buttons["Minnesota"]
        XCTAssertTrue(minnesotaPicker.waitForExistence(timeout: 20))
        minnesotaPicker.tap()
        let canvas = app.otherElements["offline.map.canvas"]
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Minnesota"),
            evaluatedWith: canvas
        )
        waitForExpectations(timeout: 30)
        keepScreenshot(named: "iPhone 13 Minnesota offline map", app: app)
    }

    func testInstalledProductsOpenWithCatalogUnavailable() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Status"].tap()
        let activeLite = app.staticTexts.matching(
            NSPredicate(
                format: "label CONTAINS %@",
                "Lite active"
            )
        ).firstMatch
        XCTAssertTrue(
            activeLite.waitForExistence(timeout: 30)
        )

        app.tabBars.buttons["Guide"].tap()
        XCTAssertTrue(
            app.staticTexts["Make backcountry water safer"]
                .waitForExistence(timeout: 20)
        )

        openOfflineMaps(in: app)
        let minnesotaPicker = app.buttons["Minnesota"]
        XCTAssertTrue(minnesotaPicker.waitForExistence(timeout: 20))
        minnesotaPicker.tap()
        let canvas = app.otherElements["offline.map.canvas"]
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Minnesota"),
            evaluatedWith: canvas
        )
        waitForExpectations(timeout: 30)
        keepScreenshot(
            named: "iPhone 13 installed products without catalog host",
            app: app
        )
    }

    func testLargestDynamicTypeCoreFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        app.tabBars.buttons["Guide"].tap()
        XCTAssertTrue(
            app.staticTexts["Make backcountry water safer"]
                .waitForExistence(timeout: 20)
        )

        app.tabBars.buttons["Ask"].tap()
        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("There is a fuel leak under my car.")
        app.buttons["chat.send"].tap()

        let response = app.descendants(matching: .any)[
            "chat.message.assistant"
        ]
        XCTAssertTrue(response.waitForExistence(timeout: 10))
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Fire or fuel hazard")
            ).firstMatch.exists
        )

        app.tabBars.buttons["Status"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["status.modelMetrics"]
                .waitForExistence(timeout: 10)
        )

        app.tabBars.buttons["Downloads"].tap()
        XCTAssertTrue(app.switches["download.mode"].waitForExistence(timeout: 10))
        keepScreenshot(named: "iPhone 13 largest Dynamic Type", app: app)
    }

    func testAirplaneModeColdRelaunch() throws {
        let app = launchLiteIncidentApp()
        app.terminate()
        app.launch()

        app.tabBars.buttons["Status"].tap()
        let activeLite = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Lite active")
        ).firstMatch
        XCTAssertTrue(activeLite.waitForExistence(timeout: 30))

        app.tabBars.buttons["Guide"].tap()
        XCTAssertTrue(
            app.staticTexts["Make backcountry water safer"]
                .waitForExistence(timeout: 20)
        )

        openOfflineMaps(in: app)
        let minnesota = app.buttons["Minnesota"]
        XCTAssertTrue(minnesota.waitForExistence(timeout: 20))
        minnesota.tap()
        let canvas = app.otherElements["offline.map.canvas"]
        expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Minnesota"),
            evaluatedWith: canvas
        )
        waitForExpectations(timeout: 30)

        app.tabBars.buttons["Ask"].tap()
        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("How do I make water safer?")
        app.buttons["chat.send"].tap()
        let response = app.descendants(matching: .any)[
            "chat.message.assistant"
        ]
        XCTAssertTrue(response.waitForExistence(timeout: 180))
        XCTAssertTrue(response.staticTexts["Lite"].exists)
        XCTAssertTrue(response.staticTexts["Offline sources (1)"].exists)
        keepScreenshot(named: "iPhone 13 Airplane Mode cold relaunch", app: app)
    }

    func testLowPowerModeFallsBackToEssential() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Status"].tap()

        let condition = app.descendants(matching: .any)[
            "status.deviceCondition"
        ]
        XCTAssertTrue(condition.waitForExistence(timeout: 10))
        XCTAssertTrue(condition.label.contains("Low Power Mode"))

        let tiers = app.descendants(matching: .any)["status.modelTiers"]
        XCTAssertTrue(tiers.waitForExistence(timeout: 10))
        XCTAssertTrue(tiers.label.contains("Essential active"))
        XCTAssertFalse(tiers.label.contains("Lite"))

        app.tabBars.buttons["Ask"].tap()
        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("How do I make water safer?")
        app.buttons["chat.send"].tap()
        let response = app.descendants(matching: .any)[
            "chat.message.assistant"
        ]
        XCTAssertTrue(response.waitForExistence(timeout: 20))
        XCTAssertTrue(response.staticTexts["Essential"].exists)
        XCTAssertTrue(response.staticTexts["Offline sources (1)"].exists)
        keepScreenshot(named: "iPhone 13 Low Power Mode fallback", app: app)
    }

    func testSafetyRuleBypassesInstalledLiteModel() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Ask"].tap()
        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("There is a fuel leak under my car.")
        app.buttons["chat.send"].tap()

        let response = app.descendants(matching: .any)[
            "chat.message.assistant"
        ]
        XCTAssertTrue(response.waitForExistence(timeout: 10))
        keepScreenshot(named: "iPhone 13 deterministic safety bypass", app: app)
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Fire or fuel hazard"
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Safety rule — model bypassed"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(response.staticTexts["Lite"].exists)

        app.tabBars.buttons["Status"].tap()
        let nativeMetrics = app.descendants(matching: .any)[
            "status.modelMetrics"
        ]
        XCTAssertTrue(nativeMetrics.waitForExistence(timeout: 10))
        XCTAssertTrue(nativeMetrics.label.contains("No native model run recorded"))
    }

    func testOnDeviceOCRTriggersSafetyOverride() throws {
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 1_000, height: 300)
        )
        let imageData = renderer.pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_000, height: 300))
            ("FUEL LEAK" as NSString).draw(
                at: CGPoint(x: 70, y: 80),
                withAttributes: [
                    .font: UIFont.boldSystemFont(ofSize: 110),
                    .foregroundColor: UIColor.black,
                ]
            )
        }

        let app = XCUIApplication()
        app.launchEnvironment[
            "TRAILGUARD_DEBUG_OCR_FIXTURE_BASE64"
        ] = imageData.base64EncodedString()
        app.launch()
        app.tabBars.buttons["Ask"].tap()

        let ocrStatus = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "text lines found")
        ).firstMatch
        XCTAssertTrue(ocrStatus.waitForExistence(timeout: 30))

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("What should I do?")
        app.buttons["chat.send"].tap()

        let response = app.descendants(matching: .any)[
            "chat.message.assistant"
        ]
        XCTAssertTrue(response.waitForExistence(timeout: 10))
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Fire or fuel hazard"
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Safety rule — model bypassed"
                )
            ).firstMatch.exists
        )
        keepScreenshot(named: "iPhone 13 Vision OCR safety override", app: app)
    }

    func testLiteModelDownloadResumesAndActivates() throws {
        let app = launchPreparedApp()
        let model = scrollToPackage(
            "package.model.lite.gemma3-1b-q4km@1.0.0",
            in: app
        )
        if model.buttons["Download"].exists {
            model.buttons["Download"].tap()
        } else if model.buttons["Resume"].exists {
            model.buttons["Resume"].tap()
        }
        XCTAssertTrue(
            model.staticTexts["Installed & active"]
                .waitForExistence(timeout: 1_200)
        )
        app.tabBars.buttons["Status"].tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "Lite active")
            ).firstMatch.waitForExistence(timeout: 30)
        )
        keepScreenshot(named: "iPhone 13 Lite model active", app: app)
    }

    func testLiteOnDeviceGroundedResponse() throws {
        let app = launchLiteIncidentApp()

        app.tabBars.buttons["Ask"].tap()
        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("How do I make water safer?")

        let started = Date()
        app.buttons["chat.send"].tap()
        let response = app.descendants(matching: .any)["chat.message.assistant"]
        XCTAssertTrue(response.waitForExistence(timeout: 180))
        let elapsedMilliseconds = Int(Date().timeIntervalSince(started) * 1_000)
        keepScreenshot(named: "iPhone 13 Lite grounded response", app: app)

        XCTAssertTrue(response.staticTexts["Lite"].exists)
        XCTAssertTrue(response.staticTexts["Offline sources (1)"].exists)
        XCTAssertFalse(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "local model was unavailable"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "failed evidence validation"
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Prefer moving water"
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            response.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "rolling boil for 1 minute"
                )
            ).firstMatch.exists
        )

        let metrics = XCTAttachment(
            string: "{\"completionMilliseconds\":\(elapsedMilliseconds),\"tier\":\"lite\",\"network\":\"incident-mode\"}"
        )
        metrics.name = "iPhone 13 Lite completion measurement"
        metrics.lifetime = .keepAlways
        add(metrics)

        app.tabBars.buttons["Status"].tap()
        let nativeMetrics = app.descendants(matching: .any)[
            "status.modelMetrics"
        ]
        XCTAssertTrue(nativeMetrics.waitForExistence(timeout: 10))
        XCTAssertTrue(nativeMetrics.label.contains("First token"))
        let nativeAttachment = XCTAttachment(string: nativeMetrics.label)
        nativeAttachment.name = "iPhone 13 native llama metrics"
        nativeAttachment.lifetime = .keepAlways
        add(nativeAttachment)
        keepScreenshot(named: "iPhone 13 native llama metrics", app: app)
    }

    func testLiteConversationalFollowUp() throws {
        let app = launchLiteIncidentApp()
        app.tabBars.buttons["Ask"].tap()

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        let responses = app.descendants(matching: .any).matching(
            identifier: "chat.message.assistant"
        )

        composer.tap()
        composer.typeText("How do I make stream water safer?")
        app.buttons["chat.send"].tap()
        let first = responses.element(boundBy: 0)
        XCTAssertTrue(first.waitForExistence(timeout: 180))
        XCTAssertTrue(first.staticTexts["Lite"].exists)
        XCTAssertTrue(
            first.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Offline sources (")
            ).firstMatch.exists
        )
        XCTAssertTrue(
            first.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "rolling boil for 1 minute"
                )
            ).firstMatch.exists
        )
        XCTAssertTrue(
            first.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "Cloth prefiltering removes sediment only"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            first.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "failed evidence validation"
                )
            ).firstMatch.exists
        )

        composer.tap()
        composer.typeText("What if I do not have a filter?")
        app.buttons["chat.send"].tap()
        let second = responses.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 180))
        XCTAssertTrue(second.staticTexts["Lite"].exists)
        XCTAssertTrue(
            second.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "Offline sources (")
            ).firstMatch.exists
        )
        XCTAssertTrue(
            second.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "rolling boil for 1 minute"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            second.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "failed evidence validation"
                )
            ).firstMatch.exists
        )
        XCTAssertFalse(
            second.staticTexts.matching(
                NSPredicate(
                    format: "label CONTAINS %@",
                    "local model was unavailable"
                )
            ).firstMatch.exists
        )
        let firstTranscript = first.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .joined(separator: "\n")
        let secondTranscript = second.staticTexts.allElementsBoundByIndex
            .map(\.label)
            .joined(separator: "\n")
        let evidence = XCTAttachment(
            string: "FIRST\n\(firstTranscript)\n\nFOLLOW-UP\n\(secondTranscript)"
        )
        evidence.name = "iPhone 13 conversational survival RAG transcript"
        evidence.lifetime = .keepAlways
        add(evidence)
        keepScreenshot(
            named: "iPhone 13 conversational survival follow-up",
            app: app
        )
    }

    func testLiteSustainedWarmRuns() throws {
        let app = launchLiteIncidentApp()
        app.tabBars.buttons["Ask"].tap()

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        let responses = app.descendants(matching: .any).matching(
            identifier: "chat.message.assistant"
        )
        var completionMilliseconds: [Int] = []

        for run in 0..<5 {
            composer.tap()
            composer.typeText("How do I make water safer?")
            let started = Date()
            app.buttons["chat.send"].tap()

            let response = responses.element(boundBy: run)
            XCTAssertTrue(response.waitForExistence(timeout: 180))
            completionMilliseconds.append(
                Int(Date().timeIntervalSince(started) * 1_000)
            )
            XCTAssertTrue(response.staticTexts["Lite"].exists)
            XCTAssertTrue(response.staticTexts["Offline sources (1)"].exists)
            XCTAssertTrue(
                response.staticTexts.matching(
                    NSPredicate(
                        format: "label CONTAINS %@",
                        "Prefer moving water"
                    )
                ).firstMatch.exists
            )
            XCTAssertFalse(
                response.staticTexts.matching(
                    NSPredicate(
                        format: "label CONTAINS %@",
                        "local model was unavailable"
                    )
                ).firstMatch.exists
            )
            XCTAssertFalse(
                response.staticTexts.matching(
                    NSPredicate(
                        format: "label CONTAINS %@",
                        "failed evidence validation"
                    )
                ).firstMatch.exists
            )
        }

        app.tabBars.buttons["Status"].tap()
        let nativeMetrics = app.descendants(matching: .any)[
            "status.modelMetrics"
        ]
        XCTAssertTrue(nativeMetrics.waitForExistence(timeout: 10))

        let evidence = XCTAttachment(
            string: "completions_ms=\(completionMilliseconds)\n\(nativeMetrics.label)"
        )
        evidence.name = "iPhone 13 five-run warm inference evidence"
        evidence.lifetime = .keepAlways
        add(evidence)

        XCTAssertFalse(nativeMetrics.label.contains("cold"))
        XCTAssertTrue(
            nativeMetrics.label.contains("thermal nominal")
                || nativeMetrics.label.contains("thermal fair")
        )

        let rateField = nativeMetrics.label.components(
            separatedBy: " · "
        ).first { $0.hasSuffix("tok/s") }
        let rate = rateField.flatMap {
            Double($0.replacingOccurrences(of: " tok/s", with: ""))
        }
        XCTAssertNotNil(rate)
        XCTAssertGreaterThanOrEqual(rate ?? 0, 8)

        keepScreenshot(named: "iPhone 13 sustained warm metrics", app: app)
    }

    func testLiteTwentyMinuteIncidentRun() throws {
        executionTimeAllowance = 1_500
        let app = launchLiteIncidentApp()
        app.tabBars.buttons["Ask"].tap()

        let composer = app.textFields["chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        let responses = app.descendants(matching: .any).matching(
            identifier: "chat.message.assistant"
        )
        let started = Date()
        let requiredDuration: TimeInterval = 20 * 60
        var runCount = 0
        var completionMilliseconds: [Int] = []

        while Date().timeIntervalSince(started) < requiredDuration {
            composer.tap()
            composer.typeText("How do I make water safer?")
            let runStarted = Date()
            app.buttons["chat.send"].tap()

            let response = responses.element(boundBy: runCount)
            XCTAssertTrue(response.waitForExistence(timeout: 180))
            completionMilliseconds.append(
                Int(Date().timeIntervalSince(runStarted) * 1_000)
            )
            XCTAssertTrue(response.staticTexts["Lite"].exists)
            XCTAssertTrue(response.staticTexts["Offline sources (1)"].exists)
            XCTAssertTrue(
                response.staticTexts.matching(
                    NSPredicate(
                        format: "label CONTAINS %@",
                        "Prefer moving water"
                    )
                ).firstMatch.exists
            )
            runCount += 1

            let remaining = requiredDuration
                - Date().timeIntervalSince(started)
            if remaining > 0 {
                RunLoop.current.run(
                    until: Date().addingTimeInterval(min(25, remaining))
                )
            }
        }

        app.tabBars.buttons["Status"].tap()
        let nativeMetrics = app.descendants(matching: .any)[
            "status.modelMetrics"
        ]
        XCTAssertTrue(nativeMetrics.waitForExistence(timeout: 10))
        XCTAssertTrue(
            nativeMetrics.label.contains("thermal nominal")
                || nativeMetrics.label.contains("thermal fair")
        )
        let rateField = nativeMetrics.label.components(
            separatedBy: " · "
        ).first { $0.hasSuffix("tok/s") }
        let rate = rateField.flatMap {
            Double($0.replacingOccurrences(of: " tok/s", with: ""))
        }
        XCTAssertGreaterThanOrEqual(rate ?? 0, 8)

        let evidence = XCTAttachment(
            string: [
                "duration_s=\(Int(Date().timeIntervalSince(started)))",
                "runs=\(runCount)",
                "completions_ms=\(completionMilliseconds)",
                nativeMetrics.label,
            ].joined(separator: "\n")
        )
        evidence.name = "iPhone 13 twenty-minute incident evidence"
        evidence.lifetime = .keepAlways
        add(evidence)
        keepScreenshot(named: "iPhone 13 twenty-minute incident", app: app)
    }

    private func launchPreparedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["TRAILGUARD_CATALOG_URL"] = catalogURL
        app.launch()

        app.tabBars.buttons["Downloads"].tap()
        let mode = app.switches["download.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        if mode.value as? String != "1" {
            mode.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
            ).tap()
        }
        expectation(
            for: NSPredicate(format: "label == %@", "Preparation mode"),
            evaluatedWith: mode
        )
        waitForExpectations(timeout: 5)

        let verify = app.buttons["catalog.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: 10))
        XCTAssertTrue(verify.isEnabled)
        verify.tap()
        let catalogStatus = app.staticTexts["catalog.status"]
        XCTAssertTrue(catalogStatus.waitForExistence(timeout: 30))
        expectation(
            for: NSPredicate(
                format: "label CONTAINS %@",
                "Verified catalog · 6 downloads"
            ),
            evaluatedWith: catalogStatus
        )
        waitForExpectations(timeout: 30)
        return app
    }

    private func launchLiteIncidentApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Status"].tap()
        let activeLite = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Lite active")
        ).firstMatch
        XCTAssertTrue(activeLite.waitForExistence(timeout: 30))

        app.tabBars.buttons["Downloads"].tap()
        let mode = app.switches["download.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        if mode.value as? String == "1" {
            mode.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
            ).tap()
        }
        expectation(
            for: NSPredicate(format: "label == %@", "Incident mode"),
            evaluatedWith: mode
        )
        waitForExpectations(timeout: 5)

        let tierPicker = app.descendants(matching: .any)["download.modelTier"]
        for _ in 0..<10 where !tierPicker.exists {
            app.swipeUp()
        }
        XCTAssertTrue(tierPicker.waitForExistence(timeout: 10))
        if !(tierPicker.value as? String ?? "").contains("Lite") {
            tierPicker.tap()
            XCTAssertTrue(app.buttons["Lite"].waitForExistence(timeout: 10))
            app.buttons["Lite"].tap()
        }
        return app
    }

    private func scrollToPackage(
        _ identifier: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        let package = app.descendants(matching: .any)[
            identifier
        ]
        for _ in 0..<6 where !package.exists {
            app.swipeUp()
        }
        XCTAssertTrue(package.waitForExistence(timeout: 10))
        return package
    }

    private func openOfflineMaps(in app: XCUIApplication) {
        app.tabBars.buttons["Ready"].tap()
        let offlineMaps = app.buttons["Offline map packs"]
        for _ in 0..<4 where !offlineMaps.exists {
            app.swipeUp()
        }
        XCTAssertTrue(offlineMaps.waitForExistence(timeout: 10))
        offlineMaps.tap()
    }

    private func keepScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
