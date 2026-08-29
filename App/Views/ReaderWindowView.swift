import SwiftUI
import AppKit

/// The reader window: sidebar + webview-or-editor swap, toolbar mode toggle,
/// and all alerts (design spec §5–§7).
struct ReaderWindowView: View {

    @StateObject private var model = DocumentModel()
    @State private var closeInterceptor: WindowCloseInterceptor?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 360)
        } detail: {
            detail
        }
        .navigationTitle(model.windowTitle)
        .focusedValue(\.documentModel, model)
        .focusedSceneValue(\.documentModel, model)
        .toolbar { toolbar }
        .alert(item: alertBinding) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) { model.dismissAlert() }
            )
        }
        .confirmationDialog(
            "Do you want to save the changes you made to “\(model.fileName)”?",
            isPresented: exitResolutionBinding,
            titleVisibility: .visible
        ) {
            Button("Save") {
                Task { await model.resolveExit(.save) }
            }
            Button("Revert Changes", role: .destructive) {
                Task { await model.resolveExit(.revert) }
            }
            Button("Cancel", role: .cancel) {
                Task { await model.resolveExit(.cancel) }
            }
        } message: {
            Text("Your changes will be lost if you don't save them.")
        }
        .alert("File changed on disk", isPresented: conflictBinding) {
            Button("Overwrite") { Task { await model.overwriteOnConflict() } }
            Button("Reload") { Task { await model.reloadOnConflict() } }
            Button("Cancel", role: .cancel) { model.cancelConflictResolution() }
        } message: {
            Text("“\(model.fileName)” was modified by another application. Save anyway, reload the file, or cancel?")
        }
        .onOpenURL { url in
            Task { await model.openDocument(at: url) }
        }
        .onAppear(perform: handleLaunchHooks)
        .interceptWindowClose(
            shouldClose: { !model.isDirty },
            closePromptRequested: {
                model.requestLeavingEditing { [weak closeInterceptor] in
                    closeInterceptor?.performConfirmedClose()
                }
            },
            onInstalled: { closeInterceptor = $0 }
        )
    }

    // MARK: detail area

    @ViewBuilder
    private var detail: some View {
        switch model.mode {
        case .reading:
            MarkdownView(
                html: model.renderedHTML,
                baseURL: model.baseURL,
                renderToken: model.renderToken,
                zoom: model.zoom,
                scrollRequest: model.scrollRequest,
                onOutline: { model.applyOutline($0) },
                onOpenLink: { handleOpenLink($0) },
                onScrollConsumed: { model.consumeScrollRequest() }
            )
        case .editing:
            SourceEditorView(model: model)
        }
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.toggleMode()
            } label: {
                Image(systemName: modeIcon)
            }
            .disabled(model.mode == .reading && !model.canEdit)
            .help(modeTooltip)
            .accessibilityIdentifier("mode-toggle")
        }
    }

    private var modeIcon: String {
        model.mode == .editing ? "pencil" : "eye"
    }

    private var modeTooltip: String {
        if model.mode == .reading && !model.canEdit {
            return model.fileURL == nil
                ? "No document open"
                : "File is read-only on disk"
        }
        return model.mode == .editing
            ? "Editing — click or ⌘L to return to reading"
            : "Reading — click or ⌘L to edit the source"
    }

    // MARK: alerts

    private var alertBinding: Binding<DocumentModel.UserAlert?> {
        Binding(
            get: { model.userAlert },
            set: { _ in model.dismissAlert() }
        )
    }

    private var exitResolutionBinding: Binding<Bool> {
        Binding(
            get: { model.pendingExitResolution },
            set: { presented in
                if !presented {
                    Task { await model.resolveExit(.cancel) }
                }
            }
        )
    }

    private var conflictBinding: Binding<Bool> {
        Binding(
            get: { model.pendingConflict },
            set: { presented in
                if !presented, model.pendingConflict {
                    model.cancelConflictResolution()
                }
            }
        )
    }

    // MARK: links

    /// Handles the pipeline's `openLink` posts: http(s) opens in the default
    /// browser; relative `.md`/`.markdown` links open in Glance (spec §5).
    private func handleOpenLink(_ href: String) {
        if let url = URL(string: href), url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
            return
        }
        guard let target = resolveRelativeMarkdownLink(href) else { return }
        let openInPlace: () -> Void
        if model.hasFolder {
            openInPlace = { Task { await model.openFileInFolder(target) } }
        } else {
            openInPlace = { Task { await model.openDocument(at: target) } }
        }
        model.requestLeavingEditing(then: openInPlace)
    }

    private func resolveRelativeMarkdownLink(_ href: String) -> URL? {
        guard let base = model.baseURL else { return nil }
        var path = href.split(separator: "#", maxSplits: 1).first.map(String.init) ?? href
        path = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard let decoded = path.removingPercentEncoding else { return nil }

        var target = base
        for component in decoded.split(separator: "/") {
            if component == ".." {
                target.deleteLastPathComponent()
            } else if component != "." && !component.isEmpty {
                target.appendPathComponent(String(component))
            }
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        return target
    }

    // MARK: launch hooks (UI-test harness)

    private func handleLaunchHooks() {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["GLANCE_AUTOTEST_FILE"] {
            Task { await model.openDocument(at: URL(fileURLWithPath: path)) }
        }
        if let path = environment["GLANCE_AUTOTEST_FOLDER"] {
            Task { await model.openDocument(at: URL(fileURLWithPath: path)) }
        }
    }
}

