# Writing for people

This guide is for the text that people read: the README, the website, the user guides, the app's window and the
messages of `rh`. It is a relaxed form of ASD-STE100 (Simplified Technical English), a controlled language for
maintenance manuals. We keep its rules for sentences. We do not use its fixed dictionary.

`uv run script/writing_report.py` measures the README, the user guides and the website. Run it before and after you
change them.

## Rules

1. **One topic in each sentence.** A step has 20 words or fewer. A description has 25 words or fewer.
2. **Write steps as commands.** Use one action in each step. Number the steps.
   - Good: "Open the app. Press **Set Up**."
   - Bad: "Opening the app and pressing Set Up, which asks you some questions, sets everything up."
3. **Use the active voice.** Say who does the action.
   - Good: "Right Here makes the config file."
   - Bad: "The config file is made."
4. **Use the present tense.** "The window shows the result", not "the window will show the result".
5. **Do not join clauses with "which", "where", ";" or ":".** Write two sentences, or a list.
6. **Put a condition first.** "If the menu does not show, use Quick Actions."
7. **Put the result after the action.** "Press **Set Up**. The window shows what it did."
8. **Use lists and tables.** Use a list for three or more items. Use a table for options and their meanings.
9. **Keep paragraphs short.** Three sentences or fewer.
10. **Show a flow as a diagram.** A flow with more than three steps is easier to read as a diagram than as text.
11. **Do not use filler words.** For example: "simply", "just", "easily", "etc.", "in order to".
12. **Use the same word for the same thing.** Use the words of the glossary below. Do not use synonyms.

## Words that do not change

- **Apple's words.** Settings paths, "Open With" and "Show in Finder" stay as macOS writes them.
  `script/verify_macos_wording.py` checks them.
- **Names in code format.** Commands, settings, files and ids stay exact: `rh setup`, `general.terminal`,
  `config.local.toml`, `agent.claude`.

## Glossary

| Use | For | Do not use |
| --- | --- | --- |
| Finder menu | the menu that Right Here adds when you right-click in Finder | context menu, right-click menu |
| Quick Actions | the actions that macOS lists under Quick Actions and Services | services, workflows |
| action | one thing that Right Here can do, such as `agent.claude` (`rh actions` lists them) | command, operation |
| agent | a command-line AI coding agent: Claude Code, Codex, Gemini CLI and others | bot, AI tool |
| AI assistant | an app that uses Right Here through MCP: Claude Desktop, Cursor, Zed and others | agent (when MCP is meant) |
| preset | a prompt that starts an agent on the selected files | template (for prompts) |
| start option | another way to start one agent, such as "Use Opus" | variant (in text for people) |
| template | a kind of new file that **New File** makes | — |
| config file | `~/.config/right-here/config.toml`, which can be synced | settings file, preferences |
| this Mac's own file | `config.local.toml`, which is never synced | local config, overlay |
| setup window | the window of the Right Here app | preferences window, settings app |
| Finder extension | the part of Right Here that adds the Finder menu | plugin, add-on |
| `rh` | the command-line tool | CLI (in sentences for people) |
| permission prompts | the questions that an agent asks before it acts | approvals, confirmations |

## Before and after

Before:

> Right Here is a macOS action layer: a sandboxed Finder Sync extension, a command-line tool (`rh`), a plain-text
> configuration file and a Model Context Protocol (MCP) server, so that developers use contextual right-clicks in
> Finder while AI assistants use the exact same actions from the terminal or over MCP.

After:

> Right Here adds actions to Finder. Right-click a folder to open it in your terminal, your editor or an AI agent.
> The same actions run from the `rh` command and from AI assistants.
