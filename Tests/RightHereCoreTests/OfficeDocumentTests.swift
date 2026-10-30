import Foundation
import Testing
@testable import RightHereCore

@Suite("OfficeDocument: the blank Word, Excel and PowerPoint documents New File makes")
struct OfficeDocumentTests {
    /// The names of the entries of a ZIP archive, as `unzip` reads them, and whether `unzip -t` finds it sound.
    private func entries(_ bytes: [UInt8]) throws -> (names: [String], sound: Bool) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("office-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("blank.zip")
        try Data(bytes).write(to: file)
        func unzip(_ arguments: [String]) throws -> (Int32, String) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            process.arguments = arguments + [file.path]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: output, as: UTF8.self))
        }
        let (tested, _) = try unzip(["-tq"])
        let (_, listing) = try unzip(["-Z1"])
        return (listing.split(separator: "\n").map(String.init), tested == 0)
    }

    @Test("each format is a sound archive of the parts it needs", arguments: OfficeFormat.allCases)
    func eachFormatIsASoundPackage(format: OfficeFormat) throws {
        let (names, sound) = try entries(OfficeDocument.bytes(format))
        #expect(sound, "unzip -t found the \(format) archive damaged")
        let expected: [String] = switch format {
        case .docx: ["[Content_Types].xml", "_rels/.rels", "word/document.xml"]
        case .xlsx: ["[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels", "xl/worksheets/sheet1.xml"]
        case .pptx: ["[Content_Types].xml", "_rels/.rels", "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels", "ppt/slides/slide1.xml", "ppt/slides/_rels/slide1.xml.rels",
                     "ppt/slideMasters/slideMaster1.xml", "ppt/slideMasters/_rels/slideMaster1.xml.rels", "ppt/slideLayouts/slideLayout1.xml",
                     "ppt/slideLayouts/_rels/slideLayout1.xml.rels", "ppt/theme/theme1.xml"]
        }
        #expect(names == expected)
        #expect(OfficeDocument.bytes(format) == OfficeDocument.bytes(format), "the same bytes every time: stored entries with a fixed date")
    }

    @Test func theChecksumIsTheStandardCRC32() {
        #expect(StoredZip.crc32(Array("123456789".utf8)) == 0xCBF4_3926, "the check value of CRC-32 (ISO 3309)")
        #expect(StoredZip.crc32([]) == 0)
    }

    @Test func theBuiltInOfficeTemplatesMakeTheirFormatAndAPlanNamesItInsteadOfTheBytes() throws {
        #expect(NewFileTemplate.builtIn.map(\.id) == ["txt", "md", "docx", "xlsx", "pptx"])
        #expect(NewFileTemplate.builtIn.filter { $0.format != nil }.allSatisfy { $0.format?.rawValue == $0.fileExtension && $0.contents.isEmpty })
        let facts = FakeSystemFacts(directories: ["/Users/tester/code"])
        let plan = try Planner(facts: facts).plan(.newFile("docx"), context: HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code")))
        guard case .createFile(let step)? = plan.steps.first else { Issue.record("\(plan.steps)"); return }
        #expect(step.path == "/Users/tester/code/untitled.docx" && step.format == .docx && step.contents.isEmpty)
        #expect(step.bytes == OfficeDocument.bytes(.docx))
        let json = String(decoding: try JSONEncoder().encode(plan), as: UTF8.self)
        #expect(json.contains("\"format\":\"docx\"") && json.count < 1_000, "the plan says the format, not kilobytes of a package: \(json.count) bytes")
    }

    @Test func aTemplatesFormatMatchesItsExtensionAndHasNoContents() {
        let base = "[[new_file.template]]\nid = \"w\"\ntitle = \"W\"\n"
        let good = ConfigParser.parse(base + "extension = \"docx\"\nformat = \"docx\"\n")
        #expect(good.diagnostics.isEmpty && good.config.newFile.templates.first?.format == .docx)
        let wrongExtension = ConfigParser.parse(base + "extension = \"doc\"\nformat = \"docx\"\n")
        #expect(wrongExtension.diagnostics.contains { $0.severity == .error && $0.message.contains("docx") })
        let withContents = ConfigParser.parse(base + "extension = \"docx\"\nformat = \"docx\"\ncontents = \"x\"\n")
        #expect(withContents.diagnostics.contains { $0.severity == .error && $0.message.contains("no contents") })
        let unknown = ConfigParser.parse(base + "extension = \"odt\"\nformat = \"odt\"\n")
        #expect(unknown.diagnostics.contains { $0.severity == .error })
    }

    @Test func hiddenTemplatesLeaveTheSubmenuAndANameThatIsNoTemplateIsAWarning() throws {
        let parsed = ConfigParser.parse("[new_file]\nhidden = [\"pptx\", \"pdf\"]\n")
        #expect(parsed.config.newFile.hidden == ["pptx", "pdf"] && parsed.config.newFile.shownTemplates.map(\.id) == ["txt", "md", "docx", "xlsx"])
        #expect(parsed.diagnostics.contains { $0.severity == .warning && $0.message.contains("pdf") })
        let state = NewFileOptions.state(config: parsed.config, entries: [:], facts: FakeSystemFacts(), localizer: .english)
        let pptx = try #require(state.row(id: "pptx"))
        let docx = try #require(state.row(id: "docx"))
        #expect(!pptx.shown && docx.shown)
        #expect(NewFileOptions.operations(settingShown: true, of: pptx, in: state) == [.expect(["pptx", "pdf"], in: "new_file.hidden"), .remove(at: 1, from: "new_file.hidden")])
        #expect(NewFileOptions.operations(settingShown: false, of: docx, in: state) == [.expect(["pptx", "pdf"], in: "new_file.hidden"), .insert("docx", into: "new_file.hidden")])
        #expect(NewFileOptions.operations(settingShown: true, of: docx, in: state).isEmpty, "shown already")
        let fresh = NewFileOptions.state(config: .default, entries: [:], facts: FakeSystemFacts(), localizer: .english)
        #expect(NewFileOptions.operations(settingShown: false, of: try #require(fresh.row(id: "xlsx")), in: fresh) == [.expect(nil, in: "new_file.hidden"), .insert("xlsx", into: "new_file.hidden")])
    }
}
