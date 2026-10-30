import RightHereCore
import RightHereKit

/// The page of one thing that a section shows in place of its list.
enum DetailPage: Equatable {
    case variant(VariantRef)
    case agent(String)
    case preset(String)
    case template(String)
    case app(String)
}

extension SetupModel {
    /// Which page of one thing is open in the section that is shown. The sections show it and the header names it from this one answer, so the two
    /// cannot tell different stories; a page of a thing that is gone is no page.
    var openDetailPage: DetailPage? {
        switch selectedTab {
        case .agents:
            // A start option's page is opened from its agent's page, so it is the one in front when both are set.
            if let open = variantDetail, variant(open.agent, open.id) != nil { return .variant(open) }
            if let open = agentDetail, agentOptions(open) != nil { return .agent(open) }
            if let open = presetDetail, preset(open) != nil { return .preset(open) }
        case .menu:
            if let open = templateDetail, template(open) != nil { return .template(open) }
        case .overview:
            if !needsFirstRunChoice, let open = appDetail, app(open) != nil { return .app(open) }
        case .config, .checks, .ai, .worktrees, .folders:
            break
        }
        return nil
    }

    /// What the header says of the open page: its name, and the name of the page its back button returns to (its tooltip, and what VoiceOver
    /// calls it).
    func detailHeader(_ l10n: Localizer) -> (title: String, parent: String)? {
        switch openDetailPage {
        case .variant(let ref)?:
            guard let row = variant(ref.agent, ref.id) else { return nil }
            return (row.title, agentOptions(ref.agent)?.name ?? ref.agent)
        case .agent(let id)?:
            guard let options = agentOptions(id) else { return nil }
            return (options.name, l10n.string(SetupTab.agents.titleKey))
        case .preset(let id)?:
            guard let row = preset(id) else { return nil }
            return (row.title, l10n.string(SetupTab.agents.titleKey))
        case .template(let id)?:
            guard let row = template(id) else { return nil }
            return (row.title, l10n.string(SetupTab.menu.titleKey))
        case .app(let id)?:
            guard let row = app(id) else { return nil }
            return (row.name, l10n.string(SetupTab.overview.titleKey))
        case nil:
            return nil
        }
    }

    /// The header's back button: a start option goes back to its agent's page, anything else to its section's list.
    func closeDetail() {
        switch openDetailPage {
        case .variant?: openVariant(nil)
        case .agent?: openAgentOptions(nil)
        case .preset?: openPreset(nil)
        case .template?: openTemplate(nil)
        case .app?: openApp(nil)
        case nil: break
        }
    }

    /// Whether the window's close, minimize and zoom buttons stand over the end of the header. They stand at the start of the title bar, which runs
    /// the way the Mac's language does (`NSWindow.windowTitlebarLayoutDirection`); the sidebar stands at the start of the window, which runs the
    /// way the window's language does. When the two differ (Arabic on an English Mac) the buttons are on the header's side.
    nonisolated static func windowButtonsOverHeader(titlebarRightToLeft: Bool, windowRightToLeft: Bool) -> Bool {
        titlebarRightToLeft != windowRightToLeft
    }

    /// The room the end of the header leaves for the window's close, minimize and zoom buttons when they stand over it: the buttons and a gap take 84
    /// points from the window's edge, and the header has a margin of 28. A column wider than the widest header puts the header in its middle, further
    /// from the edge by half of what the column has beyond it, so that a wide window needs less room or none.
    nonisolated static func headerRoomForWindowButtons(over: Bool, columnWidth: Double, widestHeader: Double) -> Double {
        guard over else { return 0 }
        let fromEdge = pageInset(columnWidth: columnWidth, widestPage: widestHeader) + 28
        return max(0, 84 - fromEdge)
    }

    /// How far the header and the page stand from the sidebar: half of what the space beside it has beyond the widest page, so that both stand in
    /// its middle. The window places both by this one number, measured on that space: a page centred inside its scroll view stood off the header by
    /// half the scroll bar, where scroll bars are always shown, and moved when the bar came and went.
    nonisolated static func pageInset(columnWidth: Double, widestPage: Double) -> Double {
        max(0, (columnWidth - widestPage) / 2)
    }
}
