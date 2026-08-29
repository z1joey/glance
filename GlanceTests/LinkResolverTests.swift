import XCTest
@testable import Glance

/// Tests for relative markdown link resolution: fragment/query stripping,
/// percent decoding, `..` traversal, and the `.md`/`.markdown` extension
/// gate (a link may open only a markdown file, never an arbitrary file).
final class LinkResolverTests: XCTestCase {

    private var tempDir: URL!
    private var folder: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("glance-link-tests-\(UUID().uuidString)")
        folder = tempDir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "sibling".write(to: folder.appendingPathComponent("sibling.md"), atomically: true, encoding: .utf8)
        try "spaced".write(to: folder.appendingPathComponent("with space.md"), atomically: true, encoding: .utf8)
        try "upper".write(to: tempDir.appendingPathComponent("up.markdown"), atomically: true, encoding: .utf8)
        try "plain".write(to: folder.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testResolvesSiblingMarkdownLink() throws {
        XCTAssertEqual(
            LinkResolver.resolve("sibling.md", baseURL: folder),
            folder.appendingPathComponent("sibling.md")
        )
    }

    func testResolvesTraversalAboveTheDocumentFolder() throws {
        XCTAssertEqual(
            LinkResolver.resolve("../up.markdown", baseURL: folder),
            tempDir.appendingPathComponent("up.markdown")
        )
    }

    func testStripsFragmentAndQueryAndDecodesPercentEscapes() throws {
        XCTAssertEqual(
            LinkResolver.resolve("sibling.md#section", baseURL: folder),
            folder.appendingPathComponent("sibling.md")
        )
        XCTAssertEqual(
            LinkResolver.resolve("with%20space.md?utm_source=doc", baseURL: folder),
            folder.appendingPathComponent("with space.md")
        )
    }

    func testRejectsExistingNonMarkdownTarget() throws {
        XCTAssertNil(
            LinkResolver.resolve("notes.txt", baseURL: folder),
            "a link may open only a markdown file"
        )
    }

    func testRejectsMissingTarget() throws {
        XCTAssertNil(LinkResolver.resolve("missing.md", baseURL: folder))
    }

    func testRejectsMalformedPercentEncoding() {
        XCTAssertNil(LinkResolver.resolve("sibling%2.md", baseURL: folder))
    }

    func testUppercaseExtensionsResolve() throws {
        try "cap".write(to: folder.appendingPathComponent("UPPER.MD"), atomically: true, encoding: .utf8)
        XCTAssertEqual(
            LinkResolver.resolve("UPPER.MD", baseURL: folder),
            folder.appendingPathComponent("UPPER.MD")
        )
    }
}
