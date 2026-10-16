import Foundation

/// The UUIDs of the code in a Mach-O file: the `LC_UUID` load command of each architecture of a universal binary. The crash report macOS writes for a program names
/// the one of the code that crashed (`slice_uuid`, the first line of an `.ips` file), so the two say whether a crash is of this build or of another copy of the program.
enum MachOUUID {
    /// Reads `length` bytes at `offset`, or `nil` when the file ends before.
    typealias Reader = (_ offset: Int, _ length: Int) -> Data?

    /// The UUIDs, lower case and hyphenated as a crash report writes them, or `nil` for a file that is not a Mach-O file or cannot be read.
    static func uuids(ofFileAt path: String) -> Set<String>? {
        guard let handle = openRegularFile(at: path) else { return nil }
        defer { try? handle.close() }
        return uuids { offset, length in
            guard length >= 0, (try? handle.seek(toOffset: UInt64(offset))) != nil, let data = try? handle.read(upToCount: length), data.count == length else { return nil }
            return data
        }
    }

    /// A handle on the regular file at `path`, or `nil` for anything else. Opening a named pipe for reading waits until something writes to it, and a folder that other programs
    /// write into (the crash reports) can hold one named like a report: it is opened without waiting, a link is not followed, and only a regular file is read.
    static func openRegularFile(at path: String) -> FileHandle? {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { close(descriptor); return nil }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    private static let thin64 = UInt32(0xFEEDFACF)
    private static let fat = UInt32(0xCAFEBABE)
    private static let fat64 = UInt32(0xCAFEBABF)
    private static let uuidCommand = UInt32(0x1B)
    /// A header's load commands are a few kilobytes; one that claims more than this is not a program of ours.
    private static let largestCommands = 1 << 20

    static func uuids(reading read: Reader) -> Set<String>? {
        guard let head = read(0, 8) else { return nil }
        switch bigEndian(head, 0) {
        case fat, fat64:
            // A universal binary: a list of slices, each a thin file at an offset. The list is big endian.
            let count = Int(bigEndian(head, 4))
            let entry = bigEndian(head, 0) == fat ? 20 : 32
            guard count > 0, count <= 64, let table = read(8, count * entry) else { return nil }
            var found = Set<String>()
            for index in 0..<count {
                let at = index * entry
                let sliceOffset = entry == 20 ? Int(bigEndian(table, at + 8)) : Int(clamping: bigEndian64(table, at + 8))
                if let slice = thinUUID(reading: read, at: sliceOffset) { found.insert(slice) }
            }
            return found
        default:
            return thinUUID(reading: read, at: 0).map { [$0] }
        }
    }

    /// The `LC_UUID` of the 64-bit little-endian Mach-O header at `offset`.
    private static func thinUUID(reading read: Reader, at offset: Int) -> String? {
        guard offset >= 0, let header = read(offset, 32), littleEndian(header, 0) == thin64 else { return nil }
        let commands = Int(littleEndian(header, 16))
        let size = Int(littleEndian(header, 20))
        guard commands > 0, size >= 8, size <= largestCommands, let block = read(offset + 32, size) else { return nil }
        var at = 0
        for _ in 0..<commands {
            guard at + 8 <= size else { return nil }
            let command = littleEndian(block, at)
            let length = Int(littleEndian(block, at + 4))
            guard length >= 8, at + length <= size else { return nil }
            if command == uuidCommand {
                guard length >= 24 else { return nil }
                let bytes = Array(block[block.startIndex + at + 8 ..< block.startIndex + at + 24])
                return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])).uuidString.lowercased()
            }
            at += length
        }
        return nil
    }

    private static func littleEndian(_ data: Data, _ at: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[data.startIndex + at + $1]) << (8 * UInt32($1)) }
    }

    private static func bigEndian(_ data: Data, _ at: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { ($0 << 8) | UInt32(data[data.startIndex + at + $1]) }
    }

    private static func bigEndian64(_ data: Data, _ at: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { ($0 << 8) | UInt64(data[data.startIndex + at + $1]) }
    }
}
