import RightHereCore

/// The setup window distinguishes a successful installation step from an extension that still needs the person.
public struct SetupStepSummary: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        case complete, skipped, failed, needsUser, warning, checking
    }

    public let state: State
    public let remark: LocalizedMessage?

    public init(_ step: SetupStep, extensionCheck: DoctorCheck?) {
        switch step.outcome {
        case .failed:
            state = .failed
            remark = .appSetupFailed
        case .skipped:
            state = .skipped
            remark = .appSetupSkipped
        case .created, .updated, .unchanged:
            if step.piece == .finderExtension {
                guard let extensionCheck, extensionCheck.id == .finderExtension else {
                    state = .checking
                    remark = .appChecking
                    return
                }
                switch extensionCheck.status {
                case .needsUser:
                    state = .needsUser
                    remark = .doctorExtensionDisabled
                    return
                case .fail:
                    state = .failed
                    remark = .appStatusProblem
                    return
                case .warn:
                    state = .warning
                    remark = .appStatusWarning
                    return
                case .ok: break
                }
            }
            state = .complete
            switch step.outcome {
            case .created: remark = step.piece == .services ? step.detail : nil
            case .updated: remark = .appSetupUpdated
            case .unchanged: remark = .appSetupUnchanged
            case .failed, .skipped: remark = nil
            }
        }
    }
}
