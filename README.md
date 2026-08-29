# Glance

A minimal, keyboard-friendly macOS markdown reader. Renders markdown
read-only by default; an eye ⇄ pencil toolbar toggle (`⌘L`) switches to raw
source editing that saves back to the file. A built-in Quick Look extension
makes **spacebar-in-Finder** show the same rendering as the app.

Design spec: [docs/superpowers/specs/2026-08-29-glance-design.md](docs/superpowers/specs/2026-08-29-glance-design.md)

## Features (MVP)

- GFM rendering: tables, task lists, strikethrough, autolinks
- Syntax-highlighted fenced code blocks
- YAML front matter rendered as a compact key/value table (keys in document order)
- Footnotes, math (`$…$` / `$$…$$` via KaTeX), Mermaid diagrams
- Read-only by default; eye ⇄ pencil editing with save, revert, and
  changed-on-disk conflict prompts
- Open a file or a folder (`⌘O`); folder files in the sidebar **Files**
  segment, document headings in **Outline** (`⌘1` / `⌘2`)
- Finder spacebar preview via a Quick Look preview extension with identical styling
- Keyboard-first, light/dark follows the system, zero network access (strict
  offline CSP; all JS vendored and committed)

## Repository layout

```
Glance.xcodeproj          generated from project.yml (xcodegen)
App/                      Glance.app target (SwiftUI, MVVM)
  GlanceApp.swift           @main, menus (⌘O / ⌘L / ⌘S / ⌘1 / ⌘2 / zoom)
  ViewModels/DocumentModel  read/edit state machine, dirty, mtime conflicts
  Views/                    reader window, WKWebView wrapper, editor, sidebar
  Services/                 FileService, FolderService, OutlineParser
QuickLookExtension/       GlanceQuickLook.appex (sandboxed, MarkdownKit only)
MarkdownKit/              local SPM package: markdown text → styled HTML
  Sources/…/Resources/      template.html, theme.css, js/pipeline.js, js/vendor/
  JSTests/                  vitest suite for pipeline.js (runs the same file as the app)
GlanceTests/              XCTest: model, services, outline parsing
GlanceUITests/            XCUITest smoke: open → edit → ⌘S → file changed
samples/                  kitchen-sink.md, edge-cases.md for dev + QL checks
tools/vendor-js.sh        pinned JS vendoring (updates js/vendor/)
tools/WebSmoke/           dev harness: renders a sample in a real WKWebView
```

## Building

Requirements: Xcode 15+ (developed on Xcode 26), macOS 13+, Node 18+ (JS
tests only).

```sh
# regenerate the project after editing project.yml (committed xcodeproj works as-is)
xcodegen generate

# build the app + Quick Look extension
xcodebuild -project Glance.xcodeproj -scheme Glance -configuration Debug build
```

The build is ad-hoc signed (`CODE_SIGN_IDENTITY="-"`) for local use.

## Tests

```sh
# pipeline tests (vitest — the primary rendering regression guard)
cd MarkdownKit/JSTests && npm install && npm test

# Swift unit + UI tests
xcodebuild -project Glance.xcodeproj -scheme Glance -destination 'platform=macOS' test

# rendering smoke in a real WKWebView (hybrid and inline asset modes)
swift run --package-path tools/WebSmoke WebSmoke hybrid samples/kitchen-sink.md
swift run --package-path tools/WebSmoke WebSmoke inline samples/kitchen-sink.md
```

## Quick Look extension

The appex renders with the identical MarkdownKit pipeline, so Finder's
spacebar preview matches the app window. To check it locally:

```sh
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Glance-*/Build/Products/Debug/Glance.app | head -1)
pluginkit -a "$APP/Contents/PlugIns/GlanceQuickLook.appex"   # register
qlmanage -p samples/kitchen-sink.md                          # preview
```

Open a `.md` file in Finder and press spacebar; the preview should show the
rendered document. (Known limitation, same as all QL markdown extensions:
relative images may not resolve inside Finder previews.)

### Quick Look troubleshooting (macOS 26 findings)

If Finder's spacebar preview spins forever or falls back to plain text, the
extension metadata must match all of the following (verified against a known
working extension, sbarex/QLMarkdown):

- `NSExtensionPrincipalClass` (not `NSExtensionMainClass`) in the appex
  Info.plist — current QL hosts resolve only this key.
- `QLIsDataBasedPreview: true` in `NSExtensionAttributes` — required for
  data-based previews (we return HTML data, not a file URL).
- `ENABLE_DEBUG_DYLIB: NO` on the appex target — Xcode 16+ splits Debug
  builds into a stub executable + debug dylib, which breaks the extension
  handshake.
- No `get-task-allow` in the *signed* entitlements (`CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO`);
  the appex must carry only `com.apple.security.app-sandbox`.
- Install the app to `/Applications`, register with
  `pluginkit -a …/GlanceQuickLook.appex`, and restart the daemon with
  `killall quicklookd`.

**Signing gate:** on macOS 26 the daemon launches an ad-hoc–signed appex but
never completes hosting it — `providePreview` is never called and Finder
falls back to the generic text preview. A Developer ID–signed, notarized
build (paid Apple Developer account) is required for the Finder preview to
render. Everything up to that gate is verified: registration, user approval
toggle (Login Items & Extensions), binary loading, and class resolution all
pass, and the exact reply HTML is proven renderable by `tools/WebSmoke` in
inline mode.

## Downloaded releases (ad-hoc signed)

Release zips are ad-hoc signed. Remove the quarantine attribute before
opening:

```sh
unzip Glance.zip
xattr -cr Glance.app
open Glance.app
```

If the Finder preview never picks up the extension, register it once:

```sh
pluginkit -a /path/to/Glance.app/Contents/PlugIns/GlanceQuickLook.appex
```

## Architecture notes

- **MarkdownKit is webview-free**: its whole public surface is "markdown text
  → styled HTML document". `pipeline.js` is an ES module with no imports —
  libraries come from `globalThis` (vendored classic `<script>` tags in the
  app, node_modules under vitest) so the identical file runs in both.
- **Asset delivery** (verified empirically with `tools/WebSmoke`): under
  `WKWebView.loadHTMLString`, classic `file:` scripts load fine but a module
  script with a `file:` URL never executes (opaque origin). Hence:
  - app → `.hybrid`: vendor scripts referenced from the bundle, pipeline.js
    inlined as an inline module
  - Quick Look → `.inline`: everything embedded, fonts as `data:` URLs
- **DocumentModel** owns all mutable state; the read/edit rules are a
  testable decision API (`leavingEditing()`, `requestLeavingEditing(then:)`,
  `resolveExit(_:)`) so prompt behavior is unit-tested without UI.
- Menu commands route to the focused window's model via `FocusedValue` +
  the responder chain; there are no global singletons.

### Known limitations

- On current macOS (26), SwiftUI does not reliably re-evaluate
  `@FocusedValue`-driven menu item enable states; the menu items stay
  enabled and no-op when inapplicable. The toolbar toggle does reflect state
  (disabled with a tooltip when the file is read-only on disk), as specified.
- Closing the window while dirty prompts Save / Revert / Cancel; quitting
  the whole app while dirty does not prompt yet.
- Relative images don't render in Finder previews (Quick Look host
  limitation).
