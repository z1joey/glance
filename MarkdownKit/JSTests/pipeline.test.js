// Environment setup: pipeline.js reads libraries lazily from globalThis
// (in the browser they are provided by classic vendor <script> tags; here the
// real pinned packages from node_modules stand in for them).
import markdownit from 'markdown-it';
import markdownItAnchor from 'markdown-it-anchor';
import markdownitFrontMatter from 'markdown-it-front-matter';
import markdownitFootnote from 'markdown-it-footnote';
import markdownitTaskLists from 'markdown-it-task-lists';
import markdownitKatex from '@vscode/markdown-it-katex';
import katex from 'katex';
import jsyaml from 'js-yaml';
import hljs from 'highlight.js/lib/common';

globalThis.markdownit = markdownit;
globalThis.markdownItAnchor = markdownItAnchor;
globalThis.markdownitFrontMatter = markdownitFrontMatter;
globalThis.markdownitFootnote = markdownitFootnote;
globalThis.markdownitTaskLists = markdownitTaskLists;
globalThis.markdownitKatex = markdownitKatex;
globalThis.katex = katex;
globalThis.jsyaml = jsyaml;
globalThis.hljs = hljs;

const { render, activateMermaid, classifyLink, wireLinks } = await import('../Sources/MarkdownKit/Resources/js/pipeline.js');

import { describe, it, expect } from 'vitest';

describe('render: GFM', () => {
  it('renders tables', async () => {
    const { bodyHtml } = await render('| a | b |\n|---|---|\n| 1 | 2 |\n');
    expect(bodyHtml).toContain('<table>');
    expect(bodyHtml).toContain('<th>a</th>');
    expect(bodyHtml).toContain('<td>2</td>');
  });

  it('renders task lists as checkboxes', async () => {
    const { bodyHtml } = await render('- [x] done\n- [ ] not done\n');
    expect(bodyHtml).toContain('contains-task-list');
    expect(bodyHtml).toContain('<input class="task-list-item-checkbox" checked="" disabled="" type="checkbox">');
    expect(bodyHtml).toContain('<input class="task-list-item-checkbox" disabled="" type="checkbox">');
  });

  it('renders strikethrough', async () => {
    const { bodyHtml } = await render('~~gone~~\n');
    expect(bodyHtml).toContain('<s>gone</s>');
  });

  it('autolinks bare URLs', async () => {
    const { bodyHtml } = await render('see https://example.com/x now\n');
    expect(bodyHtml).toContain('<a href="https://example.com/x"');
  });

  it('does not render raw HTML (escaped, XSS-safe)', async () => {
    const { bodyHtml } = await render('<script>alert(1)</script>\n\n<img src=x onerror=alert(1)>\n');
    expect(bodyHtml).not.toContain('<script>');
    expect(bodyHtml).not.toContain('<img src=x');
    expect(bodyHtml).toContain('&lt;script&gt;');
  });
});

describe('render: code highlighting', () => {
  it('wraps fenced code in hljs classes with highlighted spans', async () => {
    const { bodyHtml } = await render('```js\nconst x = 1;\n```\n');
    expect(bodyHtml).toContain('<pre><code class="hljs language-js">');
    expect(bodyHtml).toMatch(/<span class="hljs-(keyword|literal)"/);
  });

  it('renders unknown languages as escaped plain code', async () => {
    const { bodyHtml } = await render('```weirdlang\na < b\n```\n');
    expect(bodyHtml).toContain('class="hljs language-weirdlang"');
    expect(bodyHtml).toContain('a &lt; b');
  });
});

describe('render: front matter', () => {
  it('parses YAML front matter into a table, keys in document order', async () => {
    const md = '---\ntitle: Hello\nauthor: Jane\ntags:\n  - a\n  - b\ncount: 3\n---\n\n# Body\n';
    const { bodyHtml, frontMatterHtml, frontMatter } = await render(md);
    expect(frontMatter.map((r) => r.key)).toEqual(['title', 'author', 'tags', 'count']);
    expect(frontMatter[0].value).toBe('Hello');
    expect(frontMatter[2].value).toBe('a, b');
    expect(frontMatter[3].value).toBe('3');
    expect(frontMatterHtml).toContain('<table');
    expect(frontMatterHtml).toContain('<th scope="row">title</th>');
    expect(frontMatterHtml).toContain('>a, b<');
    expect(bodyHtml).not.toContain('title: Hello');
    expect(bodyHtml).toContain('<h1 id="body"');
  });

  it('omits the table when there is no front matter', async () => {
    const { frontMatterHtml, frontMatter } = await render('# Just a doc\n');
    expect(frontMatterHtml).toBe('');
    expect(frontMatter).toEqual([]);
  });

  it('survives invalid YAML by dropping the table', async () => {
    const md = '---\n: : : nope [\n---\n\n# Body\n';
    const { bodyHtml, frontMatterHtml } = await render(md);
    expect(frontMatterHtml).toBe('');
    expect(bodyHtml).toContain('<h1 id="body"');
  });
});

describe('render: footnotes', () => {
  it('renders footnote references and notes', async () => {
    const md = 'Text[^1]\n\n[^1]: The note.\n';
    const { bodyHtml } = await render(md);
    expect(bodyHtml).toContain('footnote-ref');
    expect(bodyHtml).toContain('footnotes');
    expect(bodyHtml).toContain('The note.');
  });
});

describe('render: math', () => {
  it('renders inline math with KaTeX markup', async () => {
    const { bodyHtml } = await render('Energy: $E=mc^2$.\n');
    expect(bodyHtml).toContain('class="katex"');
  });

  it('renders display math', async () => {
    const { bodyHtml } = await render('$$\n\\int_0^1 x\\,dx\n$$\n');
    expect(bodyHtml).toContain('katex-display');
  });

  it('keeps the page intact on KaTeX parse errors (error shown inline)', async () => {
    const { bodyHtml } = await render('Bad: $\\notacommand{x}$ end.\n');
    expect(bodyHtml).toContain('end.');
    expect(bodyHtml).toMatch(/katex-error|notacommand/);
  });
});

describe('render: mermaid container', () => {
  it('converts mermaid fences into a diagram container with escaped source', async () => {
    const src = 'graph TD\n  A["x < y"] --> B';
    const { bodyHtml } = await render('```mermaid\n' + src + '\n```\n');
    expect(bodyHtml).toContain('<div class="glance-mermaid">');
    expect(bodyHtml).toContain('graph TD');
    expect(bodyHtml).toContain('x &lt; y');
  });

  it('leaves ordinary fences alone', async () => {
    const { bodyHtml } = await render('```mermaid2\nnot a diagram\n```\n');
    expect(bodyHtml).not.toContain('glance-mermaid');
  });
});

describe('activateMermaid', () => {
  function fakeRoot(divs) {
    return { querySelectorAll: (sel) => (sel === '.glance-mermaid' ? divs : []) };
  }

  it('replaces each container with rendered SVG', async () => {
    const calls = [];
    globalThis.mermaid = {
      initialize: (cfg) => calls.push(['init', cfg]),
      render: async (id, src) => {
        calls.push(['render', id, src]);
        return { svg: `<svg data-id="${id}"/>` };
      },
    };
    const div = { textContent: 'graph TD', innerHTML: '' };
    await activateMermaid(fakeRoot([div]));
    expect(div.innerHTML).toContain('<svg data-id=');
    expect(calls[0][0]).toBe('init');
    expect(calls.filter((c) => c[0] === 'render').map((c) => c[2])).toEqual(['graph TD']);
    delete globalThis.mermaid;
  });

  it('shows an error box inside the container when the diagram is invalid, page unaffected', async () => {
    globalThis.mermaid = {
      initialize: () => {},
      render: async () => {
        throw new Error('Parse error');
      },
    };
    const div = { textContent: 'graph TD\n  broken', innerHTML: '' };
    await activateMermaid(fakeRoot([div]));
    expect(div.innerHTML).toContain('glance-mermaid-error');
    expect(div.innerHTML).toContain('Parse error');
    expect(div.innerHTML).not.toContain('graph TD');
    delete globalThis.mermaid;
  });

  it('is a no-op without containers', async () => {
    await activateMermaid(fakeRoot([]));
  });
});

describe('render: heading anchors and outline', () => {
  it('assigns anchor ids and returns the outline in document order', async () => {
    const md = '# Top\n\n## First\n\n### Nested\n\n## Second\n';
    const { bodyHtml, outline } = await render(md);
    expect(bodyHtml).toContain('<h2 id="first"');
    expect(outline).toEqual([
      { level: 1, text: 'Top', id: 'top' },
      { level: 2, text: 'First', id: 'first' },
      { level: 3, text: 'Nested', id: 'nested' },
      { level: 2, text: 'Second', id: 'second' },
    ]);
  });

  it('uniquifies duplicate heading ids in outline and anchors', async () => {
    const md = '## Dup\n\n## Dup\n';
    const { bodyHtml, outline } = await render(md);
    expect(bodyHtml).toContain('<h2 id="dup"');
    expect(bodyHtml).toContain('<h2 id="dup-1"');
    expect(outline.map((e) => e.id)).toEqual(['dup', 'dup-1']);
  });

  it('uses visible text (markup stripped) for outline entries', async () => {
    const md = '## **Bold** and `code`\n';
    const { outline } = await render(md);
    expect(outline).toEqual([{ level: 2, text: 'Bold and code', id: 'bold-and-code' }]);
  });
});

describe('classifyLink', () => {
  it.each([
    ['https://example.com', 'external'],
    ['http://example.com/a?b=c', 'external'],
    ['notes.md', 'markdown'],
    ['notes.markdown', 'markdown'],
    ['sub/dir/notes.md', 'markdown'],
    ['NOTES.MD', 'markdown'],
    ['notes.md#section', 'markdown'],
    ['#section', 'anchor'],
    ['image.png', 'other'],
    ['mailto:a@b.c', 'other'],
  ])('classifies %s as %s', (href, expected) => {
    expect(classifyLink(href)).toBe(expected);
  });
});

describe('wireLinks click handling', () => {
  // Fakes the DOM event path and the WKWebView bridge: wireLinks is wired to
  // a captured listener, clicks are dispatched by hand, and postMessage is
  // observed through a stand-in for window.webkit.messageHandlers.glance.
  function click(href) {
    const posted = [];
    let prevented = false;
    const handlers = {};
    const content = { addEventListener: (type, fn) => { handlers[type] = fn; } };
    const anchor = { getAttribute: (name) => (name === 'href' ? href : null) };
    const ev = {
      target: { closest: (sel) => (sel === 'a' ? anchor : null) },
      preventDefault: () => { prevented = true; },
    };
    globalThis.window = {
      webkit: { messageHandlers: { glance: { postMessage: (p) => posted.push(p) } } },
    };
    try {
      wireLinks(content, { getElementById: () => null });
      handlers.click(ev);
    } finally {
      delete globalThis.window;
    }
    return { posted, prevented };
  }

  it('posts markdown links to the host and prevents navigation', () => {
    const { posted, prevented } = click('notes.md');
    expect(prevented).toBe(true);
    expect(posted).toEqual([{ type: 'openLink', href: 'notes.md' }]);
  });

  it('posts external links to the host and prevents navigation', () => {
    const { posted, prevented } = click('https://example.com');
    expect(prevented).toBe(true);
    expect(posted).toEqual([{ type: 'openLink', href: 'https://example.com' }]);
  });

  it('forwards mailto links to the host instead of dead-ending', () => {
    const { posted, prevented } = click('mailto:a@b.c');
    expect(prevented).toBe(true);
    expect(posted).toEqual([{ type: 'openLink', href: 'mailto:a@b.c' }]);
  });

  it('forwards tel links to the host', () => {
    const { posted, prevented } = click('tel:+15550100');
    expect(prevented).toBe(true);
    expect(posted).toEqual([{ type: 'openLink', href: 'tel:+15550100' }]);
  });

  it('leaves non-forwarded other links inert (no preventDefault, no message)', () => {
    const { posted, prevented } = click('image.png');
    expect(prevented).toBe(false);
    expect(posted).toEqual([]);
  });
});
