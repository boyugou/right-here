import Foundation
import Testing
@testable import RightHereCore
@testable import RightHereKit

private func entry(_ title: String) -> MenuNode {
    MenuNode(kind: .action, title: title, icon: nil, actionID: "test." + title, children: [])
}

private func group(_ title: String, _ children: [MenuNode]) -> MenuNode {
    MenuNode(kind: .submenu, title: title, icon: nil, actionID: nil, children: children)
}

@Suite("MenuPreview: which submenus can be open")
struct MenuSubmenuTests {
    private let menu = [
        entry("Run"),
        group("Open With", [entry("Terminal"), MenuNode(kind: .separator, title: "", icon: nil, actionID: nil, children: []), entry("Zed")]),
        group("Copy Path", [entry("Full Path")]),
        group("Empty", [])
    ]

    @Test func onlySubmenusWithEntriesCanBeOpen() {
        #expect(MenuPreview.submenuIDs(menu) == ["1", "2"])
    }

    @Test func nestedSubmenusAreFoundAtEveryDepth() {
        let nested = [group("More", [entry("Continue"), group("Presets", [entry("Review")])])]
        #expect(MenuPreview.submenuIDs(nested) == ["0", "0.1"])
    }

    @Test func aMenuWithoutSubmenusHasNoneToOpen() {
        #expect(MenuPreview.submenuIDs([entry("Run")]).isEmpty)
        #expect(MenuPreview.submenuIDs([]).isEmpty)
    }

    @Test func aMenuThatChangedKeepsOnlyTheOpenSubmenusItStillHas() {
        // The ids are positions: "2" was Copy Path, and after the config dropped that entry a "2" would open whatever is now third.
        let changed = [entry("Run"), group("Open With", [entry("Terminal")])]
        #expect(MenuPreview.keepingOpen(["1", "2", "7"], in: changed) == ["1"])
        #expect(MenuPreview.keepingOpen(["1", "2"], in: menu) == ["1", "2"])
        #expect(MenuPreview.keepingOpen([], in: menu).isEmpty)
    }
}
