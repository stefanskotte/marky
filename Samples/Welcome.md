---
title: Welcome to Marky
author: Marky
---

# Welcome to Marky

Marky is a small, fast **Markdown viewer** for macOS. It renders *GitHub-flavoured* Markdown with
syntax highlighting, and watches the file so it updates while you edit it elsewhere.

> [!TIP]
> Press <kbd>⌘F</kbd> to search, <kbd>⌘+</kbd> / <kbd>⌘-</kbd> to zoom, and <kbd>⌃⌘S</kbd> for the outline.

## Links

- External: https://daringfireball.net/projects/markdown/ (opens in your browser)
- Another Markdown file: [Second page](Second.md) (opens in Marky)
- Same page: [jump to code](#code)

## Lists

1. First
2. Second
   - nested
   - items
3. Third

- [x] Render Markdown
- [x] Quick Look preview
- [ ] World domination

## Emoji

Shortcodes as on GitHub: :rocket: :white_check_mark: :warning: :tada: (but `:smile:` in code stays as typed).

## Code

```swift
struct Greeting {
    let name: String
    func say() -> String { "Hello, \(name)!" } // interpolation
}
```

```bash
brew install --cask marky   # not yet :)
```

Inline `code`, ~~strikethrough~~ and a footnote.[^1]

## Table

| Shortcut | Action          |
|---------:|-----------------|
|     ⌘F   | Find            |
|     ⌘G   | Find next       |
|     ⌘0   | Actual size     |
|     ⌘P   | Print / PDF     |

## Image

![Swatch](swatch.png)

> A plain quote, "with smart quotes" -- and dashes.

[^1]: Footnotes work too.
