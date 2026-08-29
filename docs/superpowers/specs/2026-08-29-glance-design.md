# Glance — Design Spec

**Date:** 2026-08-29 · **Status:** Approved design, pending implementation plan
**Platform:** macOS 13+ (Apple Silicon first) · **Distribution:** GitHub Releases, personal use

## 1. Summary

Glance is a minimal, keyboard-friendly macOS markdown reader. It renders markdown
read-only by default; a toolbar read/edit toggle (eye ⇄ pencil, `⌘L`) switches to
raw-source editing that saves back to the file. A built-in Quick Look extension makes **spacebar-in-Finder** show
the same rendering as the app. Opens a single file or a folder of files; a sidebar
navigates either the folder's files or the current document's heading outline.

## 2. Goals and Non-Goals

### In scope (MVP)

- GFM rendering: tables, task lists, strikethrough, autolinks
- Syntax-highlighted fenced code blocks
- YAML front matter rendered as a compact key/value table (keys in document order)
- Footnotes; math (`$…$` inline, `$$…$$` display); Mermaid diagrams
- Read-only by default; an eye ⇄ pencil toolbar toggle switches to raw source
  editing; save in place
- Finder spacebar preview via a Quick Look Preview Extension with identical styling
- Open a file or a folder (top-level `.md`/`.markdown` only); files in an
  opened folder are listed in the sidebar Files segment and opened by click
- Segmented sidebar: **Files** / **Outline** (see §5); Files segment hidden when a
  single file is open
- Keyboard-first; light/dark follows the system setting; zero network access

### Explicit non-goals (MVP)

WYSIWYG or split-pane editing · recursive folder scanning · cross-file or in-file
search · tabs · PDF/HTML export · Windows/Linux · any in-app spacebar behavior
(space is a Finder gesture) · keyboard file switching (users expect `↑/↓` to
scroll the document) · settings UI.

## 3. Architecture

One Xcode project, three targets, one shared rendering pipeline:

```
┌─────────────────────────────────────────────────┐
│                  Glance.app                     │
│  ┌───────────────┐     ┌──────────────────────┐ │
│  │ Glance (app)  │     │ GlanceQuickLook      │ │
│  │ SwiftUI shell │     │ (appex, sandboxed)   │ │
│ ┌┴──────┬────────┴┐   ┌┴─────────┬───────────┐ │
│ │window │ editor  │   │ Preview  │           │ │
│ │sidebar│         │   │ Provider │           │ │
│ └┬──────┴─────────┘   └┴─────────┬───────────┘ │
│  │        ┌─────────────┐        │             │
│  └───────►│ MarkdownKit │◄───────┘             │
│           │ (SPM pkg)   │                      │
│           │ template.html · theme.css ·      │
│           │ pipeline.js · vendored JS libs   │
│           └─────────────┘                      │
└─────────────────────────────────────────────────┘
```

### MarkdownKit (local Swift package)

A resource bundle consumed by both targets. Contains:

- `template.html` — document shell; injects a strict offline CSP meta tag;
  all assets load locally, no remote origins
- `theme.css` — the single visual theme; `prefers-color-scheme` handles dark mode
- `pipeline.js` — markdown-it plus plugins: `markdown-it-anchor` (heading ids),
  `markdown-it-front-matter`, `markdown-it-footnote`; `highlight.js` for code;
  `KaTeX` for math; `mermaid` for diagrams; `js-yaml` for front-matter parsing.
  All vendored (committed to the repo), version-pinned, updated manually.

The app and the Quick Look extension run the identical HTML/CSS/JS, which is what
guarantees the Finder preview looks the same as the app window.

### JS ↔ Swift contract

pipeline.js exposes:

- `render(markdown) → Promise` — renders body, front matter, and math/diagram
  containers; resolves when the DOM is stable (mermaid included)
- postMessage to Swift: `rendered`, `outline` (`[{level, text, id}]` in document
  order), `openLink` (relative `.md` links only)
- Swift → JS: `scrollTo(id)`, `setZoom(scale)`

### App target (SwiftUI)

- `DocumentModel` (`ObservableObject`): file URL, optional parent folder, raw
  text, read/edit state, dirty flag; owns load/save/revert and the mtime check
- `MarkdownView`: `NSViewRepresentable` wrapping `WKWebView`, loaded via
  `loadHTMLString(html, baseURL: documentFolder)` so relative images resolve
  against the document's directory; no temp files
- `SourceEditor`: native `TextEditor`, monospaced font at a fixed size, plain
  text — editing never touches the web pipeline; zoom applies to the rendered
  view only
- `Sidebar`: `NavigationSplitView` with a segmented control (Files | Outline)

### Quick Look extension

Standard `PreviewProvider` appex loading the same MarkdownKit bundle into a
WKWebView-backed `QLPreviewReply` (the approach proven by QLMarkdown). The
extension is sandboxed and receives read access to the previewed file only.

**Known limitation** (same as all QL markdown extensions): relative images may
not resolve inside Finder previews; they render as broken-image placeholders.

**Day-one spike (first implementation step):** build the appex skeleton,
ad-hoc sign the app, run `qlmanage -p sample.md`, and confirm macOS loads the
extension. If ad-hoc builds don't load extensions, the fallback is a paid
Apple Developer account with notarized builds — a cost decision, not a redesign.

## 4. File Handling

- Open: `⌘O` shows a panel accepting a file or a folder.
- A folder contributes its **top-level** `.md`/`.markdown` files, sorted by name.
  A single file behaves as a folder of one (no Files segment — §5).
- Files are read strictly as UTF-8. Invalid UTF-8 or binary → refusal alert.
- Files larger than 20 MB → refusal alert.
- Writes go through one model type using `FileManager` (the app is
  non-sandboxed by choice, personal distribution).

## 5. Window, Sidebar, and Keyboard

### Window

Title bar shows `filename` (single file) or `filename — folder`. Toolbar:
sidebar toggle (leading), read/edit button (trailing).

### Sidebar — segmented Files / Outline

- **Files segment** (visible only when a folder is open): the folder's markdown
  files; the current file is highlighted; clicking opens it.
- **Outline segment**: the current document's headings, nested by level;
  clicking smooth-scrolls to the anchor.
- `⌘1` / `⌘2` switch segments. When only a single file is open, the Files
  segment (and `⌘1`) is hidden entirely.

### Read/Edit button (mode toggle)

The toolbar's trailing button is the mode toggle, built from SF Symbols:

| State | Icon | Meaning |
|---|---|---|
| Reading (default) | `eye` | Rendered view; nothing editable |
| Editing | `pencil` | Raw source editor; standard edited-dot in close button |
| File unwritable on disk | `eye`, control disabled, tooltip "File is read-only on disk" | Viewing still works; pencil is unreachable — the control reflects real file permissions |

A tooltip always states the current mode; `⌘L` (or clicking) toggles.

### Keyboard map

| Key | Condition | Action |
|---|---|---|
| `⌘O` | always | Open file or folder |
| `⌘L` | always (if file is writable) | Toggle read / edit mode |
| `⌘S` | editing | Save |
| `↑/↓` | reading | Scroll the document up / down (native scroll) |
| `↑/↓` | editing | Caret movement |
| `⌘1/⌘2` | folder open | Sidebar segment: Files / Outline |
| `⌘+ / ⌘− / ⌘0` | reading | Zoom rendered text |
| `⌘W` | always | Close window |

### Links and references

- `http(s)` links → default browser (navigation cancelled in the webview)
- Relative links to `.md`/`.markdown` → opened in Glance
- `#anchor` links → smooth scroll
- Relative images resolve against the document's folder (app only — see §3
  limitation for the extension)

## 6. Read/Edit State Machine

Transitions:

- **Open file** → reading (always, even if previously edited)
- **Reading → editing** (`⌘L`, click the eye/pencil button): swap webview for
  source editor
- **Editing → save** (`⌘S`): write to disk; before writing, compare stored
  mtime — if the file changed on disk, prompt *Overwrite / Reload / Cancel*
- **Editing → reading, window close, or clicking another file in the Files
  segment while dirty**: prompt *Save / Revert / Cancel*. There is no keyboard
  file switching; the sidebar is the only way to change files within a folder.
- **File > Revert to Saved**: available while dirty; discards edits and reloads

## 7. Error Handling

| Case | Behavior |
|---|---|
| Not valid UTF-8 / binary | Refusal alert; nothing rendered |
| File > 20 MB | Refusal alert |
| Missing image | Broken-image placeholder |
| Mermaid syntax error | mermaid.js error box inside the diagram; page unaffected |
| KaTeX parse error | Error text inline at the expression; page unaffected |
| Pipeline JS fails to load | Fallback: plain native monospaced text + small warning banner |
| File changed on disk while open | At save time: *Overwrite / Reload / Cancel* |
| QL extension fails to load | Finder falls back to its generic text preview |

## 8. Testing

- **Pipeline (vitest, in-repo, Node):** snapshot tests of pipeline.js output —
  GFM features, highlighted code, front-matter table, footnotes, math markup,
  mermaid container, heading anchor ids. Primary guard against rendering
  regressions.
- **Swift XCTest:** `DocumentModel` (UTF-8/size guards, save/revert, mtime
  conflict), outline payload parsing, read/edit state-machine transitions,
  folder listing/sorting, segment-visibility rule.
- **XCUITest smoke:** open sample → switch to edit → type → save → assert file
  changed on disk; single-file window shows no Files segment.
- **Quick Look:** scripted manual `qlmanage -p sample.md` check each release.
- **CI (GitHub Actions, macOS runner):** typecheck/tests/build on every push;
  release workflow on `v*` tags builds an ad-hoc-signed, zipped `.app` and
  attaches it to a GitHub Release with `xattr -cr` instructions in the README.

## 9. Future Work (explicitly deferred)

Scrollspy current-section highlight in the Outline · custom themes/fonts ·
recursive folder scanning · search · export · notarized builds (if the QL spike
demands them) · Mermaid/KaTeX configuration.
