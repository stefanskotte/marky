import Foundation

/// Watches a single file and calls `onChange` (on the main queue) when its
/// contents change. Survives atomic saves, where editors replace the file
/// (rename/delete) rather than writing to it.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    deinit { source?.cancel() }

    private func arm(attempt: Int = 0) {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File briefly missing during an atomic save: retry for a few seconds.
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.arm(attempt: attempt + 1)
                }
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let replaced = !src.data.intersection([.delete, .rename]).isEmpty
            if replaced {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.arm() }
            }
            self.scheduleChange()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        if attempt > 0 { scheduleChange() }
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
