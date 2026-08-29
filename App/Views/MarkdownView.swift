import SwiftUI
import WebKit

/// `NSViewRepresentable` wrapping `WKWebView`, loaded via
/// `loadHTMLString(html, baseURL: documentFolder)` so relative images resolve
/// against the document's directory; no temp files (design spec §3).
struct MarkdownView: NSViewRepresentable {

    let html: String
    let baseURL: URL?
    let renderToken: Int
    let zoom: Double
    let scrollRequest: OutlineEntry?
    let onOutline: ([OutlineEntry]) -> Void
    let onOpenLink: (String) -> Void
    let onScrollConsumed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onOutline: onOutline,
            onOpenLink: onOpenLink,
            onScrollConsumed: onScrollConsumed
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "glance")

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        // Let the page's own background (theme-aware) show through.
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear

        context.coordinator.webView = web
        context.coordinator.load(token: renderToken, html: html, baseURL: baseURL, zoom: zoom)
        return web
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onOutline = onOutline
        coordinator.onOpenLink = onOpenLink
        coordinator.onScrollConsumed = onScrollConsumed

        if coordinator.loadedToken != renderToken {
            coordinator.load(token: renderToken, html: html, baseURL: baseURL, zoom: zoom)
            return
        }
        if coordinator.desiredZoom != zoom {
            coordinator.desiredZoom = zoom
            coordinator.applyZoom()
        }
        if let request = scrollRequest, coordinator.appliedScrollId != request.id {
            coordinator.appliedScrollId = request.id
            coordinator.scrollTo(request.id)
            onScrollConsumed()
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        coordinator.webView = nil
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {

        weak var webView: WKWebView?
        var onOutline: ([OutlineEntry]) -> Void
        var onOpenLink: (String) -> Void
        var onScrollConsumed: () -> Void

        var loadedToken = -1
        var desiredZoom: Double = 1.0
        var appliedScrollId: String?

        init(onOutline: @escaping ([OutlineEntry]) -> Void,
             onOpenLink: @escaping (String) -> Void,
             onScrollConsumed: @escaping () -> Void) {
            self.onOutline = onOutline
            self.onOpenLink = onOpenLink
            self.onScrollConsumed = onScrollConsumed
        }

        func load(token: Int, html: String, baseURL: URL?, zoom: Double) {
            loadedToken = token
            desiredZoom = zoom
            appliedScrollId = nil
            webView?.loadHTMLString(html, baseURL: baseURL)
        }

        func applyZoom() {
            webView?.evaluateJavaScript(
                "window.__glance && window.__glance.setZoom(\(desiredZoom))",
                completionHandler: nil
            )
        }

        func scrollTo(_ id: String) {
            webView?.evaluateJavaScript(
                "window.__glance && window.__glance.scrollTo(\(jsonQuoted(id)))",
                completionHandler: nil
            )
        }

        private func jsonQuoted(_ s: String) -> String {
            guard let data = try? JSONEncoder().encode(s),
                  let quoted = String(data: data, encoding: .utf8) else {
                return "''"
            }
            return quoted
        }

        // MARK: script messages from pipeline.js

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "outline":
                if let entries = body["entries"] as? [[String: Any]] {
                    onOutline(OutlineParser.parse(entries))
                }
            case "openLink":
                if let href = body["href"] as? String {
                    onOpenLink(href)
                }
            case "rendered":
                applyZoom()
            default:
                break
            }
        }

        // MARK: navigation policy

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // All link activations are handled in JS and posted via the
            // bridge; never let the webview itself navigate (spec §5).
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
