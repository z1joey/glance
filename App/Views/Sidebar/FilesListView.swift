import SwiftUI

/// The open folder's markdown files; the current file is highlighted and a
/// click opens it (dirty-check routed through the model's confirmation flow).
struct FilesListView: View {

    @ObservedObject var model: DocumentModel

    var body: some View {
        List(selection: selection) {
            ForEach(model.folderFiles, id: \.self) { url in
                Label(url.lastPathComponent, systemImage: "doc.text")
                    .tag(url)
            }
        }
        .listStyle(.sidebar)
        .accessibilityIdentifier("files-list")
    }

    private var selection: Binding<URL?> {
        Binding(
            get: { model.fileURL },
            set: { newValue in
                guard let url = newValue, url != model.fileURL else { return }
                model.requestLeavingEditing {
                    Task { await model.openFileInFolder(url) }
                }
            }
        )
    }
}
