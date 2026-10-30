import Foundation

/// Warp: a new window or tab in the folder through the URI scheme its documentation gives (docs.warp.dev, "URI Scheme"):
/// `warp://action/new_window?path=<folder>` and `warp://action/new_tab?path=<folder>` (`warppreview://` for Warp Preview), handed to
/// the installed Warp with `open -b`. The same page says the scheme cannot run a command, so an agent is refused. It does not say how
/// Warp reads `path`, so the folder is held to the rule for typed text (no control character) and every byte outside the unreserved
/// characters and `/` is percent-encoded: an `&` or `#` in a folder name stays part of the folder and cannot add to the request. It has not
/// yet been tried with a real Warp; `docs/development/MANUAL_CHECKS.md` lists what to look at.
/// Before this adapter Warp was handed the folder with `open`, which nothing documents.
public struct WarpAdapter: TerminalAdapter {
    public let terminalID = "warp"
    public var commandRefusal: String? { "Warp cannot run commands yet. Choose another terminal for this agent." }
    public var supportedPlacements: [TerminalPlacement] { [.newWindow, .newTab] }

    public init() {}

    public func steps(for session: TerminalSession, bundleID: String, facts: any SystemFacts) throws -> [Step] {
        if session.typedInput != nil, let refusal = commandRefusal { throw PlanError.unsupported(refusal) }
        let directory = try session.requireDirectory(facts)
        do { try ShellQuoting.validateForTyping(directory) } catch { throw PlanError.unsafeFolder(directory) }
        let action = session.placement == .newTab ? "new_tab" : "new_window"
        guard let path = Self.queryValue(directory) else { throw PlanError.unsupported("The folder \(directory.jsonQuoted) cannot be written into a link for Warp.") }
        return [.open(OpenStep(bundleID: bundleID, targets: ["\(Self.scheme(bundleID: bundleID))://action/\(action)?path=" + path]))]
    }

    /// The page gives `warppreview://` for Warp Preview, whose bundle identifier is the one its Homebrew cask names (`warp@preview`).
    static func scheme(bundleID: String) -> String {
        bundleID == "dev.warp.Warp-Preview" ? "warppreview" : "warp"
    }

    /// RFC 3986's unreserved characters and `/`, spelled out: `CharacterSet.alphanumerics` also holds letters outside ASCII, and
    /// `URLComponents` leaves `+`, which a query reader may take for a space, as it is.
    private static let kept = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")

    /// The path as the value of a query parameter: each UTF-8 byte of anything else becomes `%XX`.
    static func queryValue(_ path: String) -> String? {
        path.addingPercentEncoding(withAllowedCharacters: kept)
    }
}
