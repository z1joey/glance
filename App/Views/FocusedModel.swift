import SwiftUI
import AppKit

/// Routes menu commands to the focused window's `DocumentModel` —
/// no global singletons (design spec §3).
struct DocumentModelKey: FocusedValueKey {
    typealias Value = DocumentModel
}

extension FocusedValues {
    var documentModel: DocumentModel? {
        get { self[DocumentModelKey.self] }
        set { self[DocumentModelKey.self] = newValue }
    }
}
