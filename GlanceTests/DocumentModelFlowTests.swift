import XCTest
@testable import Glance

/// Tests for the state-machine additions the UI layer drives:
/// toggle/request-leaving-editing with confirmation continuations,
/// conflict prompting, user alerts, and scroll requests.
@MainActor
final class DocumentModelFlowTests: XCTestCase {

    private var tempDir: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-flow-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        fileURL = tempDir.appendingPathComponent("flow.md")
        try "v1".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeModel() async throws -> DocumentModel {
        let model = DocumentModel()
        await model.openDocument(at: fileURL)
        return model
    }

    // MARK: toggleMode

    func testToggleModeEntersAndLeavesEditingWhenClean() async throws {
        let model = try await makeModel()
        model.toggleMode()
        XCTAssertEqual(model.mode, .editing)
        model.toggleMode()
        XCTAssertEqual(model.mode, .reading)
    }

    func testToggleModeWithUnsavedChangesAsksForConfirmation() async throws {
        let model = try await makeModel()
        model.toggleMode()
        model.rawText = "dirty"

        model.toggleMode()
        // Stays in editing; the view must now present the save/revert/cancel dialog.
        XCTAssertEqual(model.mode, .editing)
        XCTAssertTrue(model.pendingExitResolution)
    }

    // MARK: requestLeavingEditing continuations

    func testCleanRequestLeavingEditingRunsContinuationImmediately() async throws {
        let model = try await makeModel()
        var ran = false
        model.requestLeavingEditing { ran = true }
        XCTAssertTrue(ran)
        XCTAssertFalse(model.pendingExitResolution)
    }

    func testDirtyRequestWaitsForResolutionAndRevertRunsContinuation() async throws {
        let model = try await makeModel()
        model.toggleMode()
        model.rawText = "dirty"

        var ran = false
        model.requestLeavingEditing { ran = true }
        XCTAssertFalse(ran)

        await model.resolveExit(.revert)
        XCTAssertTrue(ran)
        XCTAssertFalse(model.pendingExitResolution)
        XCTAssertEqual(model.mode, .reading)
        XCTAssertEqual(model.rawText, "v1")
    }

    func testResolveExitSaveWritesAndRunsContinuation() async throws {
        let model = try await makeModel()
        model.toggleMode()
        model.rawText = "saved via dialog"

        var ran = false
        model.requestLeavingEditing { ran = true }
        await model.resolveExit(.save)

        XCTAssertTrue(ran)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "saved via dialog")
        XCTAssertEqual(model.mode, .reading)
    }

    func testResolveExitCancelKeepsEditingAndDropsContinuation() async throws {
        let model = try await makeModel()
        model.toggleMode()
        model.rawText = "dirty"

        var ran = false
        model.requestLeavingEditing { ran = true }
        await model.resolveExit(.cancel)

        XCTAssertFalse(ran)
        XCTAssertEqual(model.mode, .editing)
        XCTAssertTrue(model.isDirty)
        XCTAssertFalse(model.pendingExitResolution)
    }

    // MARK: conflict prompting

    func testSaveWithConflictRaisesPendingConflictAndResolutionsClearIt() async throws {
        let model = try await makeModel()
        model.toggleMode()
        model.rawText = "mine"
        try await Task.sleep(nanoseconds: 20_000_000)
        try "disk changed".write(to: fileURL, atomically: true, encoding: .utf8)

        let outcome = await model.save()
        XCTAssertEqual(outcome, .conflict)
        XCTAssertTrue(model.pendingConflict)

        model.cancelConflictResolution()
        XCTAssertFalse(model.pendingConflict)
        XCTAssertTrue(model.isDirty) // still unresolved

        await model.overwriteOnConflict()
        XCTAssertFalse(model.pendingConflict)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "mine")

        // Now force a second conflict and reload instead.
        model.toggleMode(); model.rawText = "second edit"
        try await Task.sleep(nanoseconds: 20_000_000)
        try "disk wins again".write(to: fileURL, atomically: true, encoding: .utf8)
        _ = await model.save()
        XCTAssertTrue(model.pendingConflict)
        await model.reloadOnConflict()
        XCTAssertFalse(model.pendingConflict)
        XCTAssertEqual(model.rawText, "disk wins again")
        XCTAssertEqual(model.mode, .reading)
    }

    // MARK: alerts

    func testRefusalPublishesUserAlertAndDismissalClearsIt() async throws {
        let model = DocumentModel()
        await model.openDocument(at: tempDir.appendingPathComponent("missing.md"))
        XCTAssertNotNil(model.userAlert)
        model.dismissAlert()
        XCTAssertNil(model.userAlert)
    }

    // MARK: scroll requests

    func testScrollRequestRoundTrip() async throws {
        let model = try await makeModel()
        let entry = OutlineEntry(level: 2, text: "Section", id: "section")
        model.requestScroll(to: entry)
        XCTAssertEqual(model.scrollRequest, entry)
        model.consumeScrollRequest()
        XCTAssertNil(model.scrollRequest)
    }
}
