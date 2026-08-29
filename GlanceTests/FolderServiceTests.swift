import XCTest
@testable import Glance

final class FolderServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-folderservice-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testListsTopLevelMarkdownFilesSortedByName() throws {
        try "b".write(to: tempDir.appendingPathComponent("beta.md"), atomically: true, encoding: .utf8)
        try "a".write(to: tempDir.appendingPathComponent("alpha.markdown"), atomically: true, encoding: .utf8)
        try "c".write(to: tempDir.appendingPathComponent("10.md"), atomically: true, encoding: .utf8)
        try "c".write(to: tempDir.appendingPathComponent("2.md"), atomically: true, encoding: .utf8)

        let files = try FolderService.markdownFiles(in: tempDir)
        XCTAssertEqual(files.map { $0.lastPathComponent }, ["2.md", "10.md", "alpha.markdown", "beta.md"])
    }

    func testIgnoresNonMarkdownAndNestedFiles() throws {
        try "x".write(to: tempDir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("readme.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: tempDir.appendingPathComponent("no-ext"), atomically: true, encoding: .utf8)

        let subdirectory = tempDir.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
        try "x".write(to: subdirectory.appendingPathComponent("deep.md"), atomically: true, encoding: .utf8)

        let files = try FolderService.markdownFiles(in: tempDir)
        XCTAssertEqual(files.map { $0.lastPathComponent }, ["notes.md"])
    }

    func testEmptyFolderYieldsEmptyList() throws {
        let files = try FolderService.markdownFiles(in: tempDir)
        XCTAssertTrue(files.isEmpty)
    }
}
