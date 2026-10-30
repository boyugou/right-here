import Foundation

/// The Copy Path settings as something to edit in the window (ADR 0026): which forms the submenu offers and in which order, and the title of the entry. A pure function of the config; the
/// changes it returns are applied through `ConfigService`.
public struct CopyPathState: Sendable, Equatable {
    /// One form of a path that Copy Path can put on the clipboard.
    public struct Form: Sendable, Equatable, Identifiable {
        public var id: String { style.rawValue }
        public var style: PathStyle
        /// As the Finder menu says it, in the person's language.
        public var title: String

        public init(style: PathStyle, title: String) {
            self.style = style
            self.title = title
        }
    }

    /// `copy_path.title` as the config says it; `nil` when it says none (the menu then says "Copy Path" in the person's language).
    public var title: String?
    /// The forms the menu offers, in order.
    public var offered: [Form]
    /// The forms it does not offer: a check puts one at the end.
    public var others: [Form]
    /// The forms as a list to edit (`copy_path.styles`).
    public var list: ArgumentList

    public init(title: String?, offered: [Form], others: [Form], list: ArgumentList) {
        self.title = title
        self.offered = offered
        self.others = others
        self.list = list
    }
}

public enum CopyPathOptions {
    public static let stylesKey = "copy_path.styles"
    public static let titleKey = "copy_path.title"

    /// - Parameter listed: What the file that decides `copy_path.styles` writes for it (`ConfigService.listed`).
    public static func state(config: Config, localizer: Localizer, listed: [String]?) -> CopyPathState {
        func form(_ style: PathStyle) -> CopyPathState.Form { CopyPathState.Form(style: style, title: localizer.copyPath(style)) }
        let offered = config.copyPathStyles
        let list = ArgumentList(key: stylesKey, items: offered.map(\.rawValue), listed: listed, defaults: Config.defaultCopyPathStyles.map(\.rawValue))
        return CopyPathState(title: config.copyPathTitle, offered: offered.map(form), others: PathStyle.allCases.filter { !offered.contains($0) }.map(form), list: list)
    }

    /// The title of the entry; empty is the setting taken out (the menu says "Copy Path" in the person's language). The config refuses a title that is not a plain name.
    public static func operations(settingTitle title: String, in state: CopyPathState) -> [ConfigOperation] {
        let text = title.trimmingCharacters(in: .whitespaces)
        if text.isEmpty { return state.title == nil ? [] : [.unset(titleKey)] }
        guard text != state.title else { return [] }
        return [.set(titleKey, .string(text))]
    }

    /// A form put in the menu, at the end of the list.
    public static func operations(adding style: PathStyle, to state: CopyPathState) -> [ConfigOperation] {
        state.offered.contains { $0.style == style } ? [] : state.list.adding(style.rawValue)
    }

    /// The form at `position` (from 1) taken out of the menu.
    public static func operations(removingAt position: Int, from state: CopyPathState) -> [ConfigOperation] {
        state.list.removing(at: position)
    }

    /// What a drag in the list says (SwiftUI's `onMove`, counting from 0).
    public static func operations(moving source: IndexSet, to destination: Int, in state: CopyPathState) -> [ConfigOperation] {
        state.list.moving(source, to: destination)
    }
}
