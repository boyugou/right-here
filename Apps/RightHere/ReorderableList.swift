import AppKit
import RightHereCore
import RightHereKit
import SwiftUI

// What the editors that arrange a list have in common (ADR 0026): the grip and the check at the left of a line, the line that shows where a dragged line would land, the drop that
// moves it, the note of the last change with its Undo, and the way to move a line with the keyboard. The Finder menu and the agents are arranged with these.

/// The height of one line of an editor whose lines are one text high.
let editorLineHeight: CGFloat = 34

/// The three bars at the left of a line that can be dragged.
struct RowGrip: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .frame(width: 18)
            .accessibilityHidden(true)
    }
}

extension RowGrip {
    /// The grip as the one place that picks the line up, for a line that has a field of text in it (`reorderable(wholeRow: false)`).
    @ViewBuilder func pickedUp(model: SetupModel, token: String, row: Int, scope: String) -> some View {
        #if PREVIEW
        self
        #else
        self.onDrag {
            model.beginDrag(row: row, token: token, scope: scope)
            return NSItemProvider(object: token as NSString)
        }
        #endif
    }
}

/// The place of a grip in a line that cannot be dragged, so that its check and its icon stand under those of the lines above.
struct RowGripSpace: View {
    var body: some View {
        Color.clear
            .frame(width: 18, height: 1)
            .accessibilityHidden(true)
    }
}

/// A check that says whether a line is in the list: unchecking takes it out, checking puts it in. The checkbox of macOS 26 is drawn by SwiftUI itself (a 16-point box
/// with no AppKit view under it), so the pictures of `preview_setup.sh` draw it as the window does, and it needs no stand-in (ADR 0029).
struct RowCheck: View {
    let isOn: Bool
    let label: String
    let toggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })) { EmptyView() }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(label)
            .accessibilityLabel(label)
            .frame(width: 18)
    }
}

/// An app's, an agent's or a file type's icon, as the Finder menu draws it.
struct RowIcon: View {
    let image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .scaledToFit()
                .foregroundStyle(.primary)
        } else {
            // A line without an icon (an app that is not installed) keeps the room of one, so that its name stands where the others do.
            Color.clear
        }
    }
}

/// The line that shows where a dragged row would land.
struct DropLine: View {
    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }
}

// MARK: Dragging

/// A drop on a row: its upper half is a place before the row, its lower half a place after it. Only a drop that carries what the window put in its own drag moves anything: a drag
/// that was cancelled, and text dropped from another app, do not (`SetupModel.endDrag`).
struct RowDrop: DropDelegate {
    let model: SetupModel
    /// The list this row is in: only a row that was picked up in the same list is moved by a drop on it.
    let scope: String
    let index: Int
    let height: CGFloat
    @Binding var dropTarget: Int?
    /// The row picked up (from 1) goes before this place (from 0, in the list as it is).
    let move: @MainActor (Int, Int) async -> Void

    private func place(_ info: DropInfo) -> Int { info.location.y < height / 2 ? index : index + 1 }

    private var carriesARowOfThisList: Bool { model.drag?.scope == scope }

    func validateDrop(info: DropInfo) -> Bool { carriesARowOfThisList && info.hasItemsConforming(to: [.plainText]) }

    func dropEntered(info: DropInfo) { dropTarget = carriesARowOfThisList ? place(info) : nil }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard carriesARowOfThisList else {
            dropTarget = nil
            return DropProposal(operation: .forbidden)
        }
        dropTarget = place(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { dropTarget = nil }

    func performDrop(info: DropInfo) -> Bool {
        let destination = place(info)
        dropTarget = nil
        guard carriesARowOfThisList, let provider = info.itemProviders(for: [.plainText]).first else { return false }
        let model = self.model
        let move = self.move
        let scope = self.scope
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            let token = (object as? NSString).map { $0 as String }
            Task { @MainActor in
                guard let row = model.endDrag(token: token, scope: scope) else { return }
                await move(row, destination)
            }
        }
        return true
    }
}

extension View {
    /// The line can be picked up and dropped on a line, and moved up and down with the keyboard (Option and the arrow keys). `ImageRenderer`, which draws the window for
    /// `script/preview_setup.sh`, shows a drag source as a "not allowed" sign, so the picture is made without it.
    /// - Parameters:
    ///   - token: What the drag carries; it names the row, and no other text is a row.
    ///   - scope: The list the row is in: a drop moves a row only in the list that it was picked up in.
    ///   - row: The place of the row in its list, from 1.
    ///   - index: The place of the row among those shown, from 0.
    ///   - enabled: Whether the row can be dragged to and from at all; it cannot while the list is being written, or when the list is not what the window shows.
    ///   - wholeRow: Whether the row is picked up anywhere and moved with the arrow keys. A row with a field of text in it is picked up by its grip alone (`RowGrip.pickedUp`): a drag
    ///     inside the field selects text, and the arrow keys are the field's.
    ///   - move: What a drop does: the row (from 1) goes before the place (from 0, in the list as it is).
    ///   - moveBy: What the keyboard does: this row one place up (`-1`) or down (`1`).
    func reorderable(model: SetupModel, token: String, scope: String, row: Int, index: Int, height: CGFloat, dropTarget: Binding<Int?>, enabled: Bool = true, wholeRow: Bool = true,
                     move: @escaping @MainActor (Int, Int) async -> Void, moveBy: @escaping @MainActor (Int) async -> Void) -> some View {
        #if PREVIEW
        self
        #else
        Group {
            if !enabled {
                self
            } else if wholeRow {
                self
                    .onDrag {
                        model.beginDrag(row: row, token: token, scope: scope)
                        return NSItemProvider(object: token as NSString)
                    }
                    .focusable()
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        guard press.modifiers.contains(.option) else { return .ignored }
                        let offset = press.key == .upArrow ? -1 : 1
                        Task { await moveBy(offset) }
                        return .handled
                    }
            } else {
                self
            }
        }
        .onDrop(of: enabled ? [.plainText] : [], delegate: RowDrop(model: model, scope: scope, index: index, height: height, dropTarget: dropTarget, move: move))
        #endif
    }
}

// MARK: What the last change was

/// The note of the last change made on this page, with the button that takes it back; and the reason when a change was refused. The change is the one the button takes back, and no
/// other (`ConfigEdit.digest`).
struct ConfigEditBanner: View {
    let model: SetupModel
    let tab: SetupTab
    /// Which changes the note is for, by the setting that decided them: a page with two editors says each change under the editor it was made in.
    var concerning: (String) -> Bool = { _ in true }
    @Environment(\.localizer) private var l10n

    private var edit: ConfigEdit? {
        model.configEdit.flatMap { $0.tab == tab && concerning($0.key) ? $0 : nil }
    }

    private var refusal: EditRefusal? {
        model.editRefusal.flatMap { $0.tab == tab && concerning($0.key) ? $0 : nil }
    }

    var body: some View {
        // Nothing at all when there is nothing to say: an empty stack would still take its place in the page's spacing (ADR 0029, 13).
        if edit != nil || refusal != nil {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let edit {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                    Text(l10n.render(edit.message, isolatingValues: true))
                        .font(.callout)
                    Spacer(minLength: 8)
                    Button(l10n.string(.appMenuUndo)) { Task { await model.undoEdit() } }
                        .disabled(model.isWorking)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .panel()
                .accessibilityElement(children: .combine)
                // What the change left wrong, which the person did not ask for: an item of the menu that names what was taken out.
                ForEach(Array(edit.warnings.prefix(3).enumerated()), id: \.offset) { _, warning in
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                            .accessibilityHidden(true)
                        Text(verbatim: warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let refusal {
                NoticeLine(notice: refusal.notice, font: .callout)
            }
        }
    }
}
