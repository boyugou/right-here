import Foundation
import RightHereCore

/// Reads a file only as far as a config may go. The size is asked of the open file (`fstat`) and the read itself stops one
/// byte past the limit, so a file that grows meanwhile, or one that reports no size at all, cannot make `rh` read without
/// end; a file over the limit is never read, which is what keeps a 24 MB file in the sync folder from costing seconds of
/// parsing every time something looks at it.
enum BoundedRead {
    enum Outcome: Equatable {
        /// There is no such file (a link that points nowhere counts as none).
        case absent
        case data(Data)
        /// A file over the limit. Nothing of it was read.
        case tooLarge(bytes: Int)
        /// There, but it cannot be read: no permission, a folder, something that is not a regular file, an I/O error.
        case unreadable(reason: String)
    }

    static func read(_ file: URL, limit: Int = ConfigParser.maxBytes) -> Outcome {
        // O_NONBLOCK: opening a pipe must not wait for a writer that never comes.
        let descriptor = open(file.path, O_RDONLY | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT || errno == ENOTDIR { return .absent }
            return .unreadable(reason: String(cString: strerror(errno)))
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { return .unreadable(reason: String(cString: strerror(errno))) }
        switch info.st_mode & S_IFMT {
        case S_IFREG: break
        case S_IFDIR: return .unreadable(reason: "it is a folder, not a file")
        default: return .unreadable(reason: "it is not a regular file")
        }
        if info.st_size > limit { return .tooLarge(bytes: Int(info.st_size)) }
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count <= limit {
            let wanted = min(chunk.count, limit + 1 - data.count)
            let count = chunk.withUnsafeMutableBytes { Foundation.read(descriptor, $0.baseAddress, wanted) }
            if count < 0 {
                if errno == EINTR { continue }
                return .unreadable(reason: String(cString: strerror(errno)))
            }
            if count == 0 { break }
            data.append(contentsOf: chunk[0..<count])
        }
        // It grew while it was being read: what is known is that it is past the limit.
        return data.count > limit ? .tooLarge(bytes: data.count) : .data(data)
    }
}
