import Foundation
import Testing
@testable import RightHereCore

@Suite("Command line check before ArgumentParser reads it")
struct InvocationCheckTests {
    /// `rh config set <key> -- <values> --dry-run`, as the usage line puts the options after the values: the dry run was a value, and the file was written (an independent review of
    /// `rh config`, 2026-11-13). An option of the command after `--` is refused with the command that gives it before, unless it stands before `--` as well.
    @Test func anOptionOfConfigSetOrAddAfterTheTerminatorIsRefusedWithTheCommandThatGivesItBefore() {
        let commands = ["config", "run", "menu"]
        #expect(InvocationCheck.problem(["config", "set", "agent.claude.args", "--", "--model", "opus", "--dry-run"], commands: commands)
                == "--dry-run after -- would be written as a value of the setting, not read as the option: give the options before -- (`rh config set agent.claude.args --dry-run -- --model opus`). A value that is one of these options is written in the file itself (`rh config path` names it).")
        #expect(InvocationCheck.problem(["config", "add", "menu.items", "--", "-", "--at", "2", "--local"], commands: commands)?.contains("`rh config add menu.items --at 2 --local -- -`") == true)
        #expect(InvocationCheck.problem(["config", "set", "--json", "agent.x.args", "--", "--json"], commands: commands) == nil, "given before -- too: the one after is a value")
        #expect(InvocationCheck.problem(["config", "set", "agent.claude.args", "--", "--model", "opus"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["config", "remove", "menu.items", "--", "--dry-run"], commands: commands) == nil, "remove takes one item: another word is a usage error")
    }

    private let commands = ["run", "actions", "menu", "docs", "config", "doctor", "install", "mcp"]

    @Test("an argument that starts with a dash, and is not an option of the command, is refused", arguments: [
        ["run", "copy-path.absolute", "-dash.txt"], ["run", "copy-path.absolute", "-y"], ["run", "--dry-run", "-foo.txt"],
        ["menu", "-x"], ["run", "copy-path.absolute", "-hx"]
    ])
    func aDashArgumentIsRefused(arguments: [String]) throws {
        let problem = try #require(InvocationCheck.problem(arguments, commands: commands))
        #expect(problem.hasPrefix("arguments that start with - need -- before them"), Comment(rawValue: problem))
        #expect(problem.contains("rh \(arguments[0]) … -- \(arguments.last ?? "")"), Comment(rawValue: problem))
    }

    @Test("what follows -- is never an option, and nor is a value that starts with a dash", arguments: [
        ["run", "copy-path.absolute", "--", "-dash.txt"], ["run", "agent.claude", "--arg", "--verbose"], ["run", "agent.claude", "--arg=-x"],
        ["run", "--container", "-weird", "copy-path.name"], ["menu", "--language", "-x"], ["run", "-"], ["run", "--dry-run", "--json", "x"]
    ])
    func aDashAfterDoubleDashOrAsAValueIsAllowed(arguments: [String]) {
        #expect(InvocationCheck.problem(arguments, commands: commands) == nil, Comment(rawValue: "\(arguments)"))
    }

    @Test("the options that are known are allowed, and -h asks for help as it always did")
    func knownOptionsPass() {
        #expect(InvocationCheck.problem(["run", "-h"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["run", "--help"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["run", "copy-path.absolute", "--alert", "--worktree", "--safe", "--json", "--dry-run", "a"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["menu", "--explain", "--json", "--origin", "items", "--container", "/tmp"], commands: commands) == nil)
    }

    @Test("a command that is not one is refused, with the closest one named", arguments: [
        (["runn", "copy-path.absolute"], "Did you mean \"run\"?"), (["doctr"], "Did you mean \"doctor\"?"), (["--help", "nosuch"], nil as String?)
    ])
    func aMisspeltCommandIsRefused(arguments: [String], suggestion: String?) throws {
        if arguments.first == "--help" { #expect(InvocationCheck.problem(arguments, commands: commands) == nil); return }
        let problem = try #require(InvocationCheck.problem(arguments, commands: commands))
        #expect(problem.hasPrefix("unknown command \"\(arguments[0])\"."))
        #expect(problem.contains(suggestion ?? "Run `rh --help` to list the commands."), Comment(rawValue: problem))
    }

    @Test("a misspelt command is refused even with --help, which used to print the root help with status 0")
    func aMisspeltCommandWithHelpIsRefused() throws {
        let problem = try #require(InvocationCheck.problem(["nosuchcmd", "--help"], commands: commands))
        #expect(problem.hasPrefix("unknown command \"nosuchcmd\"."))
    }

    @Test("help, the root's options, no command at all and every other command pass")
    func theRestPasses() {
        #expect(InvocationCheck.problem([], commands: commands) == nil)
        #expect(InvocationCheck.problem(["--version"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["-h"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["help", "run"], commands: commands) == nil)
        #expect(InvocationCheck.problem(["config", "-x", "validate"], commands: commands) == nil, "other commands are ArgumentParser's to read")
    }
}
