import AppKit
import SwiftUI

/// Intercepts ⌘W/window close while the document is dirty and routes it
/// through the model's Save / Revert / Cancel confirmation flow. The
/// original SwiftUI window delegate is preserved via forwarding.
final class WindowCloseInterceptor: NSObject, NSWindowDelegate {

    weak var originalDelegate: NSWindowDelegate?
    private weak var attachedWindow: NSWindow?
    var shouldCloseHandler: () -> Bool = { true }
    /// Called instead of closing when the window is dirty and the model must
    /// run its confirmation first. On confirmation, call `performConfirmedClose`.
    var closePromptRequested: () -> Void = {}
    /// Called from `applicationShouldTerminate` when the document is dirty:
    /// runs the same confirmation flow, and the continuation re-issues
    /// `NSApp.terminate` once the document is clean again.
    var terminationPromptRequested: () -> Void = {}
    private var forceClosing = false

    func install(on window: NSWindow) {
        attachedWindow = window
        originalDelegate = window.delegate
        window.delegate = self
    }

    /// True when the window's document has no unsaved changes.
    var isDocumentClean: Bool { shouldCloseHandler() }

    /// The first visible window whose document is dirty, in AppKit's window
    /// order — `applicationShouldTerminate` prompts for it and cancels quit.
    static func firstDirty(in windows: [NSWindow]) -> WindowCloseInterceptor? {
        for window in windows where window.isVisible {
            if let interceptor = window.delegate as? WindowCloseInterceptor,
               !interceptor.isDocumentClean {
                return interceptor
            }
        }
        return nil
    }

    /// Ask the window to close again, bypassing the dirty prompt.
    func performConfirmedClose() {
        forceClosing = true
        attachedWindow?.performClose(nil)
    }

    // Forward everything we don't implement to SwiftUI's delegate.
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || originalDelegate?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        originalDelegate
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if forceClosing {
            return true
        }
        if shouldCloseHandler() {
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }
        closePromptRequested()
        return false
    }
}

/// Finds the hosting NSWindow and installs a `WindowCloseInterceptor`.
struct WindowCloseInterceptorModifier: ViewModifier {

    let shouldClose: () -> Bool
    let closePromptRequested: () -> Void
    let terminationPromptRequested: () -> Void
    let onInstalled: (WindowCloseInterceptor?) -> Void

    func body(content: Content) -> some View {
        content.background(WindowAccessor(
            shouldClose: shouldClose,
            closePromptRequested: closePromptRequested,
            terminationPromptRequested: terminationPromptRequested,
            onInstalled: onInstalled
        ))
    }

    private struct WindowAccessor: NSViewRepresentable {

        let shouldClose: () -> Bool
        let closePromptRequested: () -> Void
        let terminationPromptRequested: () -> Void
        let onInstalled: (WindowCloseInterceptor?) -> Void

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator {
            var interceptor: WindowCloseInterceptor?
            var installed = false
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { [weak view] in
                guard let window = view?.window else { return }
                let interceptor = WindowCloseInterceptor()
                configure(interceptor, context: context)
                interceptor.install(on: window)
                context.coordinator.interceptor = interceptor
                context.coordinator.installed = true
                self.onInstalled(interceptor)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let interceptor = context.coordinator.interceptor else { return }
            configure(interceptor, context: context)
            if !context.coordinator.installed {
                DispatchQueue.main.async { [weak nsView] in
                    guard let window = nsView?.window else { return }
                    interceptor.install(on: window)
                    context.coordinator.installed = true
                    self.onInstalled(interceptor)
                }
            }
        }

        private func configure(_ interceptor: WindowCloseInterceptor, context: Context) {
            interceptor.shouldCloseHandler = shouldClose
            interceptor.closePromptRequested = closePromptRequested
            interceptor.terminationPromptRequested = terminationPromptRequested
        }
    }
}

extension View {
    /// Route window-close and app-termination through the model's dirty
    /// confirmation. `onInstalled` hands back the interceptor so the view can
    /// request the actual close once the user confirms.
    func interceptWindowClose(
        shouldClose: @escaping () -> Bool,
        closePromptRequested: @escaping () -> Void,
        terminationPromptRequested: @escaping () -> Void,
        onInstalled: @escaping (WindowCloseInterceptor?) -> Void
    ) -> some View {
        modifier(WindowCloseInterceptorModifier(
            shouldClose: shouldClose,
            closePromptRequested: closePromptRequested,
            terminationPromptRequested: terminationPromptRequested,
            onInstalled: onInstalled
        ))
    }
}
