import Foundation
import RightHereCore

/// How a person changes each setting of the config in the window (ADR 0026, D3). An agent can change every setting with `rh config` and the MCP tool; a person can change all of them as text on
/// the Config page, and the settings below also have a control of their own. A test fails for a setting of the schema that is not listed here, so a setting cannot be added without deciding how the
/// window changes it.
public enum ConfigParity {
    public enum Editor: Equatable, Sendable {
        /// A control in a section of the window.
        case control(SetupTab, String)
        /// As text on the Config page for now, with why there is no control yet.
        case text(String)
    }

    public static let editors: [String: Editor] = {
        var editors: [String: Editor] = [
            "general.terminal": .control(.overview, "the menu of the default terminal"),
            "general.editor": .control(.overview, "the menu of the default editor"),
            "general.terminal_placement": .control(.overview, "where a session opens, for a terminal that has tabs and splits"),
            "general.language": .control(.overview, "the menu of the language"),
            "general.bypass_permissions": .control(.agents, "the switch that starts agents without asking"),
            "general.agents": .control(.agents, "the checks and the order of the agents"),
            "agent.*.name": .control(.agents, "the name field of an agent of one's own"),
            "agent.*.command": .control(.agents, "the command field of an agent's page"),
            "agent.*.launcher": .control(.agents, "the menu of how an agent starts"),
            "agent.*.terminal": .control(.agents, "the menu of the terminal an agent starts in"),
            "agent.*.args": .control(.agents, "the list of an agent's arguments"),
            "agent.*.bypass_permissions": .control(.agents, "the menu of whether an agent starts without asking"),
            "agent.*.bypass_permission_arg": .control(.agents, "the field of the flag that skips an agent's permission prompts"),
            "agent.*.prompt_arg": .control(.agents, "the field of how an agent's command takes a first prompt"),
            "agent.*.variant.*.id": .control(.agents, "made from the title of a new start option"),
            "agent.*.variant.*.title": .control(.agents, "the title field of a start option's page"),
            "agent.*.variant.*.arguments": .control(.agents, "the list of a start option's arguments"),
            "preset.*.id": .control(.agents, "made from the title of a new preset"),
            "preset.*.title": .control(.agents, "the title field of a preset's page"),
            "preset.*.prompt": .control(.agents, "the prompt field of a preset's page"),
            "preset.*.agent": .control(.agents, "the menu of the agent that runs a preset"),
            "preset.*.max_files": .control(.agents, "the menu of how many files a preset takes"),
            "new_file.then": .control(.menu, "the menu of what happens after a file is made"),
            "new_file.hidden": .control(.menu, "the check of a template's line"),
            "new_file.template.*.format": .text("written by Customize Templates for the Office templates; a template of one's own is a text"),
            "new_file.template.*.id": .control(.menu, "made from the title of a new template"),
            "new_file.template.*.title": .control(.menu, "the title field of a template's page"),
            "new_file.template.*.base_name": .control(.menu, "the file name field of a template's page"),
            "new_file.template.*.extension": .control(.menu, "the extension field of a template's page"),
            "new_file.template.*.contents": .control(.menu, "the contents field of a template's page"),
            "new_file.template.*.open_with": .control(.menu, "the menu of the app that opens a new file"),
            "menu.items": .control(.menu, "Edit Menu: the rows, their order and what can be added"),
            "copy_path.title": .control(.menu, "the title field of the Copy Path panel"),
            "copy_path.styles": .control(.menu, "the checks and the order of the forms of Copy Path"),
            "services.items": .control(.menu, "the list of Quick Actions and its Add menu"),
            "app.*.id": .control(.overview, "made from the name of a new app"),
            "app.*.name": .control(.overview, "the name field of an app's page"),
            "app.*.bundle_id": .control(.overview, "read from the application that is chosen with Add App"),
            "app.*.role": .control(.overview, "the menu of what an app is used as"),
            "version": .text("the number of the config format, which a person never changes"),
            "disabled": .text("what this Mac turns off, in its own file: an editor of the person's own file is a later step")
        ]
        func text(_ keys: [String], _ why: String) { for key in keys { editors[key] = .text(why) } }
        text(["app.*.bundle_ids", "app.*.open_args", "app.*.run_args"], "several bundle identifiers, and the templates that start a terminal, are text: the page of an app says so")
        return editors
    }()

    /// The settings that can only be changed as text on the Config page yet, in order.
    public static var textOnly: [String] {
        editors.filter { if case .text = $0.value { true } else { false } }.keys.sorted()
    }
}
