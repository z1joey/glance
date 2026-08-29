import XCTest

/// XCUITest smoke (design spec §8): open sample → switch to edit → type →
/// save → assert the file changed on disk; single-file window shows no Files
/// segment.
final class GlanceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOpenEditSaveRoundTrip() throws {
        // Stage a private copy of a tiny sample so the test may mutate it.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-uitest-\(UUID().uuidString).md")
        let sample = """
        # UI Test Doc

        Hello **world**.

        ## Section

        Body text for the smoke test.
        """
        try sample.write(to: temp, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: temp) }

        let app = XCUIApplication()
        app.launchEnvironment["GLANCE_AUTOTEST_FILE"] = temp.path
        app.launch()

        // Rendered view is up (the pipeline booted).
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))

        // A single file is open: no Files segment anywhere in the sidebar.
        XCTAssertFalse(app.segmentedControls.firstMatch.exists)

        // Switch to editing via the toolbar toggle (eye → pencil).
        let toggle = app.buttons["mode-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.click()

        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        editor.typeText("UITEST-MARKER ")

        // Save with ⌘S (the menu action's keyboard equivalent).
        app.typeKey("s", modifierFlags: .command)

        // Assert the file changed on disk.
        let expectation = expectation(description: "file updated on disk")
        let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
            let content = (try? String(contentsOf: temp, encoding: .utf8)) ?? ""
            print("UITEST-DEBUG disk content: \(content.prefix(120))")
            if content.contains("UITEST-MARKER") {
                timer.invalidate()
                expectation.fulfill()
            }
        }
        addTeardownBlock { timer.invalidate() }
        wait(for: [expectation], timeout: 8)
    }
}
