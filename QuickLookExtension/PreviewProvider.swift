import Foundation
import os
import Quartz
import UniformTypeIdentifiers
import MarkdownKit

/// Quick Look Preview Extension: renders markdown with the identical
/// MarkdownKit pipeline (inline embedding — the Quick Look reply host cannot
/// load external resources), so Finder's spacebar preview matches the app
/// window (design spec §3).
class PreviewProvider: QLPreviewProvider {

    private static let log = Logger(subsystem: "app.glance.Glance", category: "QuickLook")
    private static let contentSize = CGSize(width: 1000, height: 800)

    /// File-based trace (os_log is not readable in all debugging setups, and
    /// the sandbox blocks writing outside the container's own tmp). The file
    /// log is a debugging aid only — Release builds keep the os_log line.
    private static func trace(_ line: String) {
        log.info("providePreview: \(line, privacy: .public)")
        #if DEBUG
        let path = NSTemporaryDirectory() + "glance-ql-debug.log"
        let stamped = "\(Date()) \(line)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(Data(stamped.utf8))
        } else {
            try? Data("=== ql trace ===\n\(stamped)".utf8).write(to: URL(fileURLWithPath: path))
        }
        #endif
    }

    func providePreview(for request: QLFilePreviewRequest) throws -> QLPreviewReply {
        let url = request.fileURL
        let started = Date()
        Self.trace("entered for \(url.lastPathComponent)")

        // Size guard mirroring FileService (the extension must not depend on
        // app code, so the constant is local on purpose).
        let maxBytes = 20 * 1024 * 1024
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if size > maxBytes {
            Self.trace("refusing oversized file (\(size) bytes)")
            return Self.refusalReply(
                title: "File too large",
                message: "This file is larger than 20 MB, so Glance won't preview it."
            )
        }

        let data = try Data(contentsOf: url)
        guard let markdown = String(data: data, encoding: .utf8) else {
            Self.trace("refusing non-UTF-8 file")
            return Self.refusalReply(
                title: "Not a text file",
                message: "This file is not valid UTF-8 text (it may be binary)."
            )
        }

        let html = try MarkdownRenderer.html(
            markdown: markdown,
            embedding: .inline,
            title: url.lastPathComponent
        )
        Self.trace("rendered \(html.utf8.count) bytes in \(Date().timeIntervalSince(started))s — returning reply")
        return Self.htmlReply(html)
    }

    // MARK: replies

    private static func htmlReply(_ html: String) -> QLPreviewReply {
        QLPreviewReply(dataOfContentType: .html, contentSize: contentSize) { _ in
            Data(html.utf8)
        }
    }

    /// Small standalone refusal page (spec §7 refusal semantics, rendered
    /// inline because the QL host consumes plain HTML replies).
    private static func refusalReply(title: String, message: String) -> QLPreviewReply {
        let escaped: (String) -> String = { source in
            source
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"></head>
        <body style="font-family: -apple-system, sans-serif; background: #ffffff; \
        color: #1d1d1f; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0;">
          <div style="max-width: 26rem; padding: 2rem; text-align: center;">
            <h1 style="font-size: 1.1rem; margin: 0 0 0.5rem;">\(escaped(title))</h1>
            <p style="font-size: 0.9rem; color: #6e6e73; margin: 0;">\(escaped(message))</p>
          </div>
        </body>
        </html>
        """
        return htmlReply(html)
    }
}
