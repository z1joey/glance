import Foundation
import MarkdownKit

/// The view model for a reader window and the single owner of mutable
/// document state: mode, dirty flag, writability, raw text, mtime, outline,
/// sidebar segment and zoom. The read/edit rules (design spec §6) are
/// implemented here as a testable decision API — the UI only renders what
/// this model decides.
@MainActor
final class DocumentModel: ObservableObject {

    enum Mode: Equatable {
        case reading
        case editing
    }

    enum LeavingEditingDecision: Equatable {
        case proceed
        case needsConfirmation
    }

    enum LoadFailure: Equatable {
        case invalidUTF8
        case tooLarge
        case notFound
        case ioFailure(String)
    }

    enum SaveOutcome: Equatable {
        case saved
        case conflict
        case failure(String)
    }

    enum SidebarSegment: Equatable {
        case files
        case outline
    }

    /// How an unresolved "leave editing" confirmation was answered.
    enum ExitResolution {
        case save
        case revert
        case cancel
    }

    /// Anything the UI must surface as an alert (refusals, save errors).
    struct UserAlert: Equatable, Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    static let minZoom: Double = 0.5
    static let maxZoom: Double = 3.0
    private static let zoomStep: Double = 0.1

    // MARK: published state

    @Published private(set) var mode: Mode = .reading
    @Published private(set) var fileURL: URL?
    @Published private(set) var parentFolder: URL?
    @Published private(set) var folderFiles: [URL] = []
    @Published var rawText: String = ""
    @Published private(set) var savedText: String = ""
    @Published private(set) var isWritable: Bool = true
    @Published private(set) var outline: [OutlineEntry] = []
    @Published private(set) var loadFailure: LoadFailure?
    @Published private(set) var sidebarSegment: SidebarSegment = .outline
    @Published private(set) var zoom: Double = 1.0
    /// Incremented whenever the rendered HTML must be reloaded by the webview.
    @Published private(set) var renderToken: Int = 0
    /// True while the UI must present the Save / Revert / Cancel dialog.
    @Published private(set) var pendingExitResolution: Bool = false
    /// True after a save hit an mtime conflict; the UI must present
    /// Overwrite / Reload / Cancel.
    @Published private(set) var pendingConflict: Bool = false
    /// Refusals and failures, surfaced by the UI as a single alert.
    @Published private(set) var userAlert: UserAlert?
    /// Sidebar clicked a heading; the rendered view consumes and clears it.
    @Published var scrollRequest: OutlineEntry?

    private var pendingExitContinuation: (() -> Void)?

    // MARK: derived state

    var isDirty: Bool { rawText != savedText }
    var hasFolder: Bool { parentFolder != nil }
    var canEdit: Bool { fileURL != nil && isWritable }
    var fileName: String { fileURL?.lastPathComponent ?? "" }

    var windowTitle: String {
        guard let fileURL else { return "Glance" }
        if let parentFolder {
            return "\(fileURL.lastPathComponent) — \(parentFolder.lastPathComponent)"
        }
        return fileURL.lastPathComponent
    }

    /// Complete HTML document for the rendered view; rebuilt whenever the
    /// saved text changes (load, save, revert, reload).
    private(set) var renderedHTML: String = ""

    /// The document's folder — the base URL for relative images and links.
    var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    private var modificationDate: Date?

    // MARK: opening

    /// Open a file or a folder (⌘O, Finder, sidebar).
    /// A folder opens its first markdown file; a single file behaves as a
    /// folder of one with no Files segment.
    func openDocument(at url: URL) async {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        if exists && isDirectory.boolValue {
            await openFolder(at: url)
        } else {
            parentFolder = nil
            folderFiles = []
            await loadFile(at: url)
        }
    }

    /// Switch to another file of the open folder (sidebar Files segment).
    /// The caller resolves any unsaved-changes confirmation first.
    func openFileInFolder(_ url: URL) async {
        guard hasFolder else { return }
        await loadFile(at: url)
    }

    private func openFolder(at url: URL) async {
        do {
            folderFiles = try FolderService.markdownFiles(in: url)
        } catch {
            loadFailure = .ioFailure(error.localizedDescription)
            userAlert = UserAlert(
                title: "Can't open folder",
                message: error.localizedDescription
            )
            return
        }
        parentFolder = url
        sidebarSegment = .files
        if let first = folderFiles.first {
            await loadFile(at: first)
        } else {
            clearDocument()
        }
    }

    private func loadFile(at url: URL) async {
        do {
            let loaded = try await FileService.load(at: url)
            loadFailure = nil
            fileURL = url
            rawText = loaded.text
            savedText = loaded.text
            modificationDate = loaded.modificationDate
            isWritable = FileService.isWritable(at: url)
            mode = .reading
            outline = []
            sidebarSegment = hasFolder ? .files : .outline
            rebuildRenderedHTML()
        } catch let error as FileServiceError {
            // Refusal: the current document stays untouched (spec §7).
            loadFailure = Self.loadFailure(from: error)
            userAlert = UserAlert(
                title: "Can't open \(url.lastPathComponent)",
                message: Self.refusalMessage(for: loadFailure!)
            )
        } catch {
            loadFailure = .ioFailure(error.localizedDescription)
            userAlert = UserAlert(
                title: "Can't open \(url.lastPathComponent)",
                message: error.localizedDescription
            )
        }
    }

    private func clearDocument() {
        fileURL = nil
        rawText = ""
        savedText = ""
        modificationDate = nil
        isWritable = true
        mode = .reading
        outline = []
        renderedHTML = ""
        renderToken += 1
    }

    private static func loadFailure(from error: FileServiceError) -> LoadFailure {
        switch error {
        case .invalidUTF8: return .invalidUTF8
        case .tooLarge: return .tooLarge
        case .notFound: return .notFound
        case .unwritable: return .ioFailure("File is not writable")
        case .writeConflict: return .ioFailure("Write conflict")
        case .ioFailure(let message): return .ioFailure(message)
        }
    }

    private static func refusalMessage(for failure: LoadFailure) -> String {
        switch failure {
        case .invalidUTF8:
            return "This file is not valid UTF-8 text (it may be binary)."
        case .tooLarge:
            return "This file is larger than 20 MB."
        case .notFound:
            return "The file does not exist (or was moved)."
        case .ioFailure(let message):
            return message
        }
    }

    func dismissAlert() {
        userAlert = nil
    }

    private func rebuildRenderedHTML() {
        do {
            renderedHTML = try MarkdownRenderer.html(
                markdown: savedText,
                embedding: .hybrid,
                title: fileName
            )
        } catch {
            renderedHTML = ""
            userAlert = UserAlert(
                title: "Renderer resources missing",
                message: error.localizedDescription
            )
        }
        renderToken += 1
    }

    // MARK: read/edit state machine (spec §6)

    /// The testable decision API: may we leave editing without prompting?
    func leavingEditing() -> LeavingEditingDecision {
        isDirty ? .needsConfirmation : .proceed
    }

    /// Reading → editing. A no-op unless the file is open and writable.
    func enterEditing() {
        guard mode == .reading, canEdit else { return }
        mode = .editing
    }

    /// Dialog outcome "Revert": drop edits, show the rendered document.
    func discardChangesAndLeaveEditing() {
        rawText = savedText
        mode = .reading
    }

    /// Dialog outcome "Save": write, then leave editing.
    func saveChangesAndLeaveEditing() async {
        let outcome = await save()
        if outcome == .saved {
            mode = .reading
        }
    }

    /// ⌘L / toolbar toggle. Reading → editing directly; editing → reading
    /// only after the dirty-check (which may raise the confirmation dialog).
    func toggleMode() {
        if mode == .reading {
            enterEditing()
        } else {
            requestLeavingEditing { [weak self] in
                self?.mode = .reading
            }
        }
    }

    /// Run `continuation` (opening another file, leaving editing, closing the
    /// window) either immediately or, when dirty, after the UI resolves the
    /// Save / Revert / Cancel dialog via `resolveExit`.
    func requestLeavingEditing(then continuation: @escaping () -> Void) {
        switch leavingEditing() {
        case .proceed:
            continuation()
        case .needsConfirmation:
            pendingExitContinuation = continuation
            pendingExitResolution = true
        }
    }

    func resolveExit(_ resolution: ExitResolution) async {
        guard pendingExitResolution else { return }
        pendingExitResolution = false
        let continuation = pendingExitContinuation
        pendingExitContinuation = nil

        switch resolution {
        case .save:
            await saveChangesAndLeaveEditing()
            continuation?()
        case .revert:
            discardChangesAndLeaveEditing()
            continuation?()
        case .cancel:
            break
        }
    }

    /// ⌘S while editing: write to disk with mtime conflict detection.
    @discardableResult
    func save() async -> SaveOutcome {
        guard let fileURL, canEdit else {
            return .failure("No writable document")
        }
        do {
            let newDate = try await FileService.save(rawText, to: fileURL, expecting: modificationDate)
            modificationDate = newDate
            savedText = rawText
            isWritable = FileService.isWritable(at: fileURL)
            rebuildRenderedHTML()
            return .saved
        } catch let error as FileServiceError {
            switch error {
            case .writeConflict:
                pendingConflict = true
                return .conflict
            case .unwritable:
                userAlert = UserAlert(title: "Can't save", message: "File is read-only on disk.")
                return .failure("File is read-only on disk")
            case .ioFailure(let message):
                userAlert = UserAlert(title: "Can't save", message: message)
                return .failure(message)
            default:
                userAlert = UserAlert(title: "Can't save", message: error.localizedDescription)
                return .failure(error.localizedDescription)
            }
        } catch {
            userAlert = UserAlert(title: "Can't save", message: error.localizedDescription)
            return .failure(error.localizedDescription)
        }
    }

    /// Conflict dialog "Overwrite": force-write over the disk changes.
    func overwriteOnConflict() async {
        guard let fileURL, canEdit else { return }
        pendingConflict = false
        do {
            let newDate = try await FileService.overwrite(rawText, to: fileURL)
            modificationDate = newDate
            savedText = rawText
            rebuildRenderedHTML()
        } catch {
            userAlert = UserAlert(title: "Can't save", message: error.localizedDescription)
        }
    }

    /// Conflict dialog "Reload": drop edits, take the disk copy, back to reading.
    func reloadOnConflict() async {
        guard let fileURL else { return }
        pendingConflict = false
        await loadFile(at: fileURL)
    }

    /// Conflict dialog "Cancel": keep editing, resolve nothing.
    func cancelConflictResolution() {
        pendingConflict = false
    }

    /// File > Revert to Saved (available while dirty): discard edits and
    /// reload the disk copy, staying in the current mode.
    func revertToSaved() async {
        guard isDirty, let fileURL else { return }
        let previousMode = mode
        await loadFile(at: fileURL)
        mode = previousMode == .editing && canEdit ? .editing : .reading
    }

    // MARK: webview-fed state

    func applyOutline(_ entries: [OutlineEntry]) {
        outline = entries
    }

    func requestScroll(to entry: OutlineEntry) {
        scrollRequest = entry
    }

    func consumeScrollRequest() {
        scrollRequest = nil
    }

    // MARK: sidebar

    func setSegment(_ segment: SidebarSegment) {
        guard segment != .files || hasFolder else { return }
        sidebarSegment = segment
    }

    // MARK: zoom (rendered view only)

    func zoomIn() {
        setZoom(zoom + Self.zoomStep)
    }

    func zoomOut() {
        setZoom(zoom - Self.zoomStep)
    }

    func zoomReset() {
        setZoom(1.0)
    }

    private func setZoom(_ value: Double) {
        zoom = min(Self.maxZoom, max(Self.minZoom, (value * 10).rounded() / 10))
    }
}
