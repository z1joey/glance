import AppKit
import MarkdownKit
import WebKit

// Renders a markdown file through MarkdownKit into a real WKWebView using the
// same loading path as the app (loadHTMLString with the document folder as
// baseURL) and reports whether the pipeline booted and produced the expected
// DOM. Used to verify asset-embedding strategies; not shipped.
//
// usage: web-smoke <referenced|inline> [path/to/file.md]

final class SmokeDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let html: String
    let baseURL: URL
    var window: NSWindow?
    var webView: WKWebView?
    var outlineCount = 0
    var openLinks: [String] = []
    var didReport = false

    init(html: String, baseURL: URL) {
        self.html = html
        self.baseURL = baseURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "glance")
        config.userContentController.addUserScript(WKUserScript(
            source: "window.__lastError='';window.onerror=function(m){window.__lastError=String(m)};",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 700), configuration: config)
        web.navigationDelegate = self
        self.webView = web

        let win = NSWindow(contentRect: web.frame,
                           styleMask: [.titled, .closable],
                           backing: .buffered,
                           defer: false)
        win.contentView = web
        win.orderOut(nil)
        self.window = win

        Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
            let js = """
            (() => ({
              readyState: document.readyState,
              booted: window.__glanceBooted === true,
              hasMarkdownit: typeof window.markdownit,
              hasMermaid: typeof window.mermaid,
              hasHljs: typeof window.hljs,
              fallbackVisible: (() => { const f = document.getElementById('glance-fallback');
                                        return f ? getComputedStyle(f).display : 'missing'; })(),
              scripts: Array.from(document.scripts).map(s => s.src || 'inline').join(' | '),
              consoleLast: window.__lastError || '',
            }))()
            """
            self?.webView?.evaluateJavaScript(js) { result, error in
                print("SMOKE-RESULT diagnostics: \(String(describing: result ?? error))")
                print("SMOKE-VERDICT FAIL")
                exit(2)
            }
        }

        web.loadHTMLString(html, baseURL: baseURL)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("SMOKE-RESULT navigation failed: \(error.localizedDescription)")
        print("SMOKE-VERDICT FAIL")
        exit(3)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("SMOKE-RESULT provisional navigation failed: \(error.localizedDescription)")
        print("SMOKE-VERDICT FAIL")
        exit(3)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        switch type {
        case "outline":
            outlineCount = (body["entries"] as? [[String: Any]])?.count ?? 0
        case "openLink":
            if let href = body["href"] as? String { openLinks.append(href) }
        case "rendered":
            report(webView: message.webView)
        default:
            break
        }
    }

    private func report(webView: WKWebView?) {
        guard !didReport else { return }
        didReport = true
        let js = """
        (() => ({
          booted: window.__glanceBooted === true,
          bodyLength: (document.getElementById('glance-content') || {innerHTML: ''}).innerHTML.length,
          headings: document.querySelectorAll('[id].glance-content h1, h1[id], h2[id]').length,
          frontMatter: !!document.querySelector('.glance-front-matter'),
          hljsSpans: document.querySelectorAll('.hljs span[class^="hljs-"]').length,
          katex: document.querySelectorAll('.katex').length,
          mermaidSVGs: document.querySelectorAll('.glance-mermaid svg').length,
          taskItems: document.querySelectorAll('.task-list-item-checkbox').length,
          footnotes: !!document.querySelector('.footnotes'),
          zoomWorks: (() => { window.__glance && window.__glance.setZoom(1.25);
                             return document.documentElement.style.getPropertyValue('--glance-zoom'); })(),
        }))()
        """
        webView?.evaluateJavaScript(js) { result, error in
            if let error {
                print("SMOKE-RESULT evaluate failed: \(error.localizedDescription)")
                print("SMOKE-VERDICT FAIL")
                exit(4)
            }
            guard let stats = result as? [String: Any] else {
                print("SMOKE-RESULT unexpected evaluate result: \(String(describing: result))")
                print("SMOKE-VERDICT FAIL")
                exit(4)
            }
            print("SMOKE-RESULT \(stats)")
            print("SMOKE-RESULT outlineEntries=\(self.outlineCount) openLinks=\(self.openLinks)")

            let ok = (stats["booted"] as? Bool == true)
                && (stats["bodyLength"] as? Int ?? 0) > 200
                && (stats["hljsSpans"] as? Int ?? 0) > 0
                && (stats["katex"] as? Int ?? 0) >= 2
                && (stats["mermaidSVGs"] as? Int ?? 0) >= 1
                && (stats["frontMatter"] as? Bool == true)
                && (stats["taskItems"] as? Int ?? 0) >= 2
                && (stats["footnotes"] as? Bool == true)
                && self.outlineCount >= 3
            print("SMOKE-VERDICT \(ok ? "PASS" : "FAIL")")
            exit(ok ? 0 : 1)
        }
    }
}

let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "hybrid"
let path = args.count > 2 ? args[2] : "samples/kitchen-sink.md"

let embedding: MarkdownRenderer.AssetEmbedding = {
    switch mode {
    case "inline": return .inline
    case "referenced": return .referenced
    default: return .hybrid
    }
}()
let docURL = URL(fileURLWithPath: path)
guard let markdown = try? String(contentsOf: docURL, encoding: .utf8) else {
    print("SMOKE-RESULT cannot read \(path)")
    print("SMOKE-VERDICT FAIL")
    exit(5)
}
let html = try MarkdownRenderer.html(markdown: markdown, embedding: embedding, title: docURL.lastPathComponent)
print("SMOKE-RESULT html bytes: \(html.utf8.count), mode: \(mode)")

let app = NSApplication.shared
let delegate = SmokeDelegate(html: html, baseURL: docURL.deletingLastPathComponent())
app.delegate = delegate
app.run()
