import SwiftUI

/// When the scoring screen pops up the way to the round summary: after the
/// change that gives every player a score on every hole, and after a change
/// on the last hole of a round that is already complete, since a round that
/// started every hole at par is complete before it is played.
enum RoundCompletionPrompt {
    static func shows(wasComplete: Bool, isComplete: Bool, changedHole: Int, lastHole: Int) -> Bool {
        isComplete && (!wasComplete || changedHole == lastHole)
    }
}

/// The pop-up: on to the round summary, where the round is reconciled, or
/// back to the scores.
struct RoundCompletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Called before the sheet is dismissed for the round summary.
    let onSummary: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "flag.checkered")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Theme.Palette.ember)
                    .accessibilityHidden(true)
                Text("Round complete")
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Palette.bone)
                    .accessibilityAddTraits(.isHeader)
                Text("Every player has a score on every hole.")
                    .font(.body)
                    .foregroundStyle(Theme.Palette.ash)
                ChainDivider()
                    .frame(maxWidth: 220)
                Button {
                    onSummary()
                    dismiss()
                } label: {
                    Label("Round summary", systemImage: "dollarsign.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .accessibilityIdentifier("scoring.completePrompt.summary")
                Button {
                    dismiss()
                } label: {
                    Text("Keep scoring")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("scoring.completePrompt.dismiss")
            }
            .multilineTextAlignment(.center)
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("scoring.completePrompt")
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Palette.charcoal)
    }
}

#if DEBUG
#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        RoundCompletionSheet {}
    }
}
#endif
