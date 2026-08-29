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

    /// Polls until `condition` holds — the open continuations run on spawned
    /// tasks, so their effect lands shortly after `resolveExit` returns.
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("condition not met before timeout")
    }

    /// Makes the model dirty and changes the file on disk so the next save
    /// hits an mtime conflict.
    private func stageSaveConflict(_ model: DocumentModel) async throws {
        model.toggleMode()
        model.rawText = "my edit"
        try await Task.sleep(nanoseconds: 20_000_000)
        try "disk change".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func makeOtherFile() throws -> URL {
        let otherURL = tempDir.appendingPathComponent("other.md")
        try "other content".write(to: otherURL, atomically: true, encoding: .utf8)
        return otherURL
    }

    // MARK: failed save during the exit confirmation

    func testResolveExitSaveConflictKeepsEditingAndDropsContinuation() async throws {
        let model = try await makeModel()
        try await stageSaveConflict(model)

        var ran = false
        model.requestLeavingEditing { ran = true }
        await model.resolveExit(.save)

        XCTAssertFalse(ran, "the close/open continuation must not run when the save failed")
        XCTAssertEqual(model.mode, .editing)
        XCTAssertTrue(model.pendingConflict, "the conflict dialog must be able to run")
        XCTAssertTrue(model.isDirty)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "disk change")
    }

    func testToggleModeWithFailedSaveStaysInEditing() async throws {
        let model = try await makeModel()
        try await stageSaveConflict(model)

        model.toggleMode() // raises the confirmation dialog
        XCTAssertTrue(model.pendingExitResolution)
        await model.resolveExit(.save)

        XCTAssertEqual(model.mode, .editing, "a failed save must not flip back to reading")
        XCTAssertTrue(model.pendingConflict)
    }

    // MARK: opening a document while dirty

    func testOpenDocumentWhileDirtyPromptsAndRevertOpensNewFile() async throws {
        let model = try await makeModel()
        let otherURL = try makeOtherFile()
        model.toggleMode()
        model.rawText = "dirty"

        await model.openDocument(at: otherURL)
        XCTAssertTrue(model.pendingExitResolution, "opening over a dirty document must prompt")
        XCTAssertEqual(model.fileURL, fileURL, "the current document stays until resolution")

        await model.resolveExit(.revert)
        try await waitFor { model.fileURL == otherURL }
        XCTAssertEqual(model.rawText, "other content")
        XCTAssertEqual(model.mode, .reading)
        XCTAssertFalse(model.pendingExitResolution)
    }

    func testOpenDocumentWhileDirtyCancelKeepsCurrentDocument() async throws {
        let model = try await makeModel()
        let otherURL = try makeOtherFile()
        model.toggleMode()
        model.rawText = "dirty"

        await model.openDocument(at: otherURL)
        await model.resolveExit(.cancel)

        XCTAssertEqual(model.fileURL, fileURL)
        XCTAssertEqual(model.rawText, "dirty")
        XCTAssertEqual(model.mode, .editing)
    }

    func testOpenDocumentWhileDirtyFailedSaveKeepsCurrentDocument() async throws {
        let model = try await makeModel()
        let otherURL = try makeOtherFile()
        try await stageSaveConflict(model)

        await model.openDocument(at: otherURL)
        await model.resolveExit(.save)

        XCTAssertEqual(model.fileURL, fileURL, "the open must be abandoned when the save failed")
        XCTAssertTrue(model.pendingConflict)
        XCTAssertEqual(model.rawText, "my edit")
    }

    func testOpenFileInFolderWhileDirtyPromptsAndCancelKeepsDocument() async throws {
        _ = try makeOtherFile()
        let model = DocumentModel()
        await model.openDocument(at: tempDir) // folder context: flow.md sorts first
        XCTAssertTrue(model.hasFolder)
        // FolderService lists through the resolved /private/var path; compare
        // symlink-resolved URLs.
        XCTAssertEqual(model.fileURL?.resolvingSymlinksInPath(), fileURL.resolvingSymlinksInPath())
        model.toggleMode()
        model.rawText = "dirty"

        await model.openFileInFolder(tempDir.appendingPathComponent("other.md"))
        XCTAssertTrue(model.pendingExitResolution)

        await model.resolveExit(.cancel)
        XCTAssertEqual(model.fileURL?.resolvingSymlinksInPath(), fileURL.resolvingSymlinksInPath())
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
