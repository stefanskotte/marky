import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Data-based Quick Look preview: the Markdown is rendered to a self-contained
/// HTML page. Local images that the sandbox lets us read are attached inline.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)

        guard let renderer = MarkdownRenderer() else { throw CocoaError(.fileReadUnknown) }
        let output = renderer.render(text)
        var attachments: [String: QLPreviewReplyAttachment] = [:]
        let body = Self.inlineLocalImages(in: output.html, relativeTo: url, attachments: &attachments)
        let page = MarkdownRenderer.page(body: body, title: url.lastPathComponent, style: PageStyle())

        let reply = QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            reply.attachments = attachments
            return Data(page.utf8)
        }
        reply.title = output.title ?? url.lastPathComponent
        return reply
    }

    private static let imgSrc = try! NSRegularExpression(
        pattern: #"(<img\b[^>]*?\bsrc=")([^"]+)(")"#, options: [.caseInsensitive])

    static func inlineLocalImages(in html: String, relativeTo fileURL: URL,
                                  attachments: inout [String: QLPreviewReplyAttachment]) -> String {
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in imgSrc.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let srcRange = match.range(at: 2)
            let src = ns.substring(with: srcRange)
                .replacingOccurrences(of: "&amp;", with: "&")
            result += ns.substring(with: NSRange(location: last, length: srcRange.location - last))
            last = srcRange.location + srcRange.length

            var replacement = ns.substring(with: srcRange)
            if !src.contains("://"), !src.hasPrefix("data:"), !src.hasPrefix("//"),
               let path = src.components(separatedBy: CharacterSet(charactersIn: "?#")).first?.removingPercentEncoding {
                let imageURL = path.hasPrefix("/")
                    ? URL(fileURLWithPath: path)
                    : URL(fileURLWithPath: path, relativeTo: fileURL.deletingLastPathComponent())
                if let data = try? Data(contentsOf: imageURL),
                   let type = UTType(filenameExtension: imageURL.pathExtension) {
                    let id = "img\(attachments.count)"
                    attachments[id] = QLPreviewReplyAttachment(data: data, contentType: type)
                    replacement = "cid:\(id)"
                }
            }
            result += replacement
        }
        result += ns.substring(from: last)
        return result
    }
}
