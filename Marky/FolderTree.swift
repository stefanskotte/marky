import Foundation

/// A node in the sidebar's file tree. Folders only appear if they (eventually)
/// contain Markdown files.
struct FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let children: [FileNode]?
    var id: URL { url }
}

enum FolderScanner {
    /// Folders that are never worth descending into.
    static let skippedFolders: Set<String> = [
        "node_modules", "build", "dist", "DerivedData", "Pods", "Carthage", "vendor", "target",
        "bower_components", "__pycache__", "venv", "coverage",
    ]

    static let maxEntries = 20_000
    static let maxDepth = 8

    static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext"].contains(url.pathExtension.lowercased())
    }

    /// The folder to show in the sidebar for a file: the enclosing git
    /// repository if there is one (so a project's docs/ are reachable),
    /// otherwise the file's own folder.
    static func projectRoot(for file: URL) -> URL {
        let folder = file.deletingLastPathComponent().standardizedFileURL
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        var dir = folder
        for _ in 0..<10 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path || dir.path == home || dir.path == "/" { break }
            dir = parent
        }
        return folder
    }

    /// The file to show when a folder is opened: its README/index, else the first Markdown file.
    static func defaultFile(in folder: URL) -> URL? {
        let fm = FileManager.default
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        let md = items.filter(isMarkdown).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for preferred in ["readme", "index"] {
            if let hit = md.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == preferred }) { return hit }
        }
        if let first = md.first { return first }
        // Nothing at the top level: take the first file anywhere below.
        return firstFile(in: scan(root: folder))
    }

    private static func firstFile(in nodes: [FileNode]) -> URL? {
        for node in nodes {
            if let children = node.children { if let hit = firstFile(in: children) { return hit } }
            else { return node.url }
        }
        return nil
    }

    static func scan(root: URL) -> [FileNode] {
        var budget = maxEntries
        return scan(folder: root.standardizedFileURL, depth: 0, budget: &budget)
    }

    private static func scan(folder: URL, depth: Int, budget: inout Int) -> [FileNode] {
        guard depth <= maxDepth, budget > 0 else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }
        budget -= items.count

        var folders: [FileNode] = []
        var files: [FileNode] = []
        for item in items {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            let name = item.lastPathComponent
            if values?.isDirectory == true {
                if skippedFolders.contains(name) || name.hasSuffix(".xcodeproj") || name.hasSuffix(".app") { continue }
                let children = scan(folder: item, depth: depth + 1, budget: &budget)
                if !children.isEmpty { folders.append(FileNode(url: item.standardizedFileURL, name: name, children: children)) }
            } else if isMarkdown(item) {
                files.append(FileNode(url: item.standardizedFileURL, name: name, children: nil))
            }
        }
        let order: (FileNode, FileNode) -> Bool = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return folders.sorted(by: order) + files.sorted(by: order)
    }
}
