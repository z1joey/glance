import SwiftUI

/// The current document's headings, nested by level; clicking smooth-scrolls
/// to the anchor in the rendered view.
struct OutlineListView: View {

    @ObservedObject var model: DocumentModel

    var body: some View {
        Group {
            if model.outline.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(model.fileURL == nil ? "No document" : "No headings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.outline) { entry in
                    Text(entry.text)
                        .lineLimit(1)
                        .padding(.leading, CGFloat(entry.level - 1) * 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            model.requestScroll(to: entry)
                        }
                        .accessibilityIdentifier("outline-\(entry.id)")
                }
                .listStyle(.sidebar)
            }
        }
        .accessibilityIdentifier("outline-list")
    }
}
