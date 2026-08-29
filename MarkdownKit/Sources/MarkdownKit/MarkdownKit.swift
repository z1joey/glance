import Foundation

/// Renders markdown text into a complete, styled HTML document.
///
/// The whole public surface of MarkdownKit is "markdown text → styled HTML
/// document (string + bundled resources)". The package is webview-free and
/// UI-free: hosts (the app, the Quick Look extension, tests) supply the
/// webview. Rendering itself happens in the browser: the output embeds the
/// markdown source and the pipeline JavaScript; `js/pipeline.js` does the
/// actual markdown → DOM work when the page loads.
public enum MarkdownRenderer {

    /// How the document references its CSS/JS assets.
    ///
    /// WebKit fact (verified by tools/WebSmoke): under `WKWebView
    /// loadHTMLString` classic `file:` scripts load fine, but a module script
    /// with a `file:` URL never executes — the document has an opaque origin,
    /// so the module fetch fails the CORS check. That rules out referencing
    /// `pipeline.js` from a loaded string, hence three modes:
    public enum AssetEmbedding {
        /// Vendor scripts and the pipeline both referenced via `file:` URLs.
        /// Only usable from hosts with a real `file:` document origin
        /// (`loadFileURL`); `loadHTMLString` boots no pipeline in this mode.
        case referenced

        /// Vendor scripts referenced from the MarkdownKit bundle; pipeline.js
        /// inlined as an inline module script (inline modules need no fetch).
        /// Small HTML, boots under `loadHTMLString` — the app's mode.
        case hybrid

        /// Everything embedded in the HTML. Self-contained; for hosts that
        /// cannot load any external resource (the Quick Look reply).
        case inline
    }

    public enum MarkdownKitError: Error, Equatable {
        case missingResource(String)
        case unreadableResource(String)
    }

    /// Vendor scripts in strict load order — each file's globals must exist
    /// before the next loads (markdown-it first; markdown-it-katex needs the
    /// `katex` global).
    static let vendorScripts: [String] = [
        "markdown-it.min.js",
        "markdown-it-anchor.umd.js",
        "markdown-it-front-matter.js",
        "markdown-it-footnote.min.js",
        "markdown-it-task-lists.min.js",
        "katex.min.js",
        "markdown-it-katex.js",
        "js-yaml.min.js",
        "highlight.min.js",
        "mermaid.min.js",
    ]

    /// Build the full HTML document for `markdown`.
    ///
    /// - Parameters:
    ///   - markdown: raw document text (may include YAML front matter)
    ///   - embedding: asset delivery mode (see `AssetEmbedding`)
    ///   - title: document title for the HTML `<title>` element
    /// - Returns: complete HTML document source
    public static func html(
        markdown: String,
        embedding: AssetEmbedding = .hybrid,
        title: String = ""
    ) throws -> String {
        var template = try resourceString("template.html", subdir: nil)
        let theme = try resourceString("theme.css", subdir: nil)
        let katexCSS = try resourceString("katex.css", subdir: "js/vendor")
        let pipeline = try resourceString("pipeline.js", subdir: "js")

        template = template.replacingOccurrences(of: "<!--GLANCE:CSP-->", with: csp(for: embedding))
        template = template.replacingOccurrences(of: "<!--GLANCE:TITLE-->", with: htmlEscape(title))
        template = template.replacingOccurrences(
            of: "<!--GLANCE:STYLES-->",
            with: styles(theme: theme, katexCSS: katexCSS, embedding: embedding)
        )
        template = template.replacingOccurrences(
            of: "<!--GLANCE:FALLBACK-->",
            with: htmlEscape(markdown)
        )
        template = template.replacingOccurrences(
            of: "<!--GLANCE:SOURCE-->",
            with: sourcePayload(for: markdown)
        )
        template = template.replacingOccurrences(
            of: "<!--GLANCE:SCRIPTS-->",
            with: scripts(pipeline: pipeline, embedding: embedding)
        )
        return template
    }

    // MARK: - Template sections

    private static func csp(for embedding: AssetEmbedding) -> String {
        // Offline by construction: no remote origins. `file:` covers the
        // MarkdownKit bundle assets and document-relative images resolved
        // against the document's folder; `data:` covers fonts and small
        // inline images. No connect-src, so fetch/XHR/WebSocket are dead.
        let scriptSrc: String
        switch embedding {
        case .referenced, .hybrid: scriptSrc = "file: 'unsafe-inline'"
        case .inline: scriptSrc = "'unsafe-inline'"
        }
        return "<meta http-equiv=\"Content-Security-Policy\" content=\"" +
            "default-src 'none'; " +
            "script-src \(scriptSrc); " +
            "style-src file: 'unsafe-inline'; " +
            "img-src file: data:; " +
            "font-src data: file:; " +
            "connect-src 'none'; " +
            "base-uri 'none'; " +
            "form-action 'none'\">"
    }

    private static func styles(theme: String, katexCSS: String, embedding: AssetEmbedding) -> String {
        switch embedding {
        case .referenced, .hybrid:
            return [
                "<link rel=\"stylesheet\" href=\"\(bundleURL(for: "theme.css", subdir: nil))\">",
                "<link rel=\"stylesheet\" href=\"\(bundleURL(for: "katex.css", subdir: "js/vendor"))\">",
            ].joined(separator: "\n")
        case .inline:
            return [
                "<style>\(theme)</style>",
                "<style>\(katexCSS)</style>",
            ].joined(separator: "\n")
        }
    }

    private static func scripts(pipeline: String, embedding: AssetEmbedding) -> String {
        let vendor: [String]
        switch embedding {
        case .referenced, .hybrid:
            vendor = vendorScripts.map {
                "<script src=\"\(bundleURL(for: $0, subdir: "js/vendor"))\"></script>"
            }
        case .inline:
            vendor = vendorScripts.map {
                "<script>\(scriptSafe(try! resourceString($0, subdir: "js/vendor")))</script>"
            }
        }
        // The pipeline always ships as an inline module: an inline module
        // script executes without a fetch, which is what lets it boot under
        // loadHTMLString's opaque origin.
        let boot = "<script type=\"module\">\(scriptSafe(pipeline))</script>"
        return (vendor + [boot]).joined(separator: "\n")
    }

    /// The markdown source, embedded as JSON so the pipeline reads it without
    /// any HTML interpretation. `<`, `>`, `&` and line separators are escaped
    /// so the payload can never close its own script tag.
    private static func sourcePayload(for markdown: String) -> String {
        guard let data = try? JSONEncoder().encode(["text": markdown]),
              let json = String(data: data, encoding: .utf8) else {
            return "{\"text\":\"\"}"
        }
        let escaped = json
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return escaped
    }

    /// Escape a script body so the HTML parser cannot end it early.
    /// `<\/script` and `\x3C` are valid inside JS string literals and regexes,
    /// and the sequences we replace do not otherwise occur in executable code.
    private static func scriptSafe(_ source: String) -> String {
        source
            .replacingOccurrences(of: "</script", with: "<\\/script", options: [.caseInsensitive])
            .replacingOccurrences(of: "<!--", with: "\\x3C!--")
    }

    // MARK: - Resources

    private static func bundleURL(for name: String, subdir: String?) -> String {
        guard let url = resourceURL(name, subdir: subdir) else {
            return "about:invalid#missing-\(name)"
        }
        return url.absoluteString
    }

    /// Look a resource up under every layout SPM and Xcode produce for
    /// `.copy("Resources")`:
    /// `swift build` → `<bundle>/Resources/<path>` (flat bundle)
    /// Xcode         → `<bundle>/Contents/Resources/Resources/<path>`
    private static func resourceURL(_ name: String, subdir: String?) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        let candidates: [String?] = subdir.map { ["Resources/\($0)", $0] } ?? [nil, "Resources"]
        for candidate in candidates {
            if let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: candidate) {
                return url
            }
        }
        return nil
    }

    private static func resourceString(_ name: String, subdir: String?) throws -> String {
        guard let url = resourceURL(name, subdir: subdir) else {
            throw MarkdownKitError.missingResource(name)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MarkdownKitError.unreadableResource(name)
        }
    }

    private static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
