import Foundation
import Testing
@testable import RightHereKit

/// What `MachOUUID` reads, from files made here to the layout the linker writes, and from a real binary with the answer of the tool that Apple ships for it.
@Suite("MachOUUID: the UUID of the code, which a crash report names")
struct MachOUUIDTests {
    private func little(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32($0))) } }
    private func big(_ value: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: value >> (8 * UInt32(3 - $0))) } }
    private func big64(_ value: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: value >> (8 * UInt64(7 - $0))) } }

    private func bytes(of uuid: UUID) -> [UInt8] { withUnsafeBytes(of: uuid.uuid) { Array($0) } }

    /// A 64-bit little-endian header, a segment command, the UUID command (when there is a UUID) and a build version command, as `ld` orders them.
    private func thin(_ uuid: UUID?) -> Data {
        var commands: [UInt8] = []
        commands += little(0x19) + little(72) + [UInt8](repeating: 0, count: 64)
        if let uuid { commands += little(0x1B) + little(24) + bytes(of: uuid) }
        commands += little(0x32) + little(24) + [UInt8](repeating: 0, count: 16)
        let header = little(0xFEEDFACF) + little(0x0100000C) + little(0) + little(2) + little(uuid == nil ? 2 : 3) + little(UInt32(commands.count)) + little(0) + little(0)
        return Data(header + commands)
    }

    private func universal(_ slices: [Data], wide: Bool = false) -> Data {
        let entry = wide ? 32 : 20
        var offset = 0x4000
        var table: [UInt8] = []
        var body = Data()
        for slice in slices {
            table += big(0x0100000C) + big(0)
            table += wide ? big64(UInt64(offset)) + big64(UInt64(slice.count)) + big(14) + big(0) : big(UInt32(offset)) + big(UInt32(slice.count)) + big(14)
            body.append(Data(repeating: 0, count: offset - 8 - slices.count * entry - body.count))
            body.append(slice)
            offset += 0x4000
        }
        return Data(big(wide ? 0xCAFEBABF : 0xCAFEBABE) + big(UInt32(slices.count)) + table) + body
    }

    private func uuids(_ data: Data) -> Set<String>? {
        MachOUUID.uuids { offset, length in offset + length <= data.count ? data.subdata(in: offset..<offset + length) : nil }
    }

    private let first = UUID(uuidString: "F220ADBD-EAF4-3364-916E-9B513225F252")!
    private let second = UUID(uuidString: "0A1B2C3D-4E5F-4061-8273-849506A7B8C9")!

    @Test func aThinFileHasOneAndItIsWrittenAsACrashReportWritesIt() {
        #expect(uuids(thin(first)) == ["f220adbd-eaf4-3364-916e-9b513225f252"])
    }

    @Test func aUniversalFileHasOneForEachArchitecture() {
        #expect(uuids(universal([thin(first), thin(second)])) == ["f220adbd-eaf4-3364-916e-9b513225f252", "0a1b2c3d-4e5f-4061-8273-849506a7b8c9"])
        #expect(uuids(universal([thin(first), thin(second)], wide: true)) == ["f220adbd-eaf4-3364-916e-9b513225f252", "0a1b2c3d-4e5f-4061-8273-849506a7b8c9"])
        #expect(uuids(universal([thin(nil), thin(second)])) == ["0a1b2c3d-4e5f-4061-8273-849506a7b8c9"], "a slice without one adds none")
    }

    @Test("what is not a Mach-O file, or is cut off or wrong, has none and does not trap", arguments: [
        Data(), Data("#!/bin/sh\necho hi\n".utf8), Data([0xCF, 0xFA, 0xED, 0xFE]), Data(repeating: 0xFF, count: 200), Data(repeating: 0, count: 64)
    ])
    func notMachO(data: Data) {
        #expect(uuids(data) == nil || uuids(data)?.isEmpty == true)
    }

    @Test func aHeaderThatClaimsMoreThanTheFileHasIsRefused() {
        // The count of commands says 90,000 and the commands end after two, with no UUID among them.
        var data = thin(nil)
        data.replaceSubrange(16..<20, with: little(90_000))
        #expect(uuids(data) == nil)
        var huge = thin(first)
        huge.replaceSubrange(20..<24, with: little(0x7FFF_FFFF))
        #expect(uuids(huge) == nil, "load commands of two gigabytes are not read")
        var cut = thin(first)
        cut.removeLast(30)
        #expect(uuids(cut) == nil)
    }

    @Test func aCommandThatCannotBeWalkedStopsTheWalk() {
        var zero = thin(first)
        zero.replaceSubrange(36..<40, with: little(0))
        #expect(uuids(zero) == nil, "a command of size zero would walk for ever")
        // A count of four billion and commands of no size must end at the first of them, not after as many steps.
        zero.replaceSubrange(16..<20, with: little(0xFFFF_FFFF))
        #expect(uuids(zero) == nil)
        var short = thin(first)
        // The UUID command (after the 72-byte segment command) says it is 8 bytes long.
        short.replaceSubrange(32 + 72 + 4..<32 + 72 + 8, with: little(8))
        #expect(uuids(short) == nil)
    }

    @Test func aFileOfTheDiskIsReadWhereItIs() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("FinderExtension")
        try universal([thin(first), thin(second)]).write(to: file)
        #expect(MachOUUID.uuids(ofFileAt: file.path)?.count == 2)
        #expect(MachOUUID.uuids(ofFileAt: folder.appendingPathComponent("missing").path) == nil)
        #expect(MachOUUID.uuids(ofFileAt: folder.path) == nil, "a folder is not a program")
    }

    /// Against what Apple's own tool says about a real binary (universal, arm64e and x86_64): the layouts of the files that this Mac has, not only the layouts of the files above.
    @Test func theUUIDsOfARealBinaryAreWhatDwarfdumpSays() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/dwarfdump") else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dwarfdump")
        process.arguments = ["--uuid", "/bin/ls"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        let expected = Set(text.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("UUID: ") else { return nil }
            return line.dropFirst("UUID: ".count).split(separator: " ").first.map { $0.lowercased() }
        })
        guard !expected.isEmpty else { return }
        #expect(MachOUUID.uuids(ofFileAt: "/bin/ls") == expected)
    }
}
