import RightHereCore
import RightHereKit
import SwiftUI

/// A long process error must leave the page and its recovery actions reachable.
struct NoticeBanner: View {
    let notice: SetupNotice
    let model: SetupModel
    @State private var copiedNotice: SetupNotice?
    private let l10n = Localizer.system
    private static let maximumMessageHeight: CGFloat = 132

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NoticeViewportLayout(maximumHeight: Self.maximumMessageHeight) {
                ViewThatFits(in: .vertical) {
                    message
                    ScrollViewReader { proxy in
                        SetupPage(clipPreview: true) {
                            message.id("notice-start")
                        }
                        .onChange(of: notice) { proxy.scrollTo("notice-start", anchor: .top) }
                    }
                    .frame(height: Self.maximumMessageHeight)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            // ViewThatFits' scrolling branch can omit the text from the native accessibility tree.
            .accessibilityRepresentation {
                Text(l10n.render(notice.message, isolatingValues: true))
            }

            HStack(spacing: 6) {
                if notice.isProblem {
                    Button {
                        if model.copyNotice(notice) { copiedNotice = notice }
                    } label: {
                        Image(systemName: copiedNotice == notice ? "checkmark" : "doc.on.doc")
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .help(l10n.string(copiedNotice == notice ? .appMessageCopied : .appCopyMessage))
                    .accessibilityLabel(l10n.string(copiedNotice == notice ? .appMessageCopied : .appCopyMessage))
                }

                Button { model.dismissNotice() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .help(l10n.string(.appDismissNotice))
                .accessibilityLabel(l10n.string(.appDismissNotice))
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background((notice.isProblem ? Color.orange : Color.green).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }

    private var message: some View {
        NoticeLine(notice: notice, font: .callout)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// ViewThatFits fills a proposed height even for a short message. Measure its natural height before bounding the viewport.
private struct NoticeViewportLayout: Layout {
    let maximumHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, maximumHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                             proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
