import Foundation

/// One heading in the document outline, in document order.
/// `id` is the heading's HTML anchor id (unique per document).
struct OutlineEntry: Equatable, Hashable, Identifiable {
    let level: Int
    let text: String
    let id: String
}
