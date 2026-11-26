# Marky

A small, fast Markdown viewer for macOS, written in Swift, with a Quick Look extension.

Markdown is rendered to HTML with [markdown-it](https://github.com/markdown-it/markdown-it) and
[highlight.js](https://highlightjs.org), both running inside JavaScriptCore. The app and the Quick Look
extension use the same renderer, so a file looks the same in both. Pages never run JavaScript of their
own, so a `<script>` in a Markdown file does nothing.

## Features

- GitHub-flavoured Markdown: tables, task lists, strikethrough, autolinks, footnotes, alerts
  (`> [!NOTE]` / TIP / IMPORTANT / WARNING / CAUTION), YAML front matter (folded away), raw HTML
- Syntax highlighting for 36 common languages, with light and dark palettes
- **Quick Look**: press Space on a `.md` file in Finder
- Reloads automatically when the file changes on disk, keeping your scroll position (works with editors
  that save by replacing the file)
- Outline sidebar built from the headings (⌃⌘S)
- Find with every match highlighted and a match count (⌘F, ⌘G, ⇧⌘G, ⌘E, Esc)
- Zoom (⌘+ / ⌘= / ⌘- / ⌘0), remembered between launches
- Links: web links open in your browser, links to other `.md` files open in Marky, `#anchors` scroll the page
- Relative images next to the file are shown
- Print / Save as PDF (⌘P), Export as HTML (⇧⌘E), Reveal in Finder (⇧⌘R), Open in Text Editor (⌥⌘O),
  Copy File Path (⌥⌘C), Reload (⌘R)
- Settings (⌘,): appearance (Auto / Light / Dark), font (System / Serif / Rounded / Monospaced), font size,
  line width, syntax highlighting, smart quotes, auto-reload, show outline in new windows

## Build

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
xcodebuild -project Marky.xcodeproj -scheme Marky -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/Marky.app /Applications/
open /Applications/Marky.app          # launch once so macOS registers the Quick Look extension
qlmanage -r                           # reset Quick Look if previews don't show up at once
```

To make Marky the default app for Markdown: Finder → Get Info on a `.md` file → Open with → Marky →
Change All…

`Samples/Welcome.md` covers every feature and is handy for checking a build.

## Layout

| Path | What |
|------|------|
| `Shared/` | Renderer (`MarkdownRenderer.swift`), JS libraries, `render.js`, `markdown.css`. Built into both targets |
| `Marky/` | The app: SwiftUI `DocumentGroup` viewer, WKWebView, find/zoom bridge (`Resources/bridge.js`), settings |
| `QuickLook/` | Data-based Quick Look preview extension (sandboxed) |
| `scripts/make-icon.swift` | Recreates the app icon |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated) |

## Known limitations

- Quick Look uses the default style and follows the system appearance. It does not read the app's settings,
  because sharing them needs an App Group, which needs a signed team ID (see the backlog).
- Quick Look only shows images the sandbox lets it read. Remote images may not load there.
- The app isn't sandboxed, so it can read images and linked files next to the document.

## Backlog

- [ ] **Signing:** once the app is finished, sign with the enhance-it Apple Developer certificate
  (Developer ID + hardened runtime + notarisation). Then add an App Group so Quick Look uses the app's
  settings.
- [ ] **Themes and formats:** see which popular themes we can support (GitHub, GitLab, Obsidian, Typora,
  Bear and similar "hub" styles, maybe user CSS), and extra formats/extensions (Mermaid diagrams,
  KaTeX math, wiki-links, emoji shortcodes).
- [ ] **Folder navigation and tabs:** projects often have several `.md` files in one folder. Add an easy way
  to browse the folder and switch between files, e.g. simple tabs, with ⌘T for a new tab and ⌘W to close.
  (Native window tabs already work through Window → Merge All Windows, but there's no ⌘T and no folder
  browser yet.)
