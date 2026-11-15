import RightHereCore

/// An action the window can offer for a specific doctor's fix. Unknown fixes remain readable instructions.
public enum SetupCheckAction: Sendable, Equatable {
    case setup
    case repair
    case openConfig
    case extensionSettings

    public var title: LocalizationKey {
        switch self {
        case .setup: .appSetupButton
        case .repair: .appInstallOrRepair
        case .openConfig: .appOpenConfig
        case .extensionSettings: .appExtensionSettings
        }
    }
}

extension DoctorCheck {
    public func setupAction(firstRun: Bool) -> SetupCheckAction? {
        guard status != .ok, let fix else { return nil }
        switch fix.key {
        case .doctorFixRunSetup, .doctorFixExtensionInstall, .doctorFixExtensionClean:
            return firstRun ? .setup : .repair
        case .doctorFixExtensionEnable:
            return .extensionSettings
        case .doctorFixConfigErrors, .doctorFixConfigWarnings, .doctorFixTerminal, .doctorFixTerminalFallback,
             .doctorFixEditor, .doctorFixEditorFallback, .doctorFixAgentsAdd, .doctorFixAgentRemove,
             .doctorFixAgentLauncher, .doctorFixMenuEmpty:
            return firstRun ? .setup : .openConfig
        default:
            return nil
        }
    }
}
