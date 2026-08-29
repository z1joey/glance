import XCTest
@testable import Glance

final class OutlineParserTests: XCTestCase {

    func testParsesOutlineEntriesInDocumentOrder() {
        let payload: [[String: Any]] = [
            ["level": 1, "text": "Top", "id": "top"],
            ["level": 2, "text": "First", "id": "first"],
            ["level": 3, "text": "Nested & quoted", "id": "nested"],
        ]
        let entries = OutlineParser.parse(payload)
        XCTAssertEqual(entries, [
            OutlineEntry(level: 1, text: "Top", id: "top"),
            OutlineEntry(level: 2, text: "First", id: "first"),
            OutlineEntry(level: 3, text: "Nested & quoted", id: "nested"),
        ])
    }

    func testSkipsMalformedEntries() {
        let payload: [[String: Any]] = [
            ["level": 2, "text": "ok", "id": "ok"],
            ["level": "two", "text": "bad level", "id": "bad-level"],
            ["text": "missing level", "id": "missing-level"],
            ["level": 2, "id": "missing-text"],
            ["level": 2, "text": "missing id"],
        ]
        let entries = OutlineParser.parse(payload)
        XCTAssertEqual(entries, [OutlineEntry(level: 2, text: "ok", id: "ok")])
    }

    func testEmptyPayloadYieldsNoEntries() {
        XCTAssertTrue(OutlineParser.parse([]).isEmpty)
    }
}
