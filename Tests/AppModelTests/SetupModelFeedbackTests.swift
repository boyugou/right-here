import Foundation
import Testing
import RightHereCore
import RightHereKit
@testable import AppModel

@Suite("The setup window's feedback")
@MainActor
struct SetupModelFeedbackTests {
    @Test func copyingAProblemKeepsTheWholeMessageAndTheProblemOnScreen() async throws {
        var copied: [String] = []
        let folder = URL(fileURLWithPath: "/work/" + String(repeating: "long name /", count: 400) + "notes")
        let mac = try Mac(pickFolder: { _ in folder }, writeClipboard: { copied.append($0) })
        defer { mac.cleanUp() }
        mac.model.selectedTab = .worktrees
        await mac.model.chooseRepository()
        let notice = try #require(mac.model.notice)
        let message = Localizer.system.render(notice.message)
        #expect(message.count > 4_000)
        #expect(mac.model.copyNotice(notice))
        #expect(copied == [message])
        #expect(mac.model.notice == notice, "copying must not replace the problem with a success message")
        #expect(mac.model.selectedTab == .worktrees)
        mac.model.dismissNotice()
        #expect(mac.model.notice == nil)
        #expect(!mac.model.copyNotice(notice), "a dismissed view must not copy a stale message")
        #expect(copied == [message])
    }

    @Test func aChangedMessageAndASnippetConfirmationAreNotCopiedAsTheOldProblem() async throws {
        var copied: [String] = []
        let mac = try Mac(pickFolder: { _ in URL(fileURLWithPath: "/work/notes") }, writeClipboard: { copied.append($0) })
        defer { mac.cleanUp() }
        await mac.model.chooseRepository()
        let oldProblem = try #require(mac.model.notice)
        mac.model.copyMCPConfiguration()
        let confirmation = try #require(mac.model.notice)
        #expect(copied == [SetupSnippets.mcpConfiguration(command: mac.model.mcpCommand)])
        #expect(!mac.model.copyNotice(oldProblem))
        #expect(!mac.model.copyNotice(confirmation))
        #expect(copied.count == 1, "copying a snippet must leave the actual snippet on the clipboard")
        #expect(mac.model.notice == confirmation)
    }
}
