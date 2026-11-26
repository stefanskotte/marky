import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Serves local files (images, etc.) referenced by the document. The page is
/// loaded with a `marky-doc://<path to file>` base URL, so relative references
/// resolve against the Markdown file's folder.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "marky-doc"

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let file = URL(fileURLWithPath: url.path)
        do {
            let data = try Data(contentsOf: file)
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            task.didReceive(data)
            task.didFinish()
        } catch {
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}

/// WKWebView that also accepts ⌘= for zoom in (US layouts, where ⌘+ needs Shift).
final class MarkyWebView: WKWebView {
    var onZoomIn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "=" {
            onZoomIn?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

struct MarkdownWebView: NSViewRepresentable {
    @ObservedObject var model: DocumentModel

    /// Runs in an isolated content world: the page itself never runs JavaScript.
    private static let bridgeScript: String = {
        guard let url = Bundle.main.url(forResource: "bridge", withExtension: "js"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> MarkyWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(), forURLScheme: LocalFileSchemeHandler.scheme)
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.userContentController.addUserScript(WKUserScript(
            source: Self.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))

        let webView = MarkyWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.pageZoom = DocumentModel.storedZoom
        webView.onZoomIn = { [weak model] in model?.zoomIn() }

        model.attach(webView)
        return webView
    }

    func updateNSView(_ nsView: MarkyWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: DocumentModel

        init(model: DocumentModel) { self.model = model }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            MainActor.assumeIsolated {
                if model.isLoadingPage { model.pageDidLoad() }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }

            // Our own loadHTMLString.
            if action.navigationType == .other && MainActor.assumeIsolated({ model.isLoadingPage }) {
                return decisionHandler(.allow)
            }
            // "Reload" from the context menu would fetch the raw file; re-render instead.
            if action.navigationType == .reload {
                decisionHandler(.cancel)
                MainActor.assumeIsolated { model.reloadFromDisk() }
                return
            }
            // In-page anchors (#heading, footnotes).
            if url.fragment != nil, url.scheme == LocalFileSchemeHandler.scheme,
               url.path == MainActor.assumeIsolated({ model.fileURL.path }) {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated || action.targetFrame == nil {
                let newTab = action.modifierFlags.contains(.command) || action.targetFrame == nil
                MainActor.assumeIsolated { model.open(link: url, inNewTab: newTab) }
            }
        }

        // target="_blank" links.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url {
                MainActor.assumeIsolated { model.open(link: url, inNewTab: true) }
            }
            return nil
        }
    }
}
