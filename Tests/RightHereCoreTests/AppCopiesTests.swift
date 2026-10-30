import Foundation
import Testing
@testable import RightHereCore

@Suite("AppCopies: which installed copy of the app is the newest")
struct AppCopiesTests {
    private let home = "/Users/tester"

    @Test func onlyCopiesInAnApplicationsFolderAreInstalledAndTheNewestComesFirst() {
        let copies = [
            AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.2"),
            AppCopy(path: "/Volumes/Right Here/Right Here.app", version: "0.3.9"),
            AppCopy(path: "/Users/tester/Projects/right-here/dist/Right Here.app", version: "0.4.0"),
            AppCopy(path: "/Applications/Right Here.app", version: "0.3.10"),
            AppCopy(path: "/Applications/Right Here.app", version: "0.3.10")
        ]
        #expect(AppCopies.installed(copies, home: home).map(\.path) == ["/Applications/Right Here.app", "/Users/tester/Applications/Right Here.app"],
                "a disk image and a build folder are not installed, a copy is counted once, and 0.3.10 is newer than 0.3.2")
    }

    @Test func theCopyToKeepIsANewerOneOrOfOneVersionTheOneInTheMacsApplicationsFolder() {
        let installed = AppCopies.installed([AppCopy(path: "/Applications/Right Here.app", version: "0.3.7"), AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.2")], home: "/Users/tester")
        #expect(AppCopies.toKeep(instead: AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.2"), among: installed)?.path == "/Applications/Right Here.app")
        #expect(AppCopies.toKeep(instead: AppCopy(path: "/Applications/Right Here.app", version: "0.3.7"), among: installed) == nil, "the copy to keep is the one that runs")
        #expect(AppCopies.toKeep(instead: AppCopy(path: "/elsewhere/Right Here.app", version: "0.3.7"), among: installed) == nil, "a build folder of the same version gives way to nothing")
        #expect(AppCopies.toKeep(instead: AppCopy(path: "/elsewhere/Right Here.app", version: "0.3.1"), among: installed)?.path == "/Applications/Right Here.app")
        // Two copies of one version: the one the doctor says to move to the Trash does not set anything up either.
        let twins = AppCopies.installed([AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.11"), AppCopy(path: "/Applications/Right Here.app", version: "0.3.11")], home: "/Users/tester")
        #expect(AppCopies.toKeep(instead: AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.11"), among: twins)?.path == "/Applications/Right Here.app")
    }

    @Test func versionsCompareByTheirNumbers() {
        #expect(AppCopies.newer("0.3.7", than: nil) && !AppCopies.newer(nil, than: "0.1"))
        #expect(!AppCopies.newer("1.0.0", than: "1.0") && !AppCopies.newer("1.0", than: "1.0.0") && AppCopies.newer("1.0.1", than: "1.0"))
        #expect(AppCopies.newer("0.10", than: "0.9") && AppCopies.newer("0.3.10", than: "0.3.9"))
        #expect(AppCopies.newer("0.3.12b1", than: "0.3.11"), "a part that is not only a number still counts by its number")
    }

    @Test func ofTwoCopiesOfOneVersionTheMacsApplicationsFolderComesFirst() {
        let copies = [AppCopy(path: "/Users/tester/Applications/Right Here.app", version: "0.3.9"), AppCopy(path: "/Applications/Right Here.app", version: "0.3.9")]
        #expect(AppCopies.installed(copies, home: "/Users/tester").first?.path == "/Applications/Right Here.app")
    }
}

@Suite("AppIdentity: the guide on the website")
struct GuideURLTests {
    @Test func theGuideOpensInTheLanguageOfTheWindow() {
        #expect(AppIdentity.guideURL(language: "zh-Hans").absoluteString == "https://boyugou.github.io/right-here/docs.html?lang=zh-Hans")
        #expect(AppIdentity.guideURL(language: "pt-BR").absoluteString == "https://boyugou.github.io/right-here/docs.html?lang=pt-BR")
    }
}

@Suite("KnownAgents: install pages")
struct AgentInstallPageTests {
    @Test func everyInstallPageIsAnHTTPSPage() {
        let pages = KnownAgents.all.compactMap(\.installPage)
        #expect(KnownAgents.all.filter { $0.installPage == nil }.map(\.id) == ["muse"], "Muse Code has none: no page could be confirmed")
        #expect(pages.allSatisfy { $0.scheme == "https" && $0.host != nil }, "\(pages)")
    }
}
