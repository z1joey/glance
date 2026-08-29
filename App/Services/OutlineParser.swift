import Foundation

/// Converts the outline payload posted by the pipeline JS
/// (`[{level, text, id}]`) into `OutlineEntry` values. Malformed entries are
/// skipped; document order is preserved.
enum OutlineParser {

    static func parse(_ payload: [[String: Any]]) -> [OutlineEntry] {
        payload.compactMap { entry in
            guard let level = entry["level"] as? Int,
                  let text = entry["text"] as? String,
                  let id = entry["id"] as? String else {
                return nil
            }
            return OutlineEntry(level: level, text: text, id: id)
        }
    }
}
