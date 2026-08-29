import SwiftUI

/// Native monospaced plain-text editor for read/edit mode. Editing never
/// touches the web pipeline; zoom applies to the rendered view only (§3/§5).
struct SourceEditorView: View {

    @ObservedObject var model: DocumentModel

    var body: some View {
        TextEditor(text: $model.rawText)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
            .accessibilityIdentifier("source-editor")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
