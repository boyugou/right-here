import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

private func check(_ id: CheckID, _ status: DoctorCheck.Status, detail: LocalizedMessage? = nil) -> DoctorCheck {
    DoctorCheck(id, status: status, detail: detail)
}

@Suite("Setup window: the summary of the checks")
struct SetupSummaryTests {
    @Test func beforeTheDoctorHasAnsweredNothingIsClaimed() {
        // The window used to say "Everything is set up." in green until the first answer came, which is also what a person
        // who has not switched the Finder extension on sees for the first second of the first run.
        let summary = SetupSummary()
        #expect(summary.state == .checking)
        #expect(summary.openChecks.isEmpty)
        #expect(!summary.extensionNeedsSetup)
        #expect(summary.terminal == nil)
        for tab in SetupTab.allCases { #expect(summary.badge(for: tab) == nil) }
    }

    @Test func everythingOkIsAllSet() {
        let summary = SetupSummary(checks: [check(.config, .ok), check(.finderExtension, .ok)])
        #expect(summary.state == .allSet)
        #expect(summary.openChecks.isEmpty)
    }

    @Test func aWarningNeedsAttentionToo() {
        let summary = SetupSummary(checks: [check(.config, .ok), check(.cliLink, .warn), check(.services, .ok), check(.finderRunner, .fail)])
        #expect(summary.state == .needsAttention)
        #expect(summary.openChecks.map(\.id) == [.cliLink, .finderRunner])
    }

    @Test func theCommandLinkNotBeingOnPathDoesNotMakeAFirstRunThatWentWellNeedAttention() {
        // The runner script and the MCP command name `rh` by its full path, so only a person who types `rh` in a terminal has anything to do.
        // The Checks page still lists the row; it is the window's state and the badge that leave it out.
        let notOnPath = DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath("~/.local/bin/rh"), fix: .doctorFixCliPath("~/.local/bin"))
        let summary = SetupSummary(checks: [check(.config, .ok), notOnPath, check(.finderExtension, .ok)])
        #expect(summary.state == .allSet)
        #expect(summary.openChecks.map(\.id) == [.cliLink], "the page of the checks lists it")
        #expect(summary.badge(for: .checks) == nil)
        #expect(summary.openTitles(in: .english).isEmpty)
    }

    @Test func aMissingCommandLinkAndEveryOtherRowStillNeedAttention() {
        let missing = DoctorCheck(.cliLink, status: .warn, detail: .doctorCliMissing("~/.local/bin/rh"), fix: .doctorFixRunSetup)
        let summary = SetupSummary(checks: [missing, check(.editorDefault, .warn)])
        #expect(summary.state == .needsAttention)
        #expect(summary.badge(for: .checks) == .attention(2))
        let onlyPath = DoctorCheck(.cliLink, status: .warn, detail: .doctorCliNotOnPath("~/.local/bin/rh"), fix: .doctorFixCliPath("~/.local/bin"))
        #expect(SetupSummary(checks: [onlyPath, check(.editorDefault, .warn)]).badge(for: .checks) == .attention(1), "the editor still counts")
    }

    @Test func aClaudeLinkWithoutItsHandlerAndNoAgentsAtAllAreWarningsThePersonMayLeave() {
        // The handler is made when Claude Code is started once; a person who picked no agents has nothing to add. Neither is for the window to ask about.
        let link = DoctorCheck(.claudeLink, status: .warn, detail: .doctorClaudeLinkMissing("claude"), fix: .doctorFixClaudeLink)
        let none = DoctorCheck(.agents, status: .warn, detail: .doctorAgentsNone, fix: .doctorFixAgentsAdd("agents = [\"claude\"]"))
        let summary = SetupSummary(checks: [check(.config, .ok), link, none])
        #expect(summary.state == .allSet)
        #expect(summary.openChecks.map(\.id) == [.claudeLink, .agents], "the page of the checks lists both")
        #expect(summary.badge(for: .checks) == nil)
    }

    @Test func anAgentThatIsNotFoundAndAFailingLinkStillNeedAttention() {
        let notFound = DoctorCheck(.agent("claude"), status: .warn, detail: .doctorAgentNotFound("claude"))
        let brokenLink = DoctorCheck(.claudeLink, status: .fail, detail: .doctorClaudeLinkMissing("claude"))
        #expect(SetupSummary(checks: [notFound]).state == .needsAttention)
        #expect(SetupSummary(checks: [brokenLink]).state == .needsAttention, "only a warning is the person's to leave")
    }

    @Test("the first-run card is due while the extension is not registered or is switched off, and only then", arguments: [
        (DoctorCheck.Status.fail, true), (.needsUser, true), (.warn, false), (.ok, false)
    ])
    func theFirstRunCard(status: DoctorCheck.Status, due: Bool) {
        // A warning says the extension is on and registered more than once: nothing to switch on, so no card (the card and
        // the poll behind it used to wait for such a row forever).
        #expect(SetupSummary(checks: [check(.config, .ok), check(.finderExtension, status)]).extensionNeedsSetup == due)
    }

    @Test func aRowOtherThanTheExtensionsNeverMakesItFirstRun() {
        #expect(!SetupSummary(checks: [check(.finderRunner, .fail), check(.agents, .needsUser)]).extensionNeedsSetup)
    }

    @Test func theOpenTitlesAreWrittenInTheLanguageOfTheWindow() {
        let summary = SetupSummary(checks: [check(.config, .ok), check(.finderExtension, .needsUser), check(.editorDefault, .warn)])
        #expect(summary.openTitles(in: .english) == ["Finder extension", "Default editor"])
        #expect(summary.openTitles(in: Localizer(languages: ["de"])) == [
            Localizer(languages: ["de"]).string(.appCheckExtension), Localizer(languages: ["de"]).string(.appCheckEditor)
        ])
    }

    @Test func theChecksCanBeLookedUpById() {
        let summary = SetupSummary(checks: [check(.config, .ok), check(.agent("claude"), .warn)])
        #expect(summary.check(.agent("claude"))?.status == .warn)
        #expect(summary.check(.services) == nil)
    }
}

@Suite("Setup window: the app a default check names")
struct DefaultAppNameTests {
    @Test func theNameIsTheValueOfTheMessageWhateverTheLanguage() {
        // The window used to cut "Open in " (and two translations of it) off the rendered sentence, so a Spanish window
        // showed "Abrir en Ghostty" as the name of the terminal.
        let terminal = check(.terminalDefault, .ok, detail: .menuOpenIn("Ghostty"))
        #expect(terminal.openedApp == "Ghostty")
        for language in Localizer.supportedLanguages {
            let localizer = Localizer(languages: [language])
            let sentence = localizer.render(.menuOpenIn("Ghostty"))
            #expect(sentence.contains("Ghostty"), "\(language): \(sentence)")
            #expect(terminal.openedApp == "Ghostty", "\(language)")
        }
    }

    @Test func theNameIsTheOneTheSystemGivesTheApp() {
        #expect(check(.terminalDefault, .ok, detail: .menuOpenIn("终端")).openedApp == "终端")
        #expect(check(.editorDefault, .ok, detail: .menuOpenIn("Visual Studio Code")).openedApp == "Visual Studio Code")
    }

    @Test func whenTheConfiguredAppIsMissingTheOneThatTakesItsPlaceIsOpened() {
        let fallback = check(.terminalDefault, .warn, detail: .doctorAppFallback("iTerm", "Ghostty"))
        #expect(fallback.openedApp == "Ghostty")
    }

    @Test("a check that says there is no app names none", arguments: [
        LocalizedMessage.doctorTerminalNone, .doctorEditorNone, .doctorAppNotInstalled("Ghostty"), .doctorVerbatim("something else")
    ])
    func noApp(detail: LocalizedMessage) {
        #expect(check(.terminalDefault, .fail, detail: detail).openedApp == nil)
    }

    @Test func aCheckWithoutADetailNamesNone() {
        #expect(check(.terminalDefault, .fail).openedApp == nil)
    }

    @Test func theSummaryReadsTheTerminalAndTheEditorFromTheirChecks() {
        let summary = SetupSummary(checks: [
            check(.terminalDefault, .ok, detail: .menuOpenIn("Ghostty")), check(.editorDefault, .warn, detail: .doctorEditorNone)
        ])
        #expect(summary.terminal == "Ghostty")
        #expect(summary.editor == nil)
    }
}

@Suite("Setup window: the sidebar")
struct SetupTabTests {
    @Test func theSectionsAreListedInTheOrderOfUse() {
        #expect(SetupTab.allCases == [.overview, .menu, .agents, .config, .checks, .ai, .worktrees, .folders])
        #expect(Set(SetupTab.allCases.map(\.id)).count == SetupTab.allCases.count)
    }

    @Test func theChecksRowCountsTheChecksThatAreNotOk() {
        let summary = SetupSummary(checks: [check(.config, .ok), check(.cliLink, .warn), check(.finderRunner, .fail), check(.services, .ok)])
        #expect(summary.badge(for: .checks) == .attention(2))
    }

    @Test func aHealthySetupHasNoBadge() {
        let summary = SetupSummary(checks: [check(.config, .ok), check(.finderExtension, .ok)])
        for tab in SetupTab.allCases { #expect(summary.badge(for: tab) == nil) }
    }

    @Test func onlyTheChecksRowHasABadge() {
        let summary = SetupSummary(checks: [check(.finderExtension, .needsUser), check(.cliLink, .warn)])
        #expect(SetupTab.allCases.filter { summary.badge(for: $0) != nil } == [.checks])
    }
}

@Suite("Setup window: a list of checks")
struct CheckListTests {
    @Test func aRowThatIsThereIsReplacedInPlace() {
        let list = [check(.config, .ok), check(.finderLaunch, .fail), check(.services, .ok)]
        let updated = list.replacingOrAppending(check(.finderLaunch, .ok))
        #expect(updated.map(\.id) == [.config, .finderLaunch, .services])
        #expect(updated[1].status == .ok)
    }

    @Test func aRowThatIsNotThereGoesLast() {
        let list = [check(.config, .ok), check(.services, .ok)]
        let updated = list.replacingOrAppending(check(.finderLaunch, .ok))
        #expect(updated.map(\.id) == [.config, .services, .finderLaunch])
    }

    @Test func replacingAloneStillLeavesAListWithoutThatRowAsItIs() {
        let list = [check(.config, .ok)]
        #expect(list.replacing(check(.finderLaunch, .ok)) == list)
    }
}
