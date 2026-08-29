import SwiftUI

/// The current document's headings, nested by level. Clicking selects and
/// highlights the row (native List selection) and smooth-scrolls to the
/// anchor in the rendered view.
struct OutlineListView: View {

    @ObservedObject var model: DocumentModel
    @State private var selectedEntry: OutlineEntry?

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
                List(selection: $selectedEntry) {
                    ForEach(model.outline) { entry in
                        Text(entry.text)
                            .lineLimit(1)
                            .padding(.leading, CGFloat(entry.level - 1) * 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tag(entry)
                            .accessibilityIdentifier("outline-\(entry.id)")
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedEntry) { entry in
                    if let entry {
                        model.requestScroll(to: entry)
                    }
                }
                .onChange(of: model.renderToken) { _ in
                    selectedEntry = nil
                }
            }
        }
        .accessibilityIdentifier("outline-list")
    }
}
