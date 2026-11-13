import Foundation

/// Calls `onChange` (debounced, on the main actor) when a file changes, however it is
/// saved: an editor that replaces the file shows up on its folder, an in-place write
/// (VS Code, scripts) only on the file itself. Both are watched again after every change:
/// a replaced file is a new inode, and the folder can be one too (`~/.config/paw` a symlink
/// that now points elsewhere, a dotfiles checkout moved or recreated). A file that is
/// missing for the moment is picked up again by its folder's events once it is back.
final class FileWatcher {
    let url: URL
    private let onChange: () -> Void
    private var folder: DispatchSourceFileSystemObject?
    private var file: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        reopen()
    }

    private func reopen() {
        folder?.cancel()
        file?.cancel()
        folder = source(url.deletingLastPathComponent().path, [.write, .rename, .delete])
        file = source(url.path, [.write, .extend, .rename, .delete])
    }

    func stop() {
        pending?.cancel()
        folder?.cancel()
        file?.cancel()
        folder = nil
        file = nil
    }

    private func source(_ path: String, _ mask: DispatchSource.FileSystemEvent) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: .main)
        s.setEventHandler { [weak self] in self?.changed() }
        s.setCancelHandler { close(fd) }
        s.resume()
        return s
    }

    private func changed(after ms: Int = 200) {
        pending?.cancel()
        // On the main actor: the reload touches AppKit and the window manager.
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(ms))
            guard let self, !Task.isCancelled else { return }
            reopen()
            onChange()
            // The folder is gone for now (a checkout being recreated): look again until it's back.
            if folder == nil { changed(after: 2000) }
        }
    }
}
