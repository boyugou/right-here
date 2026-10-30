import AppKit
import CoreText
import Foundation
import Testing
@testable import RightHereCore

private func placeholders(_ text: String) -> [String] {
    text.matches(of: #/%(?:\d+\$)?@/#).map { String(text[$0.range]) }.sorted()
}

/// A message for any key, with as many values as the key takes.
private func filled(_ key: LocalizationKey) -> LocalizedMessage {
    LocalizedMessage(key, (0..<key.arity).map { "X\($0 + 1)" })
}

/// The UTF-16 offsets of `text` in the order CoreText draws them from left to right (the Unicode bidirectional algorithm applied,
/// the paragraph direction taken from the first strong character, as SwiftUI does). Nothing is shown: CoreText lays a string out
/// in memory, which is what a SwiftUI `Text` does with it.
private func visualOrder(_ text: String) -> [Int] {
    let font = CTFontCreateWithName("Helvetica" as CFString, 13, nil)
    let attributed = NSAttributedString(string: text, attributes: [.font: font, .ligature: 0])
    let line = CTLineCreateWithAttributedString(attributed)
    var order: [Int] = []
    for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
        var indices = [CFIndex](repeating: 0, count: CTRunGetGlyphCount(run))
        CTRunGetStringIndices(run, CFRange(location: 0, length: 0), &indices)
        order += indices
    }
    return order
}

/// The paths (`~/...`, `/...`) written in `text` that are not drawn in one piece, left to right.
private func scrambledPaths(in text: String) -> [String] {
    // The setup window turns a command between backticks into code and drops the backticks, so it lays out the text without them.
    let visible = text.replacingOccurrences(of: "`", with: "")
    var position: [Int: Int] = [:]
    for (drawn, offset) in visualOrder(visible).enumerated() { position[offset] = drawn }
    var scrambled: [String] = []
    for match in visible.matches(of: #/(?:^|[\s\u{2068}\u{200E}\u{200F}])(~?\/[^\s\u{2069}]*[A-Za-z][^\s\u{2069}]*)/#) {
        var path = String(match.output.1)
        while let last = path.last, ".,;:!?،؛۔".contains(last) { path.removeLast() }
        guard path.count > 2 else { continue }
        let start = visible.utf16.distance(from: visible.utf16.startIndex, to: match.output.1.startIndex)
        let length = path.utf16.count
        let drawn = (start..<(start + length)).compactMap { position[$0] }
        guard drawn.count == length else { continue }
        if !zip(drawn, drawn.dropFirst()).allSatisfy({ $1 == $0 + 1 }) { scrambled.append(path) }
    }
    return scrambled
}

/// The commands between backticks in `text` that are not drawn in one piece, left to right. The window shows a command as code
/// and drops the backticks, so each span is looked for in the text without them.
private func scrambledCommands(in text: String) -> [String] {
    var visible = ""
    var spans: [Range<Int>] = []
    var opened: Int?
    for character in text {
        if character == "`" {
            if let start = opened { spans.append(start..<visible.utf16.count); opened = nil } else { opened = visible.utf16.count }
        } else {
            visible.append(character)
        }
    }
    var position: [Int: Int] = [:]
    for (drawn, offset) in visualOrder(visible).enumerated() { position[offset] = drawn }
    let units = Array(visible.utf16)
    var scrambled: [String] = []
    for span in spans where span.count > 1 {
        let drawn = span.compactMap { position[$0] }
        guard drawn.count == span.count else { continue }
        if !zip(drawn, drawn.dropFirst()).allSatisfy({ $1 == $0 + 1 }) { scrambled.append(String(decoding: units[span], as: UTF16.self)) }
    }
    return scrambled
}

/// `Localization/languages.json`, the one list of the shipped languages. The scripts read it too.
private struct LanguageManifest: Decodable {
    struct Language: Decodable {
        var code: String
        var rtl: Bool?
    }

    var source: String
    var languages: [Language]

    static let current: LanguageManifest = {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Localization/languages.json")
        return try! JSONDecoder().decode(LanguageManifest.self, from: Data(contentsOf: file))
    }()

    static var rightToLeft: [String] { current.languages.filter { $0.rtl == true }.map(\.code) }
}

@Suite("Localization catalog")
struct LocalizationCatalogTests {
    @Test func theCompiledLanguagesAreTheOnesInTheManifest() {
        let manifest = LanguageManifest.current
        #expect(Localizations.languages == manifest.languages.map(\.code))
        #expect(Localizations.languages.first == manifest.source)
        #expect(manifest.source == "en")
    }

    @Test func theMirroringTestsHaveLanguagesToRun() {
        // The right-to-left tests take their languages from the manifest; with none they would pass by running nothing.
        #expect(!LanguageManifest.rightToLeft.isEmpty)
    }

    @Test func everyKeyIsTranslatedIntoEveryLanguage() {
        for key in LocalizationKey.allCases {
            let translations = Localizations.table[key.rawValue]
            #expect(translations != nil, "\(key.rawValue) is missing from the table")
            for language in Localizations.languages {
                let value = translations?[language]
                #expect(value?.isEmpty == false, "\(key.rawValue) has no \(language) text")
            }
        }
    }

    @Test func theTableHasNoKeyThatIsNotAnEnumCase() {
        let known = Set(LocalizationKey.allCases.map(\.rawValue))
        #expect(Set(Localizations.table.keys) == known)
    }

    @Test func placeholdersMatchEnglishInEveryLanguage() {
        for key in LocalizationKey.allCases {
            guard let translations = Localizations.table[key.rawValue], let english = translations["en"] else { continue }
            for (language, value) in translations {
                #expect(placeholders(value) == placeholders(english), "\(key.rawValue) [\(language)] changes the placeholders")
            }
        }
    }

    @Test func theArityOfAKeyIsTheNumberOfValuesItsEnglishTextTakes() {
        for key in LocalizationKey.allCases {
            let found = (Localizations.table[key.rawValue]?["en"] ?? "").matches(of: #/%(?:(\d+)\$)?@/#)
            let highest = found.compactMap { $0.output.1.flatMap { Int($0) } }.max()
            #expect(key.arity == (highest ?? found.count), "\(key.rawValue) takes \(highest ?? found.count) values, its arity says \(key.arity)")
        }
    }

    @Test func everyKeyIsWrittenInEveryLanguageWithAllItsValuesAndNothingLeftOver() {
        for language in Localizations.languages {
            let localizer = Localizer(languages: [language])
            for key in LocalizationKey.allCases {
                let text = localizer.render(filled(key))
                #expect(!text.contains("%"), "\(key.rawValue) [\(language)] still has a placeholder: \(text)")
                for number in 0..<key.arity { #expect(text.contains("X\(number + 1)"), "\(key.rawValue) [\(language)] drops value \(number + 1): \(text)") }
            }
        }
    }

    @Test func theKeysOfTheBuiltInTitlesTakeNoValues() {
        // `titleKey.map { localizer.string($0) }` has nothing to fill in with.
        let keys = KnownAgents.all.flatMap(\.variants).compactMap(\.titleKey)
            + AgentPreset.builtIn.compactMap(\.titleKey)
            + NewFileTemplate.builtIn.flatMap { [$0.titleKey, $0.newTitleKey, $0.baseNameKey].compactMap { $0 } }
        #expect(!keys.isEmpty)
        for key in keys { #expect(key.arity == 0, "\(key.rawValue) takes values, but a title is looked up by its key alone") }
    }

    @Test func aTextWithSeveralValuesNumbersThem() {
        // `%1$@ in %2$@` can be reordered by a translation; two bare `%@` could not.
        for key in LocalizationKey.allCases where key.arity > 1 {
            let english = Localizations.table[key.rawValue]?["en"] ?? ""
            #expect(!english.contains("%@"), "\(key.rawValue) takes several values but does not number them")
        }
    }

    @Test func defaultFileNamesAreUsableAsFileNames() {
        let names = Localizations.table[LocalizationKey.newFileBaseName.rawValue] ?? [:]
        for (language, name) in names {
            #expect(!name.contains("/") && !name.contains(":"), "\(language) base name contains a forbidden character")
        }
    }
}

@Suite("Localizer")
struct LocalizerTests {
    @Test("language tags resolve to the catalog language", arguments: [
        ("en", "en"), ("en-US", "en"), ("en-GB", "en"), ("de-DE", "de"), ("fr-CA", "fr"), ("es-419", "es"),
        ("zh-Hans-US", "zh-Hans"), ("zh-Hans-CN", "zh-Hans"), ("zh-CN", "zh-Hans"), ("zh-SG", "zh-Hans"),
        ("zh-Hant-TW", "zh-Hant"), ("zh-TW", "zh-Hant"), ("zh-HK", "zh-Hant"), ("zh-Hant", "zh-Hant"),
        ("pt-PT", "pt-BR"), ("pt-BR", "pt-BR"), ("pt", "pt-BR"), ("ja-JP", "ja"), ("ar-SA", "ar"), ("he-IL", "he"),
        ("zh", "zh-Hans"), ("de_AT", "de"),
        // What macOS reports for Simplified Chinese on a Hong Kong, Macao or Taiwan Mac: the script wins over the region.
        ("zh-Hans-HK", "zh-Hans"), ("zh-Hans-MO", "zh-Hans"), ("zh-Hans-TW", "zh-Hans"), ("zh_Hans_HK", "zh-Hans"),
        // And the reverse: an explicit Traditional script wins over a mainland region.
        ("zh-Hant-CN", "zh-Hant"), ("zh-Hant-SG", "zh-Hant"), ("zh-Hant-US", "zh-Hant"), ("zh-Hant-HK", "zh-Hant"),
        // Without a script the region decides.
        ("zh-MO", "zh-Hant"), ("zh-US", "zh-Hans"), ("zh-yue-HK", "zh-Hant")
    ])
    func resolves(tag: String, expected: String) {
        #expect(Localizer(languages: [tag]).resolvedLanguage == expected)
        #expect(Localizer.match(tag) == expected)
    }

    @Test func anUnsupportedLanguageFallsThroughToTheNextOne() {
        #expect(Localizer(languages: ["xx-YY", "fr-FR"]).resolvedLanguage == "fr")
    }

    @Test func nothingSupportedMeansEnglish() {
        #expect(Localizer(languages: ["xx", "yy"]).resolvedLanguage == "en")
        #expect(Localizer(languages: []).resolvedLanguage == "en")
    }

    @Test func englishIsTheDefaultLocalizer() {
        #expect(Localizer.english.string(.groupCopyPath) == "Copy Path")
    }

    @Test func formatsArguments() {
        #expect(Localizer.english.render(.menuOpenIn("Ghostty")) == "Open in Ghostty")
        #expect(Localizer(languages: ["de"]).render(.menuOpenIn("Ghostty")) == "In Ghostty öffnen")
        #expect(Localizer(languages: ["zh-Hans"]).render(.menuOpenIn("Ghostty")) == "在“Ghostty”中打开")
    }

    /// A value is a name, a path or a message that a file, a config or git wrote: in the English a terminal or an agent reads it is shown with its control and
    /// invisible characters as escapes, whoever built the message.
    @Test func theValuesOfAnEnglishSentenceAreShownWithControlAndInvisibleCharactersAsEscapes() {
        #expect(LocalizedMessage.menuOpenIn("a\u{1b}[2J\nb").english() == "Open in a\\u001b[2J\\nb")
        #expect(LocalizedMessage.doctorVerbatim("x\u{200B}y\u{202E}").english() == "x\\u200by\\u202e")
        #expect(LocalizedMessage.doctorAgentOk("a\u{E0041}", "b\u{7}").english() == "`a\\udb40\\udc41` found; starts with b\\u0007")
        #expect(LocalizedMessage.doctorAgentOk("a\u{E0041}", "b\u{7}").english(showingOnly: [0, 1]) == "`a\\udb40\\udc41` found; starts with b\\u0007")
        // Not mangled: what is written in a language, and the sentence's own words.
        #expect(LocalizedMessage.menuOpenIn("日本語 👨\u{200D}👩 é").english() == "Open in 日本語 👨\u{200D}👩 é")
    }

    /// A menu title and the setup window show a name as it is: a terminal escape cannot act there, and a name written right to left may need its marks.
    @Test func aTitleOrAWindowShowsANameAsItIs() {
        #expect(Localizer.english.render(.menuOpenIn("a\u{200F}b")) == "Open in a\u{200F}b")
        #expect(Localizer(languages: ["de"]).render(.menuOpenIn("a\u{1b}b")) == "In a\u{1b}b öffnen")
    }

    @Test func theIsolatesOfARightToLeftSentenceAreAddedAroundTheEscapedValue() {
        let text = Localizer(languages: ["ar"]).render(.menuOpenIn("a\u{1b}b"), isolatingValues: true, escapingValues: true)
        #expect(text.contains("\u{2068}a\\u001bb\u{2069}"), "\(text.debugDescription)")
    }

    @Test func positionalPlaceholdersReorderArguments() {
        let text = Localizer(languages: ["ja"]).render(.menuAgentIn("Claude Code", "Ghostty"))
        #expect(text == "GhosttyでClaude Codeを起動")
        #expect(Localizer(languages: ["ko"]).render(.menuAgentVariantIn("Claude Code", "Continue", "Ghostty")) == "Claude Code: Ghostty에서 Continue")
    }

    @Test func aMenuBuiltInAnotherLanguageUsesItsTitles() {
        let facts = FakeSystemFacts(
            applications: ["com.mitchellh.ghostty": URL(fileURLWithPath: "/Applications/Ghostty.app")]
        )
        let background = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester"))
        let titles = { (language: String) in
            MenuBuilder(config: .default, facts: facts, localizer: Localizer(languages: [language])).build(for: background).filter { $0.kind != .separator }.map(\.title)
        }
        #expect(titles("en") == ["Open in Ghostty", "New File", "Copy Path"])
        #expect(titles("de") == ["In Ghostty öffnen", "Neue Datei", "Pfad kopieren"])
        #expect(titles("zh-Hans") == ["在“Ghostty”中打开", "新建文件", "拷贝路径"])
        #expect(titles("ar") == ["فتح في Ghostty", "ملف جديد", "نسخ المسار"])
    }

    @Test func newFilesGetALocalizedDefaultName() throws {
        let facts = FakeSystemFacts(directories: ["/Users/tester"])
        let context = HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester"))
        let german = try Planner(facts: facts, localizer: Localizer(languages: ["de"])).plan(.newFile("md"), context: context)
        #expect(german.steps.first == .createFile(CreateFileStep(path: "/Users/tester/unbenannt.md")))
        let english = try Planner(facts: facts).plan(.newFile("md"), context: context)
        #expect(english.steps.first == .createFile(CreateFileStep(path: "/Users/tester/untitled.md")))
    }

    @Test func customTemplatesAndVariantsKeepTheirOwnText() {
        let template = NewFileTemplate(id: "py", title: "Python Script", baseName: "script", fileExtension: "py")
        #expect(template.localizedTitle(Localizer(languages: ["de"])) == "Python Script")
        #expect(template.localizedBaseName(Localizer(languages: ["de"])) == "script")
        let variant = AgentDescriptor.Variant(id: "opus", title: "Use Opus", arguments: ["--model", "opus"])
        #expect(variant.localizedTitle(Localizer(languages: ["de"])) == "Use Opus")
        #expect(KnownAgents.claude.variants[0].localizedTitle(Localizer(languages: ["de"])) == "Letzte Sitzung fortsetzen")
    }

    @Test func theSystemNameOfAnAppIsUsedWhenLocalized() {
        let facts = FakeSystemFacts(applications: ["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")],
                                    displayNames: ["com.apple.Terminal": "终端"])
        let config = Config(terminal: "terminal")
        let chinese = ActionRegistry(config: config, facts: facts, localizer: Localizer(languages: ["zh-Hans"]))
        #expect(chinese.info(.openTerminal(nil)).title == "在“终端”中打开")
        let english = ActionRegistry(config: config, facts: facts, localizer: .english)
        #expect(english.info(.openTerminal(nil)).title == "Open in Terminal")
    }
}

@Suite("Localization details")
struct LocalizationDetailTests {
    private let facts = FakeSystemFacts(directories: ["/Users/tester/code"])

    @Test("a built-in new-file entry reads as one phrase, capitalised the way its language does", arguments: [
        ("en", "md", "New Markdown Document"), ("en", "txt", "New Text Document"),
        ("it", "md", "Nuovo documento Markdown"), ("it", "txt", "Nuovo documento di testo"),
        ("es", "txt", "Nuevo documento de texto"), ("fr", "md", "Nouveau document Markdown"),
        ("ru", "txt", "Новый текстовый документ"), ("de", "txt", "Neues Textdokument"), ("zh-Hans", "md", "新建 Markdown 文稿")
    ])
    func newFileTitles(language: String, template: String, expected: String) {
        let info = ActionRegistry(config: .default, facts: facts, localizer: Localizer(languages: [language])).info(.newFile(template))
        #expect(info.title == expected)
    }

    @Test func aCustomTemplateStillComposesNewWithItsTitle() {
        var config = Config.default
        config.newFile.templates = [NewFileTemplate(id: "py", title: "Python Script", fileExtension: "py")]
        let info = ActionRegistry(config: config, facts: facts, localizer: Localizer(languages: ["es"])).info(.newFile("py"))
        #expect(info.title == "Nuevo Python Script")
    }

    @Test func theSubmenuStillShowsTheStandaloneTemplateTitles() throws {
        let menu = MenuBuilder(config: .default, facts: facts, localizer: Localizer(languages: ["it"]))
            .build(for: HereContext(origin: .container, container: URL(fileURLWithPath: "/Users/tester/code")))
        let newFile = try #require(menu.first { $0.title == "Nuovo file" })
        #expect(newFile.children.map(\.title) == ["Documento di testo", "Documento Markdown", "Documento di Word", "Cartella di lavoro di Excel", "Presentazione di PowerPoint"])
    }

    @Test("right-to-left strings that begin with a Latin name or a placeholder carry a right-to-left mark", arguments: LanguageManifest.rightToLeft)
    func rightToLeftMarks(language: String) {
        let localizer = Localizer(languages: [language])
        func rendered(_ key: LocalizationKey) -> String { localizer.render(filled(key)) }
        // A text that is only its value (a path) is shown as it is, and a mark would end up in the copied path.
        for key in LocalizationKey.allCases where key != .newFileBaseName && Localizations.table[key.rawValue]?["en"] != "%@" {
            let text = rendered(key)
            guard let first = text.drop(while: { $0 == " " }).first else { continue }
            if first.isASCII && first.isLetter { Issue.record("\(language) \(key.rawValue) starts with a Latin letter and no mark: \(text)") }
        }
        let marked = LocalizationKey.allCases.filter { rendered($0).hasPrefix("\u{200F}") }
        #expect(!marked.isEmpty, "\(language) has no string that needed a mark")
    }

    @Test("a command that ends in a bracket is followed by a left-to-right mark, or the bracket is drawn mirrored", arguments: LanguageManifest.rightToLeft)
    func commandsEndingInABracketAreMarked(language: String) {
        var found = 0
        for (key, translations) in Localizations.table.sorted(by: { $0.key < $1.key }) {
            guard let text = translations[language] else { continue }
            // The backticks are paired one after the other (the first with the second, the third with the fourth): the text between
            // two commands is not a command, even when it ends in a bracket as in "... (`rh x`)".
            for span in text.matches(of: #/`[^`]*`/#) {
                guard let last = text[span.range].dropFirst().dropLast().last, "<>()[]{}".contains(last) else { continue }
                found += 1
                #expect(text[span.range.upperBound...].first == "\u{200E}", "\(language) \(key) has a command that ends in a bracket and no mark after it")
            }
        }
        #expect(found > 0, "\(language) has no such command, so this checks nothing")
    }

    @Test("a path written in a right-to-left sentence reads left to right in one piece", arguments: LanguageManifest.rightToLeft)
    func pathsInRightToLeftSentencesAreNotScrambled(language: String) {
        // `~/.local/bin` sat in a sentence as plain text: its leading `~/.` are neutral characters between Arabic and Latin letters
        // and took the direction of the sentence, so it was drawn `local/bin./~`. A path is a value of the message, and the window
        // puts a value in an isolate. This lays every text out with CoreText, as the window does, and finds a path that is still
        // written in the translation itself.
        let localizer = Localizer(languages: [language])
        #expect(localizer.isRightToLeft)
        var checked = 0
        for key in LocalizationKey.allCases where key != .newFileBaseName {
            let text = localizer.render(filled(key), isolatingValues: true)
            for path in scrambledPaths(in: text) {
                Issue.record("\(language) \(key.rawValue): \"\(path)\" is not drawn in one piece, left to right: \(text)")
            }
            checked += 1
        }
        #expect(checked > 100)
    }

    @Test("a command between backticks is drawn left to right in one piece in a right-to-left sentence", arguments: LanguageManifest.rightToLeft)
    func commandsInRightToLeftSentencesAreNotScrambled(language: String) {
        // The commands are text of the translation, not values, so no isolate reaches them; what keeps one whole is that it starts and
        // ends with a letter or a character that goes with it (a command that ends in a bracket carries a left-to-right mark).
        let localizer = Localizer(languages: [language])
        var commands = 0
        for key in LocalizationKey.allCases where key != .newFileBaseName {
            let text = localizer.render(filled(key), isolatingValues: true)
            commands += text.filter { $0 == "`" }.count / 2
            for command in scrambledCommands(in: text) {
                Issue.record("\(language) \(key.rawValue): the command \"\(command)\" is not drawn in one piece, left to right: \(text)")
            }
        }
        #expect(commands > 20, "\(language) has too few commands for this to check anything")
    }

    @Test func theLayoutChecksSeeAScrambledPathAndCommandAndAcceptTheFixedOnes() {
        // Controls for the two checks above: without them a helper that finds nothing would pass every language.
        let sentence = "أضف %@ إلى PATH في ملف إعدادات الصدفة لديك."
        #expect(scrambledPaths(in: sentence.replacingOccurrences(of: "%@", with: "~/.local/bin")) == ["~/.local/bin"])
        #expect(scrambledPaths(in: sentence.replacingOccurrences(of: "%@", with: "\u{2068}~/.local/bin\u{2069}")).isEmpty)
        // A command that ends in a bracket has its bracket drawn on the wrong side unless a left-to-right mark follows it.
        #expect(!scrambledCommands(in: "شغّل `rh config sync enable --folder <folder>` ثم أعد المحاولة").isEmpty)
        #expect(scrambledCommands(in: "شغّل `rh config sync enable --folder <folder>`\u{200E} ثم أعد المحاولة").isEmpty)
    }

    @Test("a value that is a path is drawn in one piece in a right-to-left sentence", arguments: LanguageManifest.rightToLeft)
    func aPathValueIsDrawnInOnePiece(language: String) {
        // The positive side of the test above: the value of the "rh on your PATH" fix is put in its isolate and read left to right.
        let localizer = Localizer(languages: [language])
        let text = localizer.render(.doctorFixCliPath("~/.local/bin"), isolatingValues: true)
        #expect(text.contains("\u{2068}~/.local/bin\u{2069}"), "\(text)")
        #expect(scrambledPaths(in: text).isEmpty, "\(text)")
    }

    @Test("a name that becomes a file name never carries a direction mark", arguments: LanguageManifest.rightToLeft)
    func fileNamesAreClean(language: String) {
        let name = Localizer(languages: [language]).string(.newFileBaseName)
        #expect(!name.contains("\u{200F}"))
    }
}

@Suite("Localization of values in a window")
struct LocalizationIsolationTests {
    private let path = "/Applications/Right Here.app/Contents/Helpers/rh"
    private let first = "\u{2068}", end = "\u{2069}"

    @Test func theLanguagesTheManifestCallsRightToLeftAreTheOnesTheSystemDoes() {
        for language in LanguageManifest.current.languages {
            #expect(Localizer(languages: [language.code]).isRightToLeft == (language.rtl == true), "\(language.code)")
        }
    }

    @Test("a value in a right-to-left sentence is put in an isolate, so the sentence cannot reorder a path",
          arguments: LanguageManifest.rightToLeft)
    func valuesAreIsolated(language: String) {
        let localizer = Localizer(languages: [language])
        let plain = localizer.render(.doctorRunnerOk(path))
        #expect(plain.contains(path) && !plain.contains(first))
        #expect(localizer.render(.doctorRunnerOk(path), isolatingValues: true) == plain.replacingOccurrences(of: path, with: first + path + end))
        // Each of several values, so a sentence with a number and a name keeps both in place.
        let several = localizer.render(.doctorServicesDiffer("3", "1", "0"), isolatingValues: true)
        for value in ["3", "1", "0"] { #expect(several.contains(first + value + end), "\(language): \(several)") }
    }

    @Test func aLeftToRightLanguageIsLeftAlone() {
        for language in Localizations.languages where !LanguageManifest.rightToLeft.contains(language) {
            let localizer = Localizer(languages: [language])
            #expect(localizer.render(.doctorRunnerOk(path), isolatingValues: true) == localizer.render(.doctorRunnerOk(path)), "\(language)")
        }
    }

    @Test func aTextThatIsOnlyItsValueIsShownAsItIsInEveryLanguage() {
        for language in Localizations.languages {
            #expect(Localizer(languages: [language]).render(.doctorVerbatim(path), isolatingValues: true) == path, "\(language)")
        }
    }

    @Test func withoutTheOptionNothingIsAdded() {
        // The menu, the alerts and the names of Services and files are rendered this way and must not carry invisible marks.
        for language in Localizations.languages {
            let text = Localizer(languages: [language]).render(.menuOpenIn("Ghostty"))
            #expect(!text.contains(first) && !text.contains(end), "\(language)")
        }
    }
}
