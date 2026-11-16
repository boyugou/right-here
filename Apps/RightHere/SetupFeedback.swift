import RightHereCore
import RightHereKit
import SwiftUI

/// A compact notice never pushes navigation out of the window. Opening it keeps the complete, selectable message and its actions together.
struct SidebarNotice: View {
    let model: SetupModel
    let notice: SetupNotice
    @State private var showingDetails = false
    @State private var copied: SetupNotice?
    @Environment(\.localizer) private var l10n

    var body: some View {
        Button { showingDetails.toggle() } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: notice.isProblem ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(notice.isProblem ? Color.orange : Color.green)
                    .accessibilityHidden(true)
                Text(notice.text(in: l10n))
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.forward")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(notice.text(in: l10n))
        .help(notice.text(in: l10n))
        .onChange(of: notice) { showingDetails = false }
        .popover(isPresented: $showingDetails) {
            VStack(alignment: .leading, spacing: 12) {
                MessageViewportLayout(maximumHeight: 200) {
                    ViewThatFits(in: .vertical) {
                        message
                        ScrollView { message }
                            .frame(height: 200)
                    }
                }
                .accessibilityRepresentation { Text(notice.text(in: l10n)) }
                HStack {
                    Button {
                        if model.copyNotice(notice) { copied = notice }
                    } label: {
                        Label(l10n.string(copied == notice ? .appMessageCopied : .appCopyMessage), systemImage: copied == notice ? "checkmark" : "doc.on.doc")
                    }
                    Spacer(minLength: 8)
                    Button(l10n.string(.appDismissNotice)) { model.dismissNotice(notice) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(14)
            .frame(width: 380)
            .environment(\.localizer, l10n)
            .environment(\.layoutDirection, l10n.isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }

    private var message: some View {
        NoticeLine(notice: notice, font: .callout)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ViewThatFits fills a proposed height even for a short message. Measure its natural height before bounding the viewport.
struct MessageViewportLayout: Layout {
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, maximumHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
