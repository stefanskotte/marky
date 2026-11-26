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
- **Tabs and folders**: a sidebar with **Files** (the project's Markdown files: the git repository, or
  the file's folder) and **Outline** (the headings). Clicking a file or a link shows it in the same tab;
  ⌘-click a link, or right-click a file, to open it in a new tab. Native macOS tabs: ⌘T new tab, ⌘W close,
  ⇧⌘[ / ⇧⌘] previous/next tab, ⌘1–⌘9 jump to a tab, ⌘[ / ⌘] back/forward. ⌘O also opens a folder (it
  shows the folder's README). Open tabs are restored at the next launch.
- Sidebar ⌃⌘S, Files ⌃⌘1, Outline ⌃⌘2
- Find with every match highlighted and a match count (⌘F, ⌘G, ⇧⌘G, ⌘E, Esc)
- Zoom (⌘+ / ⌘= / ⌘- / ⌘0), remembered between launches
- Links: web links open in your browser, links to other `.md` files open in Marky, `#anchors` scroll the page
- Relative images next to the file are shown
- Print / Save as PDF (⌘P), Export as HTML (⇧⌘E), Reveal in Finder (⇧⌘R), Open in Text Editor (⌥⌘O),
  Copy File Path (⌥⌘C), Reload (⌘R)
- Settings (⌘,): appearance (Auto / Light / Dark), font (System / Serif / Rounded / Monospaced), font size,
  line width, syntax highlighting, smart quotes, auto-reload, open files as tabs

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
| `Marky/` | The app: AppKit tab windows (`WindowManager`) hosting SwiftUI views, WKWebView, folder scanner, find/zoom bridge (`Resources/bridge.js`), settings |
| `QuickLook/` | Data-based Quick Look preview extension (sandboxed) |
| `scripts/make-icon.swift` | Recreates the app icon |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated) |

## Known limitations

- Quick Look uses the default style and follows the system appearance. It does not read the app's settings,
  because sharing them needs an App Group, which needs a signed team ID (see the backlog).
- Quick Look only shows images the sandbox lets it read (see the backlog). Remote images may not load there.
- The app isn't sandboxed, so it can read images and linked files next to the document.

## Backlog

- [ ] **Signing:** once the app is finished, sign with the enhance-it Apple Developer certificate
  (Developer ID + hardened runtime + notarisation). Then add an App Group so Quick Look uses the app's
  settings.
- [ ] **Themes and formats:** see which popular themes we can support (GitHub, GitLab, Obsidian, Typora,
  Bear and similar "hub" styles, maybe user CSS), and extra formats/extensions (Mermaid diagrams,
  KaTeX math, wiki-links, emoji shortcodes).
- [x] **Folder navigation and tabs:** Files sidebar + native tabs (⌘T / ⌘W), done 2026-11-26.
- [ ] **Quick Look doesn't show relative images**, e.g. `~/Devel/a500pico-usb/hardware/README.md`
  (`![top](out/render_angle.png)`). Likely cause: the sandboxed extension may only read the previewed file.
  Possible fix: a read-only temporary-exception entitlement for the home folder (allowed outside the App
  Store), then attach images as now.
