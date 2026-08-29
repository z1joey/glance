import XCTest
@testable import Glance

/// The read/edit state machine and its decision API, tested without UI.
@MainActor
final class DocumentModelTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-model-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func write(_ text: String, name: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeFolder(with files: [(String, String)]) throws -> URL {
        let folder = tempDir.appendingPathComponent("Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (name, text) in files {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        return folder
    }

    // MARK: opening

    func testOpenFileStartsInReadingMode() async throws {
        let url = try write("# Doc\n", name: "doc.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        XCTAssertEqual(model.mode, .reading)
        XCTAssertEqual(model.fileURL, url)
        XCTAssertEqual(model.rawText, "# Doc\n")
        XCTAssertFalse(model.isDirty)
        XCTAssertTrue(model.isWritable)
        XCTAssertNil(model.loadFailure)
        XCTAssertFalse(model.hasFolder)
        XCTAssertEqual(model.windowTitle, "doc.md")
    }

    func testOpenFolderListsFilesAndOpensFirstSorted() async throws {
        let folder = try makeFolder(with: [
            ("b.md", "B"), ("a.md", "A"), ("ignored.txt", "T"),
        ])
        let model = DocumentModel()
        await model.openDocument(at: folder)
        XCTAssertTrue(model.hasFolder)
        XCTAssertEqual(model.parentFolder, folder)
        XCTAssertEqual(model.folderFiles.map { $0.lastPathComponent }, ["a.md", "b.md"])
        XCTAssertEqual(model.fileURL?.lastPathComponent, "a.md")
        XCTAssertEqual(model.rawText, "A")
        XCTAssertEqual(model.windowTitle, "a.md — Folder")
        XCTAssertEqual(model.sidebarSegment, .files)
    }

    func testOpenInvalidUTF8SetsFailureWithoutTouchingCurrentDocument() async throws {
        let first = try write("# Good\n", name: "good.md")
        let model = DocumentModel()
        await model.openDocument(at: first)

        let bad = tempDir.appendingPathComponent("bad.md")
        try Data([0xFF, 0xFE, 0x81]).write(to: bad)
        await model.openDocument(at: bad)

        XCTAssertEqual(model.loadFailure, .invalidUTF8)
        XCTAssertEqual(model.fileURL, first)
        XCTAssertEqual(model.rawText, "# Good\n")
    }

    func testOpenOversizedFileSetsFailure() async throws {
        let big = tempDir.appendingPathComponent("big.md")
        FileManager.default.createFile(atPath: big.path, contents: Data(count: FileService.maxFileSizeBytes + 1))
        let model = DocumentModel()
        await model.openDocument(at: big)
        XCTAssertEqual(model.loadFailure, .tooLarge)
    }

    // MARK: mode transitions

    func testToggleToEditingAndDirtyTracking() async throws {
        let url = try write("v1", name: "mode.md")
        let model = DocumentModel()
        await model.openDocument(at: url)

        model.enterEditing()
        XCTAssertEqual(model.mode, .editing)

        model.rawText = "v1 edited"
        XCTAssertTrue(model.isDirty)
        XCTAssertEqual(model.leavingEditing(), .needsConfirmation)
    }

    func testCleanDocumentLeavesEditingWithoutConfirmation() async throws {
        let url = try write("v1", name: "clean.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        XCTAssertEqual(model.leavingEditing(), .proceed)
    }

    func testUnwritableFileCannotEnterEditing() async throws {
        let url = try write("ro", name: "ro.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        let model = DocumentModel()
        await model.openDocument(at: url)
        XCTAssertFalse(model.isWritable)
        XCTAssertFalse(model.canEdit)
        model.enterEditing()
        XCTAssertEqual(model.mode, .reading)
    }

    // MARK: leaving editing paths

    func testDiscardChangesRevertsTextAndLeavesEditing() async throws {
        let url = try write("v1", name: "discard.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "edited"

        model.discardChangesAndLeaveEditing()
        XCTAssertEqual(model.mode, .reading)
        XCTAssertEqual(model.rawText, "v1")
        XCTAssertFalse(model.isDirty)
    }

    func testSaveChangesAndLeaveEditingWritesToDisk() async throws {
        let url = try write("v1", name: "saveleave.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "v2"

        await model.saveChangesAndLeaveEditing()
        XCTAssertEqual(model.mode, .reading)
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "v2")
    }

    // MARK: saving and conflicts

    func testSaveWritesToDisk() async throws {
        let url = try write("v1", name: "save.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "saved text"

        let outcome = await model.save()
        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "saved text")
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.mode, .editing) // ⌘S keeps you in the editor
    }

    func testSaveDetectsFileChangedOnDisk() async throws {
        let url = try write("v1", name: "conflict-model.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "mine"

        try await Task.sleep(nanoseconds: 20_000_000)
        try "changed on disk".write(to: url, atomically: true, encoding: .utf8)

        let outcome = await model.save()
        XCTAssertEqual(outcome, .conflict)
        // Unresolved: the disk file still holds the foreign change.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "changed on disk")
    }

    func testOverwriteOnConflictWritesAndResumes() async throws {
        let url = try write("v1", name: "overwrite.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "mine"

        try await Task.sleep(nanoseconds: 20_000_000)
        try "changed on disk".write(to: url, atomically: true, encoding: .utf8)
        _ = await model.save()

        await model.overwriteOnConflict()
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "mine")
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.mode, .editing)
    }

    func testReloadOnConflictDiscardsEdits() async throws {
        let url = try write("v1", name: "reload.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "mine"

        try await Task.sleep(nanoseconds: 20_000_000)
        try "disk wins".write(to: url, atomically: true, encoding: .utf8)
        _ = await model.save()

        await model.reloadOnConflict()
        XCTAssertEqual(model.rawText, "disk wins")
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.mode, .reading)
    }

    // MARK: revert

    func testRevertToSavedWhileDirty() async throws {
        let url = try write("v1", name: "revert.md")
        let model = DocumentModel()
        await model.openDocument(at: url)
        model.enterEditing()
        model.rawText = "edited"

        await model.revertToSaved()
        XCTAssertEqual(model.rawText, "v1")
        XCTAssertFalse(model.isDirty)
        XCTAssertEqual(model.mode, .editing)
    }

    // MARK: opening another file from the sidebar

    func testOpenFileInFolderSwitchesDocument() async throws {
        let folder = try makeFolder(with: [("a.md", "AAA"), ("b.md", "BBB")])
        let model = DocumentModel()
        await model.openDocument(at: folder)

        let b = folder.appendingPathComponent("b.md")
        await model.openFileInFolder(b)
        XCTAssertEqual(model.fileURL, b)
        XCTAssertEqual(model.rawText, "BBB")
        XCTAssertEqual(model.mode, .reading)
    }

    // MARK: zoom

    func testZoomClampsAndResets() async throws {
        let url = try write("# z\n", name: "zoom.md")
        let model = DocumentModel()
        await model.openDocument(at: url)

        model.zoomIn(); model.zoomIn(); model.zoomIn()
        XCTAssertGreaterThan(model.zoom, 1.0)
        model.zoomOut(); model.zoomOut(); model.zoomOut(); model.zoomOut(); model.zoomOut()
        XCTAssertGreaterThanOrEqual(model.zoom, DocumentModel.minZoom)
        model.zoomReset()
        XCTAssertEqual(model.zoom, 1.0)
    }
}
