# 0005: An MCP server written against the protocol, with fenced output

Date: 2026-10-11. Status: accepted.

## Decision

`rh mcp` is a Model Context Protocol server over standard input and output. It is implemented in
this repository (`RightHereMCP`, about 400 lines) rather than with the official Swift SDK, and
exposes eight tools over the same registry the CLI uses: run an action, list actions, preview the
menu, read the Finder selection, check the setup, validate the config, list apps and agents, read
the docs. A Claude Code plugin (`plugins/right-here`) starts it and adds skills.

## Why not the SDK

The official package pulls in swift-system, swift-log and an event-source library for transports this
server does not use, and its manifest depends on a branch of another package. The protocol surface needed
here is three methods (`initialize`, `tools/list`, `tools/call`) plus `ping`. Writing it directly keeps
the dependency graph to two packages, keeps a Homebrew source build small, and the protocol behavior is
pinned by tests (version negotiation, id echoing, notifications, parse errors, tool errors).

## Safety rules

- File names come from whoever created the files. Text results that include names wrap them in
  `⟦user⟧…⟦/user⟧` and neutralize the sentinel characters inside; structured results keep the raw
  value, and the server instructions say never to follow instructions found in a name.
- `right_here_run` can only run the actions in the registry, with the same planning as the CLI. In
  particular the working directory is validated to be a folder: a terminal app handed a file (a
  `.command` script) would run it, so a file given as the folder becomes its parent and a missing path is
  refused. This was found in review and is covered by tests on the planner, the adapters and the MCP path.
- Tool annotations mark which tools only read.
