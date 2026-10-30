import Foundation

/// The text of a field that is changed in place, and the text it started from (ADR 0026). It is the state of `EditableText` apart from SwiftUI, so that what the field does with the config
/// that changes under it can be tested: the window cannot be driven.
///
/// `baseline` is what the config said when the field last took it, and a change is made from it. A field that was not typed in takes whatever the config says now (an Undo, something else that
/// changed the setting, the field's own change read back), and leaving it changes nothing, so a field that has the focus never writes its old text back over a newer one. A field that was typed
/// in keeps what was typed, unless the config now says that very text (a change that was held for the person's yes and was made, then undone): it takes the config's text then, so that
/// the field shows the file and leaving it does not ask again.
///
/// A change that is held for the person's yes (`held`) is the field's own until it is answered: the answer, a no or a yes that was made, reaches the field that raised the question and no
/// other (a field that was refused keeps what was typed for the person to put right, whoever else is asked something).
struct FieldDraft: Equatable {
    var draft = ""
    var baseline = ""
    /// A change of this text is being made: a second Return, or Return and then a Tab, is the same change.
    private(set) var committing = false
    /// The change of the text that was typed is waiting for the person's yes or no.
    private(set) var held = false

    /// The field is shown with the text the config says.
    mutating func appear(saved: String) {
        draft = saved
        baseline = saved
    }

    /// The config says `new` now.
    mutating func configChanged(to new: String) {
        if draft == baseline || draft == new {
            if draft == new { held = false }
            draft = new
            baseline = new
        }
    }

    /// What was typed is given up (Escape): the field shows what the config says now (`now`), and a change is made from that, not from the text the field started from.
    mutating func giveUp(now: String) {
        draft = now
        baseline = now
        held = false
    }

    /// The person answered the question that this field's change raised, with a no or with a yes that was made: the field shows what the config says now. A field whose change was not held
    /// has nothing to take from the answer.
    mutating func answered(now: String) {
        guard held else { return }
        held = false
        draft = now
        baseline = now
    }

    /// The change to make, `nil` when there is none or one is being made: the text that was typed, and the text the field was showing.
    mutating func beginCommit() -> (typed: String, shown: String)? {
        guard !committing, draft != baseline else { return nil }
        committing = true
        held = false
        return (draft, baseline)
    }

    /// The change was asked for. When it was made (`done`), the field shows what the config says now (`now`); typing that went on while it was made stays. A change that was not made is
    /// either held for the person's yes (`held`: the answer is for this field) or refused, and what was typed stays for the person to put right.
    mutating func endCommit(typed: String, done: Bool, held waiting: Bool = false, now: String) {
        committing = false
        held = waiting && !done
        guard done else { return }
        if draft == typed { draft = now }
        baseline = now
    }
}
