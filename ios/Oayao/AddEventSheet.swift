import SwiftUI

struct AddEventSheet: View {
    @State private var title = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L10n.tr(.cancel)) { dismiss() }
                    .padding(.leading, 4)
                Spacer()
                Text(L10n.tr(.newEvent))
                    .font(.headline)
                Spacer()
                // Invisible placeholder keeps title centred
                Button(L10n.tr(.cancel)) { }
                    .padding(.trailing, 4)
                    .opacity(0)
                    .disabled(true)
            }
            .padding(.horizontal)
            .padding(.top, 22)
            .padding(.bottom, 10)

            Form {
                Section(L10n.tr(.title)) {
                    TextField(L10n.tr(.eventName), text: $title)
                }

                Section(L10n.tr(.notesOptional)) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    // Disabled-state styling is manual: SwiftUI's automatic
                    // dimming stacks with the tinted row and crushes
                    // legibility on dark themes like midnight.
                    Button {
                        guard canSave else { return }
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(CanvasTheme(storedId: UInt32(themeId)).readableTextColor)
                            } else {
                                Text(L10n.tr(.saveEvent))
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .tint(CanvasTheme(storedId: UInt32(themeId)).readableTextColor.opacity(canSave ? 1.0 : 0.45))
                }
                .listRowBackground(CanvasTheme(storedId: UInt32(themeId)).backgroundColor)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    private func save() {
        isSaving = true
        CalendarManager.shared.addEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: date,
            notes: notes.trimmingCharacters(in: .whitespaces)
        ) { success in
            dismiss()
        }
    }
}
