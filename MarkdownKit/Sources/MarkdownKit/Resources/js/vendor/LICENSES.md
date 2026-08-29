# Vendored JS libraries

Committed by `tools/vendor-js.sh`; versions pinned there and mirrored in
`../../JSTests/package.json`. No CDN, no bundler — these files load locally.

| File | Package | Version | License |
|---|---|---|---|
| `markdown-it.min.js` | markdown-it | 14.1.0 | MIT |
| `markdown-it-anchor.umd.js` | markdown-it-anchor | 9.2.0 | MIT |
| `markdown-it-front-matter.js` | markdown-it-front-matter | 0.2.3 | MIT (CommonJS source wrapped in a UMD shim) |
| `markdown-it-footnote.min.js` | markdown-it-footnote | 4.0.0 | MIT |
| `markdown-it-task-lists.min.js` | markdown-it-task-lists | 2.1.1 | ISC |
| `markdown-it-katex.js` | @vscode/markdown-it-katex | 1.1.1 | MIT (CommonJS source wrapped in a UMD shim; resolves `katex` from the global) |
| `katex.min.js` | katex | 0.16.22 | MIT |
| `katex.css` | katex | 0.16.22 | MIT (woff2 fonts inlined as `data:` URLs by `tools/vendor-js.sh`) |
| `js-yaml.min.js` | js-yaml | 4.1.0 | MIT |
| `highlight.min.js` | @highlightjs/cdn-assets | 11.11.1 | BSD-3-Clause |
| `mermaid.min.js` | mermaid | 11.12.0 | MIT |

License texts ship in each npm package; see https://www.npmjs.com/package/<name>/v/<version>.
