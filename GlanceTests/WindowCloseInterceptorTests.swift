import XCTest
import AppKit
@testable import Glance

/// Window-free tests for the termination-gate pieces: `isDocumentClean`
/// mirrors the close handler, and the termination prompt is forwarded.
/// (`firstDirty(in:)`'s NSWindow traversal is AppKit glue — creating and
/// ordering real windows inside the unit-test host crashes CI runners, so
/// that path is exercised by the window-close/quit flow, not here.)
@MainActor
final class WindowCloseInterceptorTests: XCTestCase {

    func testIsDocumentCleanMirrorsTheCloseHandler() {
        let dirty = WindowCloseInterceptor()
        dirty.shouldCloseHandler = { false }
        XCTAssertFalse(dirty.isDocumentClean)

        let clean = WindowCloseInterceptor()
        clean.shouldCloseHandler = { true }
        XCTAssertTrue(clean.isDocumentClean)
    }

    func testTerminationPromptIsForwarded() {
        var prompted = false
        let interceptor = WindowCloseInterceptor()
        interceptor.terminationPromptRequested = { prompted = true }

        interceptor.terminationPromptRequested()
        XCTAssertTrue(prompted)
    }
}
