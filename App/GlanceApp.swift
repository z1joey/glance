import SwiftUI
import AppKit

@main
struct GlanceApp: App {

    var body: some Scene {
        WindowGroup {
            ReaderWindowView()
        }
        .commands {
            GlanceCommands()
        }
    }
}

/// Menu commands routed to the focused window's DocumentModel.
struct GlanceCommands: Commands {

    @FocusedValue(\.documentModel) private var focusedModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open…") { Self.openDocumentPanel(to: focusedModel) }
                .keyboardShortcut("o")
        }

        CommandGroup(after: .saveItem) {
            // Menu items are deliberately not .disabled()'d on FocusedValue:
            // on current macOS the enable state of focused-value-driven menu
            // items is not re-evaluated reliably, while action closures read
            // the live model. The actions below no-op safely when
            // inapplicable; the toolbar reflects state per spec §5.
            Button("Save") {
                guard let model = focusedModel, model.canEdit, model.mode == .editing else { return }
                Task { _ = await model.save() }
            }
            .keyboardShortcut("s")

            Button("Revert to Saved") {
                guard let model = focusedModel else { return }
                Task { await model.revertToSaved() } // no-ops unless dirty
            }
        }

        CommandMenu("View") {
            Button("Toggle Read / Edit") {
                focusedModel?.toggleMode()
            }
            .keyboardShortcut("l")

            Divider()

            Button("Files") {
                focusedModel?.setSegment(.files)
            }
            .keyboardShortcut("1")

            Button("Outline") {
                focusedModel?.setSegment(.outline)
            }
            .keyboardShortcut("2")

            Divider()

            Button("Zoom In") { focusedModel?.zoomIn() }
                .keyboardShortcut("+")
            Button("Zoom Out") { focusedModel?.zoomOut() }
                .keyboardShortcut("-")
            Button("Actual Size") { focusedModel?.zoomReset() }
                .keyboardShortcut("0")
        }
    }

    /// ⌘O: one panel accepting a file or a folder (design spec §4).
    @MainActor
    static func openDocumentPanel(to model: DocumentModel?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [] // no filter: folders must stay selectable
        panel.message = "Choose a markdown file or a folder of them"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await model?.openDocument(at: url) }
        }
    }
}
