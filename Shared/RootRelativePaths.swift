import Foundation

/// GitHub reads an image or link path that starts with "/" (`<img src="/Images/board.jpg">`) from the
/// repository root, not the disk root. Many READMEs rely on that, so such paths are rewritten to the
/// project's folder when that is where the file is. A path that exists as written is left alone.
enum RootRelativePaths {
    private static let attribute = try! NSRegularExpression(
        pattern: #"(\b(?:src|href)=")(/[^/"][^"]*)(")"#, options: [.caseInsensitive])

    static func resolve(in html: String, document: URL) -> String {
        guard html.contains("=\"/") else { return html }
        let candidates = roots(for: document)
        let fm = FileManager.default
        let ns = html as NSString
        var result = ""
        var last = 0
        for match in attribute.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let valueRange = match.range(at: 2)
            let value = ns.substring(with: valueRange)
            result += ns.substring(with: NSRange(location: last, length: valueRange.location - last))
            last = valueRange.location + valueRange.length

            var replacement = value
            let path = (value.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? value)
                .replacingOccurrences(of: "&amp;", with: "&")
            if let decoded = path.removingPercentEncoding, !fm.fileExists(atPath: decoded),
               let root = candidates.first(where: { fm.fileExists(atPath: $0.path + decoded) }),
               let prefix = root.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
                replacement = prefix + value
            }
            result += replacement
        }
        result += ns.substring(from: last)
        return result
    }

    /// The git repository root when there is one (GitHub's meaning of "/"); otherwise, for a
    /// downloaded copy without .git, the document's folder and its parents up to the home folder.
    static func roots(for document: URL) -> [URL] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.standardizedFileURL.path
        var dir = document.deletingLastPathComponent().standardizedFileURL
        var chain: [URL] = []
        for _ in 0..<20 {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return [dir] }
            chain.append(dir)
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || dir.path == home || dir.path == "/" { break }
            dir = parent
        }
        return chain
    }
}
