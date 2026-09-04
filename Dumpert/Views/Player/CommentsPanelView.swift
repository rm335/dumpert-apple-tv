import SwiftUI

/// Read-only comment thread panel, shown over the right side of the player.
/// Rows are focusable so the Siri Remote can scroll the thread; a Menu press
/// lands in `.onExitCommand` (focus is inside the panel) and closes it.
struct CommentsPanelView: View {
    let comments: [DumpertComment]
    let totalCount: Int
    let isLoading: Bool
    let loadFailed: Bool
    let onClose: () -> Void

    @FocusState private var focusedCommentID: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Focus anchor for the loading/empty/failed states, so Menu still routes
    /// to onExitCommand before any comment row exists. API comment ids are
    /// positive, so -1 can never collide.
    private static let placeholderFocusID = -1

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            panel
        }
        .ignoresSafeArea()
        .onExitCommand { onClose() }
        .onAppear {
            focusedCommentID = comments.first?.id ?? Self.placeholderFocusID
        }
        .onChange(of: comments.first?.id) { _, newFirst in
            // The on-demand fetch resolves after the panel opened: move focus
            // from the placeholder onto the first real row.
            if let newFirst, focusedCommentID == Self.placeholderFocusID {
                focusedCommentID = newFirst
            }
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
            closeHint
        }
        .frame(width: 720)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.88))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble.fill")
                .font(.title3)
                .foregroundStyle(.dumpiGreen)
            Text("Reaguursels", comment: "Comments panel header")
                .font(.headline)
                .foregroundStyle(.white)
            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            statusView { ProgressView() }
        } else if loadFailed {
            statusView {
                Text("Reaguursels laden mislukt", comment: "Comments panel load failure")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else if comments.isEmpty {
            statusView {
                Text("Geen reaguursels", comment: "No comments available")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(comments) { comment in
                        commentRow(comment, isReply: false)
                        ForEach(comment.replies) { reply in
                            commentRow(reply, isReply: true)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 10)
            }
        }
    }

    /// Centered status content that still takes focus, keeping Menu → close alive.
    private func statusView(@ViewBuilder _ label: () -> some View) -> some View {
        VStack {
            Spacer()
            label()
                .frame(maxWidth: .infinity)
            Spacer()
        }
        .focusable()
        .focused($focusedCommentID, equals: Self.placeholderFocusID)
    }

    private func commentRow(_ comment: DumpertComment, isReply: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isReply {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("@\(comment.authorUsername)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white.opacity(0.85))

                    if let date = comment.creationDate {
                        Text(date.relativeString)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 3) {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.caption2)
                        Text("\(comment.kudosCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(.dumpiGreen)
                }

                Text(comment.displayContent.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.callout)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(focusedCommentID == comment.id ? 0.12 : 0.04))
        )
        .padding(.leading, isReply ? 44 : 0)
        .focusable()
        .focused($focusedCommentID, equals: comment.id)
        .animation(reduceMotion ? nil : .dumpiFocus, value: focusedCommentID)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(isReply ? String(localized: "Reactie van", comment: "Accessibility: reply comment prefix") : String(localized: "Reaguursel van", comment: "Accessibility: comment prefix")) \(comment.authorUsername): \(comment.displayContent)",
            comment: "Accessibility: comment row"
        ))
    }

    private var closeHint: some View {
        Text("Druk op Menu om te sluiten", comment: "Comments panel close hint")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }
}
