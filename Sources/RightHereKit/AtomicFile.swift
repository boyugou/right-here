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
        var mode: mode_t = 0o644
        var existing = stat()
        if stat(destination.path, &existing) == 0 { mode = existing.st_mode & 0o777 }
        if let forced { mode = forced }
        let temporary = try stage(data, besides: destination, mode: mode)
        do {
            try beforeRename?(temporary)
            guard rename(temporary.path, destination.path) == 0 else {
                throw WriteError(description: "cannot replace \(destination.path): \(String(cString: strerror(errno)))")
            }
        } catch {
            unlink(temporary.path)
            throw error
        }
    }

    enum Creation: Equatable {
        case created
        /// Something is already there, a file, a folder or a link (one that points nowhere included). It was not touched.
        case exists
    }

    /// Creates `destination` with `data` only when nothing has that name. The content is written beside it and then linked in:
    /// `link` fails with `EEXIST` for a name that is taken, so of several callers that race to create the same file exactly one
    /// succeeds and none replaces what another has just written (a check for the file followed by a write that renames over it
    /// lets the later one win), and a reader sees the whole file or none. `beforeLink` runs after the content is on disk; tests
    /// use it to put a file in the way at the last moment.
    static func createExclusively(_ data: Data, at destination: URL, mode: mode_t = 0o644, beforeLink: ((URL) throws -> Void)? = nil) throws -> Creation {
        let temporary = try stage(data, besides: destination, mode: mode)
        defer { unlink(temporary.path) }
        try beforeLink?(temporary)
        if link(temporary.path, destination.path) == 0 { return .created }
        if errno == EEXIST { return .exists }
        throw WriteError(description: "cannot create \(destination.path): \(String(cString: strerror(errno)))")
    }

    /// The content in a new file of its own beside the destination, on disk and closed.
    private static func stage(_ data: Data, besides destination: URL, mode: mode_t) throws -> URL {
        let folder = destination.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, mode)
        guard descriptor >= 0 else { throw WriteError(description: "cannot create \(temporary.path): \(String(cString: strerror(errno)))") }
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
        } catch {
            close(descriptor)
            unlink(temporary.path)
            throw error
        }
        close(descriptor)
        return temporary
    }
}
