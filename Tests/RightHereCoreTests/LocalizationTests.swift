import Foundation
import Testing
@testable import RightHereCore

private func placeholders(_ text: String) -> [String] {
    text.matches(of: #/%(?:\d+\$)?@/#).map { String(text[$0.range]) }.sorted()
}

@Suite("Localization catalog")
struct LocalizationCatalogTests {
    @Test func thirtyLanguagesAreShipped() {
        #expect(Localizations.languages.count == 30)
        #expect(Localizations.languages.first == "en")
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
        #expect(Localizer(languages: ["zh-Hans"]).string(.menuOpenIn, "Ghostty") == "在Ghostty中打开")
    }

    @Test func positionalPlaceholdersReorderArguments() {
        let text = Localizer(languages: ["ja"]).string(.menuAgentIn, "Claude Code", "Ghostty")
        #expect(text == "GhosttyでClaude Code")
        #expect(Localizer(languages: ["ko"]).string(.menuAgentVariantIn, "Claude Code", "Continue", "Ghostty") == "Ghostty에서 Claude Code: Continue")
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
        #expect(titles("zh-Hans") == ["在Ghostty中打开", "新建文件", "拷贝路径"])
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
        struct NamedFacts: SystemFacts {
            var base = FakeSystemFacts(applications: ["com.apple.Terminal": URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")])
            var homeDirectory: URL { base.homeDirectory }
            var currentDirectory: URL { base.currentDirectory }
            var loginShell: String { base.loginShell }
            func isDirectory(_ url: URL) -> Bool? { base.isDirectory(url) }
            func fileExists(_ url: URL) -> Bool { base.fileExists(url) }
            func gitRoot(containing url: URL) -> URL? { base.gitRoot(containing: url) }
            func applicationURL(bundleID: String) -> URL? { base.applicationURL(bundleID: bundleID) }
            func displayName(bundleID: String) -> String? { bundleID == "com.apple.Terminal" ? "终端" : nil }
            func isRunning(bundleID: String) -> Bool { false }
            func environment(_ key: String) -> String? { nil }
        }
        let config = Config(terminal: "terminal")
        let chinese = ActionRegistry(config: config, facts: NamedFacts(), localizer: Localizer(languages: ["zh-Hans"]))
        #expect(chinese.info(.openTerminal(nil)).title == "在终端中打开")
        let english = ActionRegistry(config: config, facts: NamedFacts(), localizer: .english)
        #expect(english.info(.openTerminal(nil)).title == "Open in Terminal")
    }
}
