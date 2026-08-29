/*!
 * Glance markdown pipeline.
 *
 * Environment-agnostic by design: every third-party library is read lazily
 * from `globalThis` — in the app and the Quick Look extension the vendored
 * classic <script> tags provide them; under vitest the test file imports the
 * same pinned packages from node_modules and assigns them to globalThis.
 * This file never imports anything itself, so the identical source runs in
 * the browser (referenced or inlined) and under Node.
 */

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

/**
 * Classify a link href for Glance's click handling.
 * @returns {'anchor'|'external'|'markdown'|'other'}
 */
export function classifyLink(href) {
  const h = String(href || '').trim();
  if (h.startsWith('#')) return 'anchor';
  if (/^https?:\/\//i.test(h)) return 'external';
  const path = h.split('#')[0].split('?')[0];
  if (/(\.md|\.markdown)$/i.test(path)) return 'markdown';
  return 'other';
}

function inlineText(token) {
  if (!token.children) return token.content;
  return token.children.map((c) => c.content).join('');
}

function fenceRenderer(md) {
  return (tokens, idx) => {
    const token = tokens[idx];
    const lang = (token.info || '').trim().split(/\s+/)[0].toLowerCase();

    if (lang === 'mermaid') {
      return `<div class="glance-mermaid">${md.utils.escapeHtml(token.content)}</div>\n`;
    }

    const hljs = globalThis.hljs;
    let inner;
    let cls = 'hljs';
    if (lang) cls += ` language-${md.utils.escapeHtml(lang)}`;
    if (hljs && lang && hljs.getLanguage(lang)) {
      try {
        inner = hljs.highlight(token.content, { language: lang, ignoreIllegals: true }).value;
      } catch {
        inner = md.utils.escapeHtml(token.content);
      }
    } else {
      inner = md.utils.escapeHtml(token.content);
    }
    return `<pre><code class="${cls}">${inner}</code></pre>\n`;
  };
}

export function buildMarkdownIt(sinks) {
  const md = globalThis.markdownit({
    html: false,       // raw HTML is escaped — Glance renders markdown, not arbitrary HTML
    linkify: true,     // GFM autolinks
    typographer: false,
    breaks: false,
  });

  // Front matter must be stripped before anything else looks at the stream.
  md.use(globalThis.markdownitFrontMatter, (raw) => { sinks.frontMatterRaw = raw; });
  md.use(globalThis.markdownitTaskLists);
  md.use(globalThis.markdownitFootnote);
  md.use(globalThis.markdownitKatex);
  md.use(globalThis.markdownItAnchor); // assigns heading ids via a core rule (core.ruler.push)

  if (sinks.outline) {
    // Registered after the anchor rule, so heading ids are already set.
    md.core.ruler.push('glance_outline', (state) => {
      const tokens = state.tokens;
      for (let i = 0; i < tokens.length; i++) {
        const t = tokens[i];
        if (t.type !== 'heading_open' || !t.tag) continue;
        const level = parseInt(t.tag.slice(1), 10);
        if (!level) continue;
        const inline = tokens[i + 1];
        sinks.outline.push({
          level,
          text: inline ? inlineText(inline) : '',
          id: t.attrGet('id') || '',
        });
      }
    });
  }

  md.renderer.rules.fence = fenceRenderer(md);
  return md;
}

function displayValue(v) {
  if (Array.isArray(v)) {
    return v.map((x) => (x !== null && typeof x === 'object' ? JSON.stringify(x) : String(x))).join(', ');
  }
  if (v !== null && typeof v === 'object') return JSON.stringify(v);
  return String(v);
}

function parseFrontMatter(raw) {
  const jsyaml = globalThis.jsyaml;
  if (!raw || !jsyaml) return [];
  let doc;
  try {
    doc = jsyaml.load(raw);
  } catch {
    return []; // invalid front matter: render the body, skip the table
  }
  if (!doc || typeof doc !== 'object' || Array.isArray(doc)) return [];
  return Object.entries(doc).map(([key, value]) => ({ key: String(key), value: displayValue(value) }));
}

export function frontMatterTable(rows) {
  if (!rows || !rows.length) return '';
  const trs = rows
    .map((r) => `<tr><th scope="row">${escapeHtml(r.key)}</th><td>${escapeHtml(r.value)}</td></tr>`)
    .join('');
  return `<table class="glance-front-matter"><tbody>${trs}</tbody></table>`;
}

/**
 * Render markdown text.
 * @returns {Promise<{bodyHtml: string, frontMatter: Array<{key: string, value: string}>,
 *   frontMatterHtml: string, outline: Array<{level: number, text: string, id: string}>}>}
 */
export async function render(markdown) {
  const sinks = { outline: [], frontMatterRaw: null };
  const md = buildMarkdownIt(sinks);
  const bodyHtml = md.render(String(markdown));
  const frontMatter = parseFrontMatter(sinks.frontMatterRaw);
  return {
    bodyHtml,
    frontMatter,
    frontMatterHtml: frontMatterTable(frontMatter),
    outline: sinks.outline,
  };
}

/**
 * Replace .glance-mermaid containers under `root` with rendered SVG.
 * A failed diagram leaves an error box inside its container; the page and the
 * remaining diagrams are unaffected.
 */
export async function activateMermaid(root) {
  const mermaid = globalThis.mermaid;
  if (!mermaid || !root.querySelectorAll) return;
  const containers = Array.from(root.querySelectorAll('.glance-mermaid'));
  if (!containers.length) return;

  const dark = typeof matchMedia === 'function'
    && matchMedia('(prefers-color-scheme: dark)').matches;
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: dark ? 'dark' : 'neutral',
  });

  const renderOne = async (el, i) => {
    const source = el.textContent;
    try {
      const { svg } = await mermaid.render(`glance-mermaid-${i}`, source);
      el.innerHTML = svg;
    } catch (err) {
      const message = escapeHtml((err && err.message) || String(err));
      el.innerHTML = `<div class="glance-mermaid-error"><strong>Diagram error</strong> ${message}</div>`;
    }
  };
  await Promise.all(containers.map(renderOne));
}

function postMessage(payload) {
  // WKWebView script-message bridge; absent under vitest and in plain browsers.
  const bridge = typeof window !== 'undefined'
    && window.webkit && window.webkit.messageHandlers
    && window.webkit.messageHandlers.glance;
  if (bridge) bridge.postMessage(payload);
}

function scrollToId(doc, id) {
  const el = doc.getElementById(id);
  if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// Schemes handed to the host (opened via NSWorkspace); everything else in the
// 'other' bucket — relative images, arbitrary custom schemes — stays inert.
const EXTERNAL_APP_SCHEMES = /^(mailto|tel|sms):/i;

export function wireLinks(content, doc) {
  content.addEventListener('click', (ev) => {
    const anchor = ev.target && ev.target.closest ? ev.target.closest('a') : null;
    if (!anchor) return;
    const href = anchor.getAttribute('href');
    const kind = classifyLink(href);
    if (kind === 'other') {
      if (!EXTERNAL_APP_SCHEMES.test(href || '')) return; // e.g. image.png — leave inert
      ev.preventDefault();
      postMessage({ type: 'openLink', href });
      return;
    }
    ev.preventDefault();
    if (kind === 'anchor') {
      const id = decodeURIComponent((href || '').slice(1));
      scrollToId(doc, id);
    } else {
      // 'markdown' links are opened in Glance; 'external' ones in the browser.
      postMessage({ type: 'openLink', href });
    }
  });
}

function showFallback(doc, message) {
  doc.documentElement.classList.remove('glance-booted');
  const fallback = doc.getElementById('glance-fallback');
  if (fallback) fallback.style.display = 'block';
  const msg = doc.getElementById('glance-fallback-message');
  if (msg) msg.textContent = message;
}

/**
 * Browser entry point. Runs automatically when this module is loaded into the
 * document (referenced via <script type="module" src> or inlined); inert
 * under vitest because there is no #glance-content element.
 */
export async function mount(doc) {
  if (typeof doc === 'undefined' || !doc.getElementById('glance-content')) return;
  window.__glanceBooted = true;

  let markdown = '';
  try {
    const payload = JSON.parse(doc.getElementById('glance-source').textContent);
    markdown = String(payload.text || '');
  } catch (err) {
    showFallback(doc, 'Glance could not read the document payload.');
    return;
  }

  try {
    const { bodyHtml, frontMatterHtml, outline } = await render(markdown);
    doc.getElementById('glance-front-matter').innerHTML = frontMatterHtml;
    const content = doc.getElementById('glance-content');
    content.innerHTML = bodyHtml;
    await activateMermaid(content);

    doc.documentElement.classList.add('glance-booted');
    wireLinks(content, doc);
    window.__glance = {
      scrollTo: (id) => scrollToId(doc, id),
      setZoom: (scale) => doc.documentElement.style.setProperty('--glance-zoom', String(scale)),
    };
    postMessage({ type: 'outline', entries: outline });
    postMessage({ type: 'rendered' });
  } catch (err) {
    showFallback(doc, `Glance's renderer failed: ${err && err.message ? err.message : err}`);
  }
}

if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  mount(document);
}
