import AppKit
import SwiftUI

// The fields of text of the pages of settings (ADR 0026). A line that is changed in place makes its change when Return is pressed or the field is left, and gives it up on Escape; a form
// reads its fields when its button is pressed.

private struct FieldAnswerKey: EnvironmentKey {
    static let defaultValue = 0
}

private struct HeldChangeKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Bool = { false }
}

extension EnvironmentValues {
    /// Changes when the person answers the question of a change that was held for their yes, with a no or with a yes that was made (`SetupModel.fieldAnswerToken`): the field that raised the
    /// question takes its text from the config (`FieldDraft.answered`).
    var fieldAnswerToken: Int {
        get { self[FieldAnswerKey.self] }
        set { self[FieldAnswerKey.self] = newValue }
    }

    /// Whether a question about a change is up, which a field asks right after its change was not made: it is held for the yes, and not refused.
    var changeIsHeld: @MainActor () -> Bool {
        get { self[HeldChangeKey.self] }
        set { self[HeldChangeKey.self] = newValue }
    }
}

/// The way a field of text looks, and what stands for one in the preview, which draws nothing for a control that AppKit draws.
struct FieldLook: View {
    let text: String
    let prompt: String
    var monospaced = false
    /// How many lines it may show: a prompt of a preset wraps.
    var lines = 1

    var body: some View {
        Text(verbatim: text.isEmpty ? prompt : text)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
            .foregroundStyle(text.isEmpty ? .tertiary : .primary)
            .lineLimit(lines)
            .fixedSize(horizontal: false, vertical: lines > 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
    }
}

/// A line of text that is changed in place.
///
/// What it shows is what the config says (`current`). The text it started from (`baseline`) is the one a change is made from: a field that was not typed in takes whatever the config
/// says now (an Undo, something else that changed the setting), and leaving it changes nothing, so a field that has the focus never writes its old text back over a newer one. A field
/// that was typed in keeps what was typed, and says which text that was based on, so that a list that moved meanwhile does not take it for another item.
struct EditableText: View {
    /// What VoiceOver calls the field.
    let label: String
    let prompt: String
    var monospaced = false
    /// A text that wraps over several lines (the prompt of a preset) instead of scrolling in one.
    var wraps = false
    /// A block of text with line breaks of its own (what a new file holds): Return is a line break, and the change is made when the field is left.
    var block = false
    let current: () -> String
    /// Makes the change: what was typed, and the text the field was showing. `true` when it was made, or there was nothing to make; `false` when it was refused or held, and what was
    /// typed stays for the person to put right.
    let commit: (_ typed: String, _ shown: String) async -> Bool
    /// Makes the change of a block that has rested while it is still being typed in, which is not told to VoiceOver; `nil` makes it as `commit` does.
    var restCommit: ((_ typed: String, _ shown: String) async -> Bool)?

    @Environment(\.fieldAnswerToken) private var answerToken
    @Environment(\.changeIsHeld) private var changeIsHeld
    @State private var field = FieldDraft()
    /// A block of text is written when it has rested for a moment: it is left by clicking another field, and not by Return, so a person who types and then goes to another page would
    /// otherwise lose it.
    @State private var resting: Task<Void, Never>?
    @FocusState private var focused: Bool

    var body: some View {
        let saved = current()
        #if STANDINS
        FieldLook(text: saved, prompt: prompt, monospaced: monospaced, lines: block ? 6 : (wraps ? 4 : 1))
        #else
        input
            .focused($focused)
            .onAppear { field.appear(saved: saved) }
            .onChange(of: saved) { _, new in field.configChanged(to: new) }
            .onSubmit { Task { await finish() } }
            .onChange(of: focused) { _, isFocused in if !isFocused { Task { await finish() } } }
            .onChange(of: field.draft) { _, _ in if block { rest() } }
            .onChange(of: answerToken) { _, _ in field.answered(now: current()) }
            .onExitCommand {
                field.giveUp(now: current())
                focused = false
            }
            .onDisappear {
                // Typing that the page was left with is made on its way out: the change names the entry it was typed for, and is refused for another one. The focus that the field loses on its way
                // out is not a second commit of the same text. A block whose rest is already writing it is left to finish: cancelling it would stop it waiting for a window that is busy, and say
                // nothing, and the change that this asks for is not made while that one runs.
                if !field.committing { resting?.cancel() }
                guard let (typed, shown) = field.beginCommit() else { return }
                Task {
                    _ = await commit(typed, shown)
                    field.endCommit(typed: typed, done: false, now: "")
                }
            }
        #endif
    }

    #if !STANDINS
    @ViewBuilder private var input: some View {
        if block {
            PlainTextView(text: $field.draft, label: label, fontSize: 13, insets: NSSize(width: 4, height: 6),
                          onEndEditing: { Task { await finish() } }, onCancel: { field.giveUp(now: current()) })
                .frame(minHeight: 96, maxHeight: 220)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
        } else {
            TextField(label, text: $field.draft, prompt: Text(prompt).font(.body), axis: wraps ? .vertical : .horizontal)
                .lineLimit(wraps ? 2...6 : 1...1)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
        }
    }
    #endif

    /// Writes a block of text when it has been left alone for a while: each such write is a change of its own that the history keeps, so it waits for a real pause, and it is not announced.
    private func rest() {
        resting?.cancel()
        resting = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            await finish(resting: true)
        }
    }

    private func finish(resting rested: Bool = false) async {
        // A second Return, or Return and then a Tab, while the change is being written is the same change.
        guard let (typed, shown) = field.beginCommit() else { return }
        let done = await (rested ? (restCommit ?? commit) : commit)(typed, shown)
        // Typing that went on while the change was written stays. A change that was not made and has a question up is waiting for the yes, and the answer is for this field.
        field.endCommit(typed: typed, done: done, held: !done && changeIsHeld(), now: current())
    }
}

/// A field of a form: its text is the person's until the form's button reads it.
struct DraftField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var monospaced = false
    var wraps = false

    var body: some View {
        #if STANDINS
        FieldLook(text: text, prompt: prompt, monospaced: monospaced, lines: wraps ? 4 : 1)
        #else
        TextField(label, text: $text, prompt: Text(prompt).font(.body), axis: wraps ? .vertical : .horizontal)
            .lineLimit(wraps ? 2...6 : 1...1)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
        #endif
    }
}

/// A button that is an image, a few words or a whole row, and has no frame of its own. SwiftUI draws all of it, so `script/preview_setup.sh` draws it as the window does.
struct PlainButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        // Not `.borderless`: that is an AppKit button, and in a window that was never put on screen it drew the words of a whole row (an app, a preset) grey, as a
        // disabled one, also when the window and the app said they were key and active (ADR 0029, 11). A plain button draws its label as it is; its whole frame is clicked.
        Button(action: action) {
            label()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The button that does what a page is for (Save, Apply, Set Up): blue while it can be pressed, and the grey capsule of the buttons beside it while it cannot,
/// as macOS draws a default button that is off. `.borderedProminent` drew it off as a faded blue, which looked pressable and like a web page (a design review
/// of 0.3.21), and the look of an off default button cannot be measured in a window off screen, which draws every default button as in the background.
struct DefaultButton: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered).disabled(true)
        }
    }
}

/// The line between two rows of a group, from where the rows' text starts to where it ends (14 points in from each side), as `LinedRows` and the grouped settings
/// of macOS 26 draw it; a line from edge to edge was the look of a few groups only.
struct RowDivider: View {
    var body: some View {
        GroupLine()
            .padding(.horizontal, 14)
    }
}

/// The line between two rows of a group, in the colour of the grouped settings of macOS 26: the text colour at about 5 percent over the group, #EBEBEB on
/// #F7F7F7 in light and #2D2D2D on #232323 in dark (ADR 0029, "What was measured"). `Divider` draws the separator colour, twice as dark there, which made
/// every group read as a ruled table. With Increase Contrast it is the separator's own strength again.
struct GroupLine: View {
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(contrast == .increased ? 0.2 : 0.055))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// A line of a panel of settings, as the grouped settings of macOS 26 draw one: the setting's name at the leading edge and what sets it at the
/// trailing edge, or, for a block of text, the name over it. What the setting does stands under both: a help text below the whole panel was
/// read as belonging to another row.
struct OptionRow<Control: View>: View {
    let label: String
    var help: String? = nil
    /// A block of text (a template's contents, a preset's prompt) takes the row's whole width, under its name.
    var stacked = false
    @ViewBuilder let control: () -> Control

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if stacked {
                Text(verbatim: label)
                    .font(.body)
                control()
            } else {
                HStack(alignment: .center, spacing: 16) {
                    Text(verbatim: label)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // The control takes its width first, and the name wraps: a field cut its placeholder in German at the smallest window.
                    control()
                        .frame(maxWidth: 260, alignment: .trailing)
                        .layoutPriority(1)
                }
            }
            if let help {
                Text(verbatim: help)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // The whole width of the group, so that a row of a block of text starts where the others do.
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
        .accessibilityElement(children: .contain)
    }
}
