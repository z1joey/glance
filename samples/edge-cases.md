# Edge Cases

Odd documents that should never crash the renderer.

## Empty and near-empty documents

The next section contains only whitespace, and the document after that only
front matter.

## Unusual content

A very long unbroken line:

supercalifragilisticexpialidocious-supercalifragilisticexpialidocious-supercalifragilisticexpialidocious-supercalifragilisticexpialidocious-supercalifragilisticexpialidocious

Unicode: 中文, العربية, ελληνικά, 🎉, combining diacritics: é.

HTML-looking text stays literal: `<b>not bold</b>`, `<!-- not a comment -->`.

Inline math with unicode: $α + β = γ$

| Wide | Table | With | Many | Columns | To | Force | Horizontal | Scrolling |
|------|-------|------|------|---------|----|-------|-----------|-----------|
| 1    | 2     | 3    | 4    | 5       | 6  | 7     | 8         | 9         |

```
fence with no language
```

Heading with trailing spaces and punctuation: ### What?! — it renders.
