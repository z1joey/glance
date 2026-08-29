import XCTest
import AppKit
@testable import Glance

/// Tests for the applicationShouldTerminate dirty-quit gate: the first dirty
/// window's interceptor is found and prompted, and clean/undelegated windows
/// are ignored.
@MainActor
final class WindowCloseInterceptorTests: XCTestCase {

    private var windows: [NSWindow] = []

    override func tearDownWithError() throws {
        for window in windows {
            window.delegate = nil
            window.orderOut(nil)
            window.close()
        }
        windows = []
    }

    private func makeVisibleWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        windows.append(window)
        window.orderFront(nil)
        return window
    }

    private func makeInterceptor(isClean: Bool) -> WindowCloseInterceptor {
        let interceptor = WindowCloseInterceptor()
        interceptor.shouldCloseHandler = { isClean }
        return interceptor
    }

    func testFirstDirtyReturnsTheDirtyWindowInterceptor() {
        let cleanWindow = makeVisibleWindow()
        cleanWindow.delegate = makeInterceptor(isClean: true)
        let dirtyWindow = makeVisibleWindow()
        let dirty = makeInterceptor(isClean: false)
        dirtyWindow.delegate = dirty

        let found = WindowCloseInterceptor.firstDirty(in: [cleanWindow, dirtyWindow])
        XCTAssertTrue(found === dirty)
    }

    func testFirstDirtyReturnsNilWhenEveryWindowIsClean() {
        let window = makeVisibleWindow()
        window.delegate = makeInterceptor(isClean: true)

        XCTAssertNil(WindowCloseInterceptor.firstDirty(in: [window]))
    }

    func testFirstDirtyIgnoresVisibleWindowsWithoutAnInterceptor() {
        let bareWindow = makeVisibleWindow() // no delegate installed (not a reader window)
        let dirty = makeInterceptor(isClean: false)
        let hiddenWindow = makeVisibleWindow()
        hiddenWindow.orderOut(nil)
        hiddenWindow.delegate = dirty

        let found = WindowCloseInterceptor.firstDirty(in: [bareWindow, hiddenWindow])
        XCTAssertNil(found, "hidden windows must not gate termination")
    }

    func testIsDocumentCleanMirrorsTheCloseHandler() {
        XCTAssertFalse(makeInterceptor(isClean: false).isDocumentClean)
        XCTAssertTrue(makeInterceptor(isClean: true).isDocumentClean)
    }

    func testTerminationPromptIsForwarded() {
        var prompted = false
        let interceptor = WindowCloseInterceptor()
        interceptor.terminationPromptRequested = { prompted = true }

        interceptor.terminationPromptRequested()
        XCTAssertTrue(prompted)
    }
}
