import Foundation
import Testing
@testable import RightHereCore

private func placeholders(_ text: String) -> [String] {
    text.matches(of: #/%(?:\d+\$)?@/#).map { String(text[$0.range]) }.sorted()
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
        ("zh", "zh-Hans"), ("de_AT", "de")
    ])
    func resolves(tag: String, expected: String) {
        #expect(Localizer(languages: [tag]).resolvedLanguage == expected)
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
        #expect(Localizer.english.string(.menuOpenIn, "Ghostty") == "Open in Ghostty")
        #expect(Localizer(languages: ["de"]).string(.menuOpenIn, "Ghostty") == "In Ghostty öffnen")
        #expect(Localizer(languages: ["zh-Hans"]).string(.menuOpenIn, "Ghostty") == "在“Ghostty”中打开")
    }

    @Test func positionalPlaceholdersReorderArguments() {
        let text = Localizer(languages: ["ja"]).string(.menuAgentIn, "Claude Code", "Ghostty")
        #expect(text == "GhosttyでClaude Codeを起動")
        #expect(Localizer(languages: ["ko"]).string(.menuAgentVariantIn, "Claude Code", "Continue", "Ghostty") == "Claude Code: Ghostty에서 Continue")
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
        #expect(newFile.children.map(\.title) == ["Documento di testo", "Documento Markdown"])
    }

    @Test("right-to-left strings that begin with a Latin name or a placeholder carry a right-to-left mark", arguments: LanguageManifest.rightToLeft)
    func rightToLeftMarks(language: String) {
        let localizer = Localizer(languages: [language])
        for key in LocalizationKey.allCases where key != .newFileBaseName {
            let text = localizer.string(key, "X", "Y", "Z")
            guard let first = text.drop(while: { $0 == " " }).first else { continue }
            if first.isASCII && first.isLetter { Issue.record("\(language) \(key.rawValue) starts with a Latin letter and no mark: \(text)") }
        }
        let marked = LocalizationKey.allCases.filter { localizer.string($0, "X", "Y", "Z").hasPrefix("\u{200F}") }
        #expect(!marked.isEmpty, "\(language) has no string that needed a mark")
    }

    @Test("a name that becomes a file name never carries a direction mark", arguments: LanguageManifest.rightToLeft)
    func fileNamesAreClean(language: String) {
        let name = Localizer(languages: [language]).string(.newFileBaseName)
        #expect(!name.contains("\u{200F}"))
    }
}
