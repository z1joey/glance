import XCTest
@testable import Glance

final class FileServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-fileservice-tests-\(UUID().uuidString)")
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

    // MARK: load

    func testLoadReadsUTF8TextAndModificationDate() async throws {
        let url = try write("# Hello\n", name: "hello.md")
        let loaded = try await FileService.load(at: url)
        XCTAssertEqual(loaded.text, "# Hello\n")
        let diskDate = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(loaded.modificationDate, diskDate)
    }

    func testLoadRejectsInvalidUTF8() async throws {
        let url = tempDir.appendingPathComponent("binary.md")
        try Data([0xFF, 0xFE, 0x00, 0x81, 0xC3]).write(to: url)
        do {
            _ = try await FileService.load(at: url)
            XCTFail("expected invalidUTF8")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .invalidUTF8)
        }
    }

    func testLoadRejectsOversizedFile() async throws {
        let url = tempDir.appendingPathComponent("huge.md")
        let oversized = FileService.maxFileSizeBytes + 1
        FileManager.default.createFile(atPath: url.path, contents: Data(count: oversized))
        do {
            _ = try await FileService.load(at: url)
            XCTFail("expected tooLarge")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .tooLarge)
        }
    }

    func testLoadMissingFileThrowsNotFound() async {
        let url = tempDir.appendingPathComponent("nope.md")
        do {
            _ = try await FileService.load(at: url)
            XCTFail("expected notFound")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: save

    func testSaveWritesAndReturnsNewModificationDate() async throws {
        let url = try write("old", name: "save.md")
        let loaded = try await FileService.load(at: url)
        let newDate = try await FileService.save("new text", to: url, expecting: loaded.modificationDate)
        let disk = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(disk, "new text")
        XCTAssertNotEqual(newDate, loaded.modificationDate)
    }

    func testSaveDetectsDiskConflict() async throws {
        let url = try write("v1", name: "conflict.md")
        let loaded = try await FileService.load(at: url)
        try await Task.sleep(nanoseconds: 20_000_000) // ensure mtime moves
        try "changed elsewhere".write(to: url, atomically: true, encoding: .utf8)
        do {
            _ = try await FileService.save("my edits", to: url, expecting: loaded.modificationDate)
            XCTFail("expected writeConflict")
        } catch let error as FileServiceError {
            XCTAssertEqual(error, .writeConflict)
        }
        // The conflicting write must not have happened.
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "changed elsewhere")
    }

    func testOverwriteBypassesConflictCheck() async throws {
        let url = try write("v1", name: "force.md")
        let newDate = try await FileService.overwrite("forced", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "forced")
        let diskDate = try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        XCTAssertEqual(newDate, diskDate)
    }

    // MARK: writability

    func testIsWritableReflectsFilePermissions() throws {
        let url = try write("ro", name: "readonly.md")
        XCTAssertTrue(FileService.isWritable(at: url))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        XCTAssertFalse(FileService.isWritable(at: url))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
    }
}
