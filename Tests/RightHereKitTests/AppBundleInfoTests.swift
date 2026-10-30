import Foundation
import Testing
@testable import RightHereKit

@Suite("AppBundleInfo: what an app says of itself")
struct AppBundleInfoTests {
    /// A folder that is an application as far as its `Info.plist` goes.
    private func bundle(named name: String, in folder: URL, info: [String: Any]?) throws -> URL {
        let app = folder.appendingPathComponent(name, isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        if let info { try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist")) }
        return app
    }

    @Test func theIdentifierAndTheNameAreReadFromTheInfoPlist() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let nova = try bundle(named: "Nova.app", in: folder, info: ["CFBundleIdentifier": "com.panic.Nova", "CFBundleName": "Nova", "CFBundleDisplayName": "  Nova Editor "])
        #expect(AppBundleInfo.read(at: nova) == AppBundleInfo(bundleID: "com.panic.Nova", name: "Nova Editor"), "the display name, without the spaces around it")
        let plain = try bundle(named: "Plain.app", in: folder, info: ["CFBundleIdentifier": "com.example.Plain", "CFBundleName": "Plain Name"])
        #expect(AppBundleInfo.read(at: plain)?.name == "Plain Name")
        let nameless = try bundle(named: "Folder Name.app", in: folder, info: ["CFBundleIdentifier": "com.example.Nameless", "CFBundleName": "  ", "CFBundleDisplayName": ""])
        #expect(AppBundleInfo.read(at: nameless)?.name == "Folder Name", "the name of the folder when the plist gives none")
    }

    @Test func anAppThatSaysItIsAShellIsKnownAsOneWhichMakesTheFormStartWithTheRoleTerminal() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let shell: [[String: Any]] = [["CFBundleTypeRole": "Editor", "LSItemContentTypes": ["public.plain-text"]], ["CFBundleTypeRole": "Shell", "LSItemContentTypes": ["com.apple.terminal.shell-script"]]]
        let terminal = try bundle(named: "Tabby.app", in: folder, info: ["CFBundleIdentifier": "org.tabby", "CFBundleName": "Tabby", "CFBundleDocumentTypes": shell])
        #expect(AppBundleInfo.read(at: terminal)?.runsShellScripts == true)
        let editor = try bundle(named: "Pulsar.app", in: folder, info: ["CFBundleIdentifier": "dev.pulsar", "CFBundleName": "Pulsar", "CFBundleDocumentTypes": [["CFBundleTypeRole": "Editor"]]])
        #expect(AppBundleInfo.read(at: editor)?.runsShellScripts == false)
        let plain = try bundle(named: "Plain.app", in: folder, info: ["CFBundleIdentifier": "com.example.plain", "CFBundleDocumentTypes": "not a list"])
        #expect(AppBundleInfo.read(at: plain)?.runsShellScripts == false, "an odd value says nothing")
    }

    @Test func aNameThatTheConfigWouldRefuseIsNotTheNameTheFormStartsWith() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        let hostile = try bundle(named: "Fine Name.app", in: folder, info: ["CFBundleIdentifier": "com.example.hostile", "CFBundleDisplayName": "Nova\u{202E}lmth", "CFBundleName": "Nova\u{1B}[2J"])
        #expect(AppBundleInfo.read(at: hostile)?.name == "Fine Name", "a direction override and an escape sequence are not a name; the folder's is")
        let long = try bundle(named: "Short.app", in: folder, info: ["CFBundleIdentifier": "com.example.long", "CFBundleDisplayName": String(repeating: "A", count: 500)])
        #expect(AppBundleInfo.read(at: long)?.name == "Short")
        let nothing = try bundle(named: "Odd\u{202E}.app", in: folder, info: ["CFBundleIdentifier": "com.example.odd", "CFBundleDisplayName": "\u{200B}"])
        #expect(AppBundleInfo.read(at: nothing)?.name == "App", "nothing that the config accepts: a plain word the person changes")
    }

    @Test func whatIsNotAnApplicationWithAnIdentifierIsNotRead() throws {
        let folder = try makeTemporaryDirectory(); defer { try? FileManager.default.removeItem(at: folder) }
        #expect(AppBundleInfo.read(at: try bundle(named: "NoPlist.app", in: folder, info: nil)) == nil)
        #expect(AppBundleInfo.read(at: try bundle(named: "NoIdentifier.app", in: folder, info: ["CFBundleName": "x"])) == nil)
        #expect(AppBundleInfo.read(at: try bundle(named: "Empty.app", in: folder, info: ["CFBundleIdentifier": ""])) == nil)
        #expect(AppBundleInfo.read(at: try bundle(named: "NotAnApp.bundle", in: folder, info: ["CFBundleIdentifier": "com.example.Bundle"])) == nil, "a plug-in or a framework is not an app")
        #expect(AppBundleInfo.read(at: folder.appendingPathComponent("Missing.app")) == nil)
        let file = folder.appendingPathComponent("File.app")
        try Data("not a folder".utf8).write(to: file)
        #expect(AppBundleInfo.read(at: file) == nil)
    }
}
