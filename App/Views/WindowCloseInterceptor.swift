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
    private var forceClosing = false

    func install(on window: NSWindow) {
        attachedWindow = window
        originalDelegate = window.delegate
        window.delegate = self
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
    let onInstalled: (WindowCloseInterceptor?) -> Void

    func body(content: Content) -> some View {
        content.background(WindowAccessor(
            shouldClose: shouldClose,
            closePromptRequested: closePromptRequested,
            onInstalled: onInstalled
        ))
    }

    private struct WindowAccessor: NSViewRepresentable {

        let shouldClose: () -> Bool
        let closePromptRequested: () -> Void
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
                interceptor.shouldCloseHandler = self.shouldClose
                interceptor.closePromptRequested = self.closePromptRequested
                interceptor.install(on: window)
                context.coordinator.interceptor = interceptor
                context.coordinator.installed = true
                self.onInstalled(interceptor)
            }
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            guard let interceptor = context.coordinator.interceptor else { return }
            interceptor.shouldCloseHandler = shouldClose
            interceptor.closePromptRequested = closePromptRequested
            if !context.coordinator.installed {
                DispatchQueue.main.async { [weak nsView] in
                    guard let window = nsView?.window else { return }
                    interceptor.install(on: window)
                    context.coordinator.installed = true
                    self.onInstalled(interceptor)
                }
            }
        }
    }
}

extension View {
    /// Route window-close through the model's dirty confirmation.
    /// `onInstalled` hands back the interceptor so the view can request the
    /// actual close once the user confirms.
    func interceptWindowClose(
        shouldClose: @escaping () -> Bool,
        closePromptRequested: @escaping () -> Void,
        onInstalled: @escaping (WindowCloseInterceptor?) -> Void
    ) -> some View {
        modifier(WindowCloseInterceptorModifier(
            shouldClose: shouldClose,
            closePromptRequested: closePromptRequested,
            onInstalled: onInstalled
        ))
    }
}
