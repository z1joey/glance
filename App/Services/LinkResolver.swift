import Foundation

/// Resolves a rendered document's relative markdown links against the
/// document's folder (spec §5: relative `.md`/`.markdown` links open in
/// Glance). Fragment (`#`) and query (`?`) parts are ignored; percent
/// escapes are decoded. `..` traversal stays allowed — sibling links above
/// the document folder are legitimate.
enum LinkResolver {

    /// The extension gate is the containment control: a link may open only a
    /// markdown file, never an arbitrary readable file on disk.
    static let markdownExtensions = FolderService.markdownExtensions

    /// The resolved target, or nil when the link does not point at an
    /// existing markdown file.
    static func resolve(_ href: String, baseURL: URL) -> URL? {
        var path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        path = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard let decoded = path.removingPercentEncoding else { return nil }
        guard markdownExtensions.contains((decoded as NSString).pathExtension.lowercased()) else {
            return nil
        }

        var target = baseURL
        for component in decoded.split(separator: "/") {
            if component == ".." {
                target.deleteLastPathComponent()
            } else if component != "." && !component.isEmpty {
                target.appendPathComponent(String(component))
            }
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        return target
    }
}
