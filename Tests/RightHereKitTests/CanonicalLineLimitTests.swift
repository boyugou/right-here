import Darwin
import Foundation
import Testing

/// The platform fact behind the limit on a typed line (an independent review, 2026-11-12). Ghostty, Terminal and iTerm type the agent's line into a new
/// session's tty while its shell is still starting, so the tty is in canonical mode, as a new pty is. No shell, terminal or window is involved: a pty pair.
@Suite("What a new terminal's tty keeps of a typed line")
struct CanonicalLineLimitTests {
    /// What the shell finds once its line editor turns canonical mode off, after `bytes` were written to the pty as one unfinished line and a Return.
    static func pendingAfterTyping(_ bytes: Int) throws -> (accepted: Int, pending: [UInt8]) {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        try #require(master >= 0)
        defer { close(master) }
        try #require(grantpt(master) == 0 && unlockpt(master) == 0)
        let path = try #require(ptsname(master).map { String(cString: $0) })
        let slave = open(path, O_RDWR | O_NOCTTY)
        try #require(slave >= 0)
        defer { close(slave) }
        var modes = termios()
        try #require(tcgetattr(slave, &modes) == 0)
        try #require(modes.c_lflag & tcflag_t(ICANON) != 0, "a new pty starts in canonical mode")
        _ = fcntl(master, F_SETFL, fcntl(master, F_GETFL) | O_NONBLOCK)

        let line = [UInt8](repeating: UInt8(ascii: "x"), count: bytes) + [UInt8(ascii: "\n")]
        var accepted = 0
        var scratch = [UInt8](repeating: 0, count: 65536)
        let deadline = Date().addingTimeInterval(2)
        while accepted < line.count, Date() < deadline {
            let count = line[accepted...].withUnsafeBytes { write(master, $0.baseAddress, $0.count) }
            if count > 0 { accepted += count } else { _ = read(master, &scratch, scratch.count) } // the echo, which a terminal reads
        }
        while read(master, &scratch, scratch.count) > 0 {}

        modes.c_lflag &= ~tcflag_t(ICANON)
        withUnsafeMutableBytes(of: &modes.c_cc) { characters in
            characters[Int(VMIN)] = 0
            characters[Int(VTIME)] = 0
        }
        try #require(tcsetattr(slave, TCSANOW, &modes) == 0)
        var pending: [UInt8] = []
        while true {
            let count = read(slave, &scratch, scratch.count)
            if count <= 0 { break }
            pending += scratch[0..<count]
        }
        return (accepted, pending)
    }

    @Test func aLineOf1023BytesArrivesWithItsReturn() throws {
        let (accepted, pending) = try Self.pendingAfterTyping(1023)
        #expect(accepted == 1024)
        #expect(pending.count == 1024 && pending.last == UInt8(ascii: "\n"))
    }

    @Test("a longer line keeps its first 1024 bytes and loses the rest, Return included, while write reports every byte taken", arguments: [1024, 1100, 4000])
    func aLongerLineLosesItsReturn(bytes: Int) throws {
        let (accepted, pending) = try Self.pendingAfterTyping(bytes)
        #expect(accepted == bytes + 1)
        #expect(pending.count == 1024)
        #expect(!pending.contains(UInt8(ascii: "\n")))
    }
}
