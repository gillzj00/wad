import SwiftData
import SwiftUI

/// The player whose Venmo handle is edited.
struct VenmoHandleEdit: Identifiable {
    var playerID: String
    var name: String

    var id: String { playerID }
}

/// Adds, changes or removes a player's Venmo handle.
struct VenmoHandleEditor: View {
    @Environment(\.dismiss) private var dismiss

    let round: Round
    let edit: VenmoHandleEdit

    @State private var text: String
    @State private var failure: String?

    init(round: Round, edit: VenmoHandleEdit) {
        self.round = round
        self.edit = edit
        let handle = round.players.first { $0.playerID == edit.playerID }?.venmoHandle
        _text = State(initialValue: handle ?? "")
    }

    private var parsed: VenmoHandle.Parsed { VenmoHandle.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Venmo handle", text: $text)
                        .keyboardType(.asciiCapable)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("venmoHandle.field")
                } header: {
                    SectionHeader(edit.name)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if parsed == .invalid {
                            Text(VenmoHandle.rule)
                                .foregroundStyle(Theme.Palette.blood)
                                .accessibilityIdentifier("venmoHandle.invalid")
                        }
                        SectionFooter("The name after the @ in Venmo. Leave it blank for a player without Venmo. "
                            + "Wad does not check it against Venmo.")
                    }
                }
                .themedRows()
            }
            .themedList()
            .navigationTitle("Venmo handle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(parsed == .invalid)
                        .accessibilityIdentifier("venmoHandle.save")
                }
            }
            .alert("Could not save", isPresented: .constant(failure != nil)) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func save() {
        do {
            try PaymentLedger(round: round).setVenmoHandle(text, playerID: edit.playerID)
            dismiss()
        } catch {
            failure = String(describing: error)
        }
    }
}
