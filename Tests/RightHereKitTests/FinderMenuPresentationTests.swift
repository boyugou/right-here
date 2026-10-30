import Foundation
import Testing
import RightHereCore
@testable import RightHereKit

@Suite("FinderMenuPresentation: what the menu is like when it is given to Finder")
struct FinderMenuPresentationTests {
    private let menu: [MenuNode] = [
        MenuNode(kind: .action, title: "Open in Ghostty", icon: .app("com.mitchellh.ghostty"), actionID: "open.terminal", children: []),
        .separator,
        MenuNode(kind: .submenu, title: "Open With", icon: .symbol("arrow.up.forward.app"), actionID: nil, children: [
            MenuNode(kind: .action, title: "Terminal", icon: .app("com.apple.Terminal"), actionID: "open.terminal@terminal", children: []),
            MenuNode(kind: .action, title: "iTerm", icon: .app("com.googlecode.iterm2"), actionID: "open.terminal@iterm", children: []),
            .separator,
            MenuNode(kind: .action, title: "Cursor", icon: .app("com.todesktop.230313mzl4w4u92"), actionID: "open.app.cursor", children: [])
        ]),
        .separator,
        MenuNode(kind: .action, title: "Copy Path", icon: .symbol("doc.on.doc"), actionID: "copy-path.absolute", children: [])
    ]

    @Test func macOS26DrawsASeparatorAsAnEmptyRowAndSoTheMenuGoesWithoutThemThere() {
        // A reported screenshot of Finder on macOS 26.5.1 shows an empty row of the height of an entry where each separator is.
        #expect(!FinderMenuPresentation.showsSeparators(osMajorVersion: 26))
        #expect(!FinderMenuPresentation.showsSeparators(osMajorVersion: 15))
        #expect(FinderMenuPresentation.showsSeparators(osMajorVersion: 27))
        #expect(FinderMenuPresentation.showsSeparators(osMajorVersion: 28))
    }

    @Test func withoutSeparatorsNoneIsLeftAtAnyDepthAndEverythingElseIsAsItWas() {
        let given = FinderMenuPresentation.nodes(menu, separators: false)
        #expect(given.map(\.title) == ["Open in Ghostty", "Open With", "Copy Path"])
        #expect(given[1].children.map(\.title) == ["Terminal", "iTerm", "Cursor"])
        #expect(given[1].icon == .symbol("arrow.up.forward.app") && given[1].children[2].actionID == "open.app.cursor" && given[0].icon == .app("com.mitchellh.ghostty"))
        #expect(given.allSatisfy { $0.kind != .separator } && given[1].children.allSatisfy { $0.kind != .separator })
    }

    @Test func withSeparatorsTheMenuIsGivenAsItIs() {
        #expect(FinderMenuPresentation.nodes(menu, separators: true) == menu)
    }

    @Test func aMenuThatIsOnlySeparatorsIsEmptyAndAMenuWithoutAnyIsTheSame() {
        #expect(FinderMenuPresentation.nodes([.separator, .separator], separators: false).isEmpty)
        let plain = [MenuNode(kind: .action, title: "A", icon: nil, actionID: "a", children: [])]
        #expect(FinderMenuPresentation.nodes(plain, separators: false) == plain)
    }

    @Test func aSubmenuThatHeldOnlySeparatorsIsKeptEmptyForTheCallerToDecide() {
        let nodes = [MenuNode(kind: .submenu, title: "S", icon: nil, actionID: nil, children: [.separator])]
        let given = FinderMenuPresentation.nodes(nodes, separators: false)
        #expect(given.count == 1 && given[0].children.isEmpty)
    }
}
