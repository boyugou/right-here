import Foundation

/// Replaces a file in one step: the new content is written beside it and renamed over it, so a reader (or a crash, or
/// an interrupted sync) sees the old file or the new one, never half of either. The temporary file is in the
/// destination's own folder because `rename` is atomic only within one volume.
enum AtomicFile {
    struct WriteError: Error, CustomStringConvertible {
        var description: String
    }

    /// `beforeRename` runs after the content is on disk and before it replaces the destination; tests use it to
    /// interrupt the write. A failure removes the temporary file and leaves the destination as it was.
    /// `mode` is the permission bits the file ends up with; without it a new file is 0644 and an existing one keeps the bits it has.
    static func write(_ data: Data, to destination: URL, mode forced: mode_t? = nil, beforeRename: ((URL) throws -> Void)? = nil) throws {
        let folder = destination.deletingLastPathComponent()
        var mode: mode_t = 0o644
        var existing = stat()
        if stat(destination.path, &existing) == 0 { mode = existing.st_mode & 0o777 }
        if let forced { mode = forced }
        let temporary = folder.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard descriptor >= 0 else { throw WriteError(description: "cannot create \(temporary.path): \(String(cString: strerror(errno)))") }
        var closed = false
        do {
            try data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                var offset = 0
                while offset < buffer.count {
                    let written = Foundation.write(descriptor, base + offset, buffer.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw WriteError(description: "cannot write \(temporary.path): \(String(cString: strerror(errno)))")
                    }
                    offset += written
                }
            }
            fchmod(descriptor, mode)
            fsync(descriptor)
            close(descriptor)
            closed = true
            try beforeRename?(temporary)
            guard rename(temporary.path, destination.path) == 0 else {
                throw WriteError(description: "cannot replace \(destination.path): \(String(cString: strerror(errno)))")
            }
        } catch {
            if !closed { close(descriptor) }
            unlink(temporary.path)
            throw error
        }
    }
}
