import AppKit
import SwiftUI

#if !STANDINS
/// A plain-text editor: an `NSTextView` with every automatic substitution off, undo, and no rich text. What it holds is code or the text of a file (the config, what a new file starts with), so
/// smart quotes would turn the quotes of TOML into ones it cannot read, and smart dashes would turn the `--` of a flag into a dash. `ConfigTextEditor` and the contents of a new-file template use it.
struct PlainTextView: NSViewRepresentable {
    @Binding var text: String
    let label: String
    var fontSize: CGFloat = 12
    var insets = NSSize(width: 6, height: 8)
    /// The text view lost the keyboard: what was typed is to be kept.
    var onEndEditing: (() -> Void)?
    /// Escape was pressed: what was typed is to be given up.
    var onCancel: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        guard let view = scroll.documentView as? NSTextView else { return scroll }
        view.delegate = context.coordinator
        context.coordinator.parent = self
        view.isRichText = false
        view.allowsUndo = true
        // Code and files read from the left whatever the language of the system.
        view.baseWritingDirection = .leftToRight
        view.alignment = .left
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.textContainerInset = insets
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.isAutomaticTextCompletionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.inlinePredictionType = .no
        view.mathExpressionCompletionType = .no
        view.writingToolsBehavior = .none
        view.setAccessibilityLabel(label)
        view.string = text
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView, view.string != text else { return }
        let selection = view.selectedRange()
        view.string = text
        // A text put in from outside (a revert, a file read again) is not typing: what was typed before it is undone against ranges that are not there any more, which
        // raises or garbles the text.
        view.undoManager?.removeAllActions()
        view.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private var text: Binding<String>
        var parent: PlainTextView?

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }

        func textDidEndEditing(_ notification: Notification) {
            parent?.onEndEditing?()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)), let cancel = parent?.onCancel else { return false }
            cancel()
            textView.window?.makeFirstResponder(nil)
            return true
        }
    }
}
#endif
