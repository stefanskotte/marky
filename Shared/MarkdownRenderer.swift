import Foundation
import JavaScriptCore

/// Renders Markdown to HTML with markdown-it + highlight.js running in
/// JavaScriptCore. Used by both the app and the Quick Look extension, so the
/// output is identical in both and needs no JavaScript in the page itself.
final class MarkdownRenderer {
    struct Heading: Identifiable, Hashable, Decodable {
        let level: Int
        let text: String
        let id: String
    }

    struct Output: Decodable {
        let html: String
        let headings: [Heading]
        let title: String?
    }

    struct Options {
        var highlightCode = true
        var smartTypography = true
    }

    private let context: JSContext
    private let renderFunction: JSValue

    private static var bundle: Bundle { Bundle(for: MarkdownRenderer.self) }

    init?() {
        guard let context = JSContext() else { return nil }
        var failed = false
        context.exceptionHandler = { _, exception in
            NSLog("Marky renderer JS error: \(exception?.toString() ?? "?")")
            failed = true
        }
        for name in ["markdown-it.min", "markdown-it-footnote.min", "highlight.min", "render"] {
            guard let url = Self.bundle.url(forResource: name, withExtension: "js"),
                  let source = try? String(contentsOf: url, encoding: .utf8) else {
                NSLog("Marky: missing resource \(name).js")
                return nil
            }
            context.evaluateScript(source, withSourceURL: url)
        }
        guard !failed, let fn = context.objectForKeyedSubscript("markyRender"), !fn.isUndefined else {
            return nil
        }
        self.context = context
        self.renderFunction = fn
    }

    func render(_ markdown: String, options: Options = Options()) -> Output {
        let opts: [String: Any] = ["highlight": options.highlightCode, "typographer": options.smartTypography]
        guard let json = renderFunction.call(withArguments: [markdown, opts])?.toString(),
              let data = json.data(using: .utf8),
              let output = try? JSONDecoder().decode(Output.self, from: data) else {
            let escaped = markdown
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            return Output(html: "<pre>\(escaped)</pre>", headings: [], title: nil)
        }
        return output
    }

    // MARK: - Page assembly

    static let stylesheet: String = {
        guard let url = bundle.url(forResource: "markdown", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return css
    }()

    /// Page-level JavaScript is never allowed: raw HTML in a Markdown file must
    /// not be able to run scripts.
    static let contentSecurityPolicy =
        "default-src 'none'; img-src * data: blob: marky-doc: cid:; media-src * marky-doc:; " +
        "style-src 'unsafe-inline'; font-src data: marky-doc:; script-src 'none'"

    static func page(body: String, title: String, style: PageStyle) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title))</title>
        <style>\(stylesheet)</style>
        <style id="marky-vars">\(style.css)</style>
        </head>
        <body>
        <article id="content">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

/// The user-adjustable typography, expressed as CSS variables.
struct PageStyle: Equatable {
    enum Font: String, CaseIterable, Identifiable {
        case system, serif, rounded, mono
        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "System"
            case .serif: "Serif"
            case .rounded: "Rounded"
            case .mono: "Monospaced"
            }
        }
        var css: String {
            switch self {
            case .system: "-apple-system, BlinkMacSystemFont, \"Helvetica Neue\", sans-serif"
            case .serif: "ui-serif, \"New York\", Charter, Georgia, serif"
            case .rounded: "ui-rounded, \"SF Pro Rounded\", -apple-system, sans-serif"
            case .mono: "ui-monospace, \"SF Mono\", Menlo, monospace"
            }
        }
    }

    enum Width: String, CaseIterable, Identifiable {
        case narrow, medium, wide, full
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
        var css: String {
            switch self {
            case .narrow: "680px"
            case .medium: "860px"
            case .wide: "1100px"
            case .full: "none"
            }
        }
    }

    var font: Font = .system
    var fontSize: Double = 16
    var width: Width = .medium

    var css: String {
        ":root{--marky-font:\(font.css);--marky-size:\(Int(fontSize))px;--marky-width:\(width.css);}"
    }
}
