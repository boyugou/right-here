import Foundation
import Testing
@testable import RightHereCore

private func config(_ text: String) -> Config { ConfigParser.parse(text).config }

@Suite("CopyPathOptions: the forms of Copy Path as rows to edit")
struct CopyPathOptionsTests {
    private func state(_ text: String = "", listed: [String]? = nil) -> CopyPathState {
        CopyPathOptions.state(config: config(text), localizer: .english, listed: listed)
    }

    private func apply(_ operations: [ConfigOperation], to text: String) throws -> Config {
        var document = ConfigDocument(text)
        for operation in operations { document = try operation.apply(to: document) }
        return config(document.text)
    }

    @Test func theDefaultFormsAreRowsAndTheOthersAreLeftOut() {
        let shown = state()
        #expect(shown.offered.map(\.style) == Config.defaultCopyPathStyles && shown.title == nil)
        #expect(Set(shown.others.map(\.style)) == Set(PathStyle.allCases).subtracting(Config.defaultCopyPathStyles))
        #expect(shown.list.usesDefaults && shown.list.isExact && shown.offered.allSatisfy { !$0.title.isEmpty })
        let written = state("[copy_path]\nstyles = [\"name\", \"absolute\"]\ntitle = \"Paths\"\n", listed: ["name", "absolute"])
        #expect(written.offered.map(\.style) == [.name, .absolute] && written.others.count == PathStyle.allCases.count - 2 && written.title == "Paths")
        #expect(!written.list.usesDefaults && written.list.isExact)
    }

    @Test func theFirstChangeWritesTheDefaultListAndThenChangesIt() throws {
        let shown = state()
        let added = CopyPathOptions.operations(adding: .parent, to: shown)
        #expect(added.first == .expect(nil, in: "copy_path.styles") && added.dropFirst().first == .set("copy_path.styles", .strings(Config.defaultCopyPathStyles.map(\.rawValue))))
        #expect(try apply(added, to: "").copyPathStyles == Config.defaultCopyPathStyles + [.parent])
        #expect(try apply(CopyPathOptions.operations(removingAt: 2, from: shown), to: "").copyPathStyles == [.absolute, .gitRelative, .name, .shellEscaped, .aiMention])
        #expect(try apply(CopyPathOptions.operations(moving: [3], to: 0, in: shown), to: "").copyPathStyles == [.name, .absolute, .tilde, .gitRelative, .shellEscaped, .aiMention])
        #expect(CopyPathOptions.operations(moving: [0], to: 0, in: shown).isEmpty && CopyPathOptions.operations(removingAt: 9, from: shown).isEmpty)
    }

    @Test func aWrittenListIsChangedByPlaceAndOnlyWhileTheFileWritesWhatTheWindowShowed() throws {
        let text = "[copy_path]\nstyles = [\"name\", \"absolute\", \"tilde\"]\n"
        let shown = state(text, listed: ["name", "absolute", "tilde"])
        let added = CopyPathOptions.operations(adding: .fileURL, to: shown)
        #expect(added == [.expect(["name", "absolute", "tilde"], in: "copy_path.styles"), .insert("file-url", into: "copy_path.styles", at: nil)])
        #expect(try apply(added, to: text).copyPathStyles == [.name, .absolute, .tilde, .fileURL])
        #expect(CopyPathOptions.operations(adding: .name, to: shown).isEmpty, "a form that is offered is not added again")
        let elsewhere = state(text, listed: ["absolute"])
        #expect(!elsewhere.list.isExact && CopyPathOptions.operations(adding: .fileURL, to: elsewhere).isEmpty, "a list that this file does not write as shown is not changed by place")
    }

    @Test func theTitleIsSetAndTheEmptyOneIsTheSettingTakenOut() {
        let plain = state()
        #expect(CopyPathOptions.operations(settingTitle: "  Paths ", in: plain) == [.set("copy_path.title", .string("Paths"))])
        #expect(CopyPathOptions.operations(settingTitle: " ", in: plain).isEmpty)
        let titled = state("[copy_path]\ntitle = \"Paths\"\n")
        #expect(CopyPathOptions.operations(settingTitle: "", in: titled) == [.unset("copy_path.title")])
        #expect(CopyPathOptions.operations(settingTitle: "Paths", in: titled).isEmpty)
    }
}
