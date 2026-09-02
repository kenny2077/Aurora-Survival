#if AURORA_MESH_BETA
import XCTest

final class MeshChatUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDebugCardOnboardingAndByteLimit() {
        let app = XCUIApplication()
        app.launchEnvironment["AURORA_UI_ACCEPT_AGREEMENT"] = "1"
        app.launchEnvironment["AURORA_UI_RESET_MESH_ONBOARDING"] = "1"
        app.launch()

        app.tabBars.buttons["Tools"].tap()
        let card = app.buttons["tools.meshChat"]
        while !card.exists { app.swipeUp() }
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.buttons["mesh.onboarding.accept"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Range is not guaranteed. Concrete, steel, interference, and device position can stop a link."].exists)
        XCTAssertTrue(app.staticTexts["Mesh Chat does not contact emergency services and is not a substitute for an emergency call or satellite service."].exists)
        app.buttons["mesh.onboarding.accept"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mesh.radio.status"].waitForExistence(timeout: 10))

        app.buttons["Create Group"].tap()
        app.textFields["mesh.create.name"].tap()
        app.textFields["mesh.create.name"].typeText("Trail Team")
        app.buttons["mesh.create.confirm"].tap()
        XCTAssertTrue(app.staticTexts["Trail Team"].waitForExistence(timeout: 10))
        app.staticTexts["Trail Team"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["mesh.group.header"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["mesh.messages.empty"].exists)

        let composer = app.textFields["mesh.message.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        composer.typeText("Checking in")
        app.buttons["mesh.message.send"].tap()
        XCTAssertTrue(app.staticTexts["Checking in"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["mesh.messages.empty"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "mesh.message.day").count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "mesh.message.delivery").count, 1)

        composer.tap()
        composer.typeText(String(repeating: "a", count: 2_049))
        XCTAssertTrue(app.descendants(matching: .any)["mesh.message.byteCount"].exists)
        XCTAssertFalse(app.buttons["mesh.message.send"].isEnabled)
    }

    func testScannerIsFullScreenAndDismissible() {
        let app = launchInMeshHome()
        app.buttons["mesh.scanInvite"].tap()

        let scanner = app.descendants(matching: .any)["mesh.scanner.fullScreen"]
        XCTAssertTrue(scanner.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch
        XCTAssertEqual(scanner.frame.minX, window.frame.minX, accuracy: 2)
        XCTAssertEqual(scanner.frame.minY, window.frame.minY, accuracy: 2)
        XCTAssertEqual(scanner.frame.width, window.frame.width, accuracy: 2)
        XCTAssertEqual(scanner.frame.height, window.frame.height, accuracy: 2)
        XCTAssertTrue(app.buttons["mesh.scanner.close"].isHittable)
        app.buttons["mesh.scanner.close"].tap()
        XCTAssertTrue(app.buttons["mesh.scanInvite"].waitForExistence(timeout: 10))
    }

    func testCreatorCanConfirmDeletionAndReturnsHome() {
        let app = launchInMeshHome()
        app.buttons["Create Group"].tap()
        app.textFields["mesh.create.name"].tap()
        app.textFields["mesh.create.name"].typeText("Temporary Team")
        app.buttons["mesh.create.confirm"].tap()
        app.staticTexts["Temporary Team"].tap()
        app.buttons["Group details"].tap()

        let delete = app.buttons["mesh.group.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        XCTAssertTrue(app.buttons["Delete Group for Everyone"].waitForExistence(timeout: 10))
        app.buttons["Delete Group for Everyone"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["mesh.home"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Temporary Team"].exists)
    }

    private func launchInMeshHome() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["AURORA_UI_ACCEPT_AGREEMENT"] = "1"
        app.launchEnvironment["AURORA_UI_RESET_MESH_ONBOARDING"] = "1"
        app.launch()
        app.tabBars.buttons["Tools"].tap()
        let card = app.buttons["tools.meshChat"]
        while !card.exists { app.swipeUp() }
        card.tap()
        let accept = app.buttons["mesh.onboarding.accept"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mesh.radio.status"].waitForExistence(timeout: 10))
        return app
    }
}
#endif
