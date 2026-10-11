import Foundation

/// The names everything else derives from. Changing the product name or its identifiers starts here.
public enum AppIdentity {
    public static let productName = "Right Here"
    public static let cliName = "rh"
    public static let configDirectoryName = "right-here"
    public static let environmentPrefix = "RH_"

    public static let bundleIDPrefix = "com.boyugou.righthere"
    public static let hostBundleID = bundleIDPrefix
    public static let extensionBundleID = bundleIDPrefix + ".FinderExtension"

    public static let hostBundleName = "Right Here.app"
    public static let extensionBundleName = "FinderExtension.appex"
    /// The script the Finder extension runs outside its sandbox; it hands over to `rh run`.
    public static let runnerScriptName = "rh-run"
}
