import SwiftUI

/// Segmented sidebar: Files | Outline (design spec §5). The Files segment is
/// hidden entirely when a single file is open.
struct SidebarView: View {

    @ObservedObject var model: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            if model.hasFolder {
                Picker("Sidebar", selection: segmentBinding) {
                    Text("Files").tag(DocumentModel.SidebarSegment.files)
                    Text("Outline").tag(DocumentModel.SidebarSegment.outline)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding([.horizontal, .top], 8)
                .accessibilityIdentifier("sidebar-segment")
            }

            switch model.sidebarSegment {
            case .files:
                if model.hasFolder {
                    FilesListView(model: model)
                } else {
                    OutlineListView(model: model)
                }
            case .outline:
                OutlineListView(model: model)
            }
        }
    }

    private var segmentBinding: Binding<DocumentModel.SidebarSegment> {
        Binding(
            get: { model.sidebarSegment },
            set: { model.setSegment($0) }
        )
    }
}
