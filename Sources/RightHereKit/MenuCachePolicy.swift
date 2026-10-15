import Foundation

/// When the Finder extension may hand out a menu it built earlier instead of building one again.
///
/// A menu depends on the config (its files' stamp), and on what is installed on this Mac, which the extension's facts remember for a few
/// minutes. A menu kept for as long as the config does not change would go on offering an app that was uninstalled, or leave out one that
/// was just installed, for as long as the extension lives, which is until Finder restarts. So it is also kept only briefly.
public enum MenuCachePolicy {
    /// Shorter than the lifetime of what the facts remember, so a rebuilt menu always sees fresh facts within that time.
    public static let lifetime: TimeInterval = 60

    public static func canServe(builtAt: Date, now: Date, sameConfig: Bool) -> Bool {
        sameConfig && now >= builtAt && now.timeIntervalSince(builtAt) < lifetime
    }
}
