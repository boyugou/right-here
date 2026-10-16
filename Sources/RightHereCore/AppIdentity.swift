import Foundation

/// The names everything else derives from. Changing the product name or its identifiers starts here.
public enum AppIdentity {
    public static let productName = "Right Here"
    /// The released version: `rh --version`, the MCP server, the app. `project.yml` (MARKETING_VERSION) and the top entry of CHANGELOG.md say the
    /// same; `script/verify_version.py` checks it.
    public static let version = "0.3.2"
    public static let cliName = "rh"
    public static let configDirectoryName = "right-here"

    public static let bundleIDPrefix = "com.boyugou.righthere"
    public static let hostBundleID = bundleIDPrefix
    public static let extensionBundleID = bundleIDPrefix + ".FinderExtension"

    public static let extensionBundleName = "FinderExtension.appex"
    /// The script the Finder extension runs outside its sandbox; it hands over to `rh run`.
    public static let runnerScriptName = "rh-run"
}
