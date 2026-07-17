import SwiftUI

struct AddEventSheet: View {
    @State private var title = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
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
                    Button {
                        save()
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.tr(.saveEvent))
                                    .bold()
                            }
                            Spacer()
                        }
                    }
                    .tint(.white)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
                .listRowBackground(Color(red: 169/255, green: 229/255, blue: 214/255))
            }
        }
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
