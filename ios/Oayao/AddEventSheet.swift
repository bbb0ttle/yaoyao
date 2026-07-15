import SwiftUI

struct AddEventSheet: View {
    @State private var title = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .padding(.leading, 4)
                Spacer()
                Text("New Event")
                    .font(.headline)
                Spacer()
                // Invisible placeholder keeps title centred
                Button("Cancel") { }
                    .padding(.trailing, 4)
                    .opacity(0)
                    .disabled(true)
            }
            .padding(.horizontal)
            .padding(.top, 22)
            .padding(.bottom, 10)

            Form {
                Section("Title") {
                    TextField("Event name", text: $title)
                }

                Section("Notes (optional)") {
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
                                Text("Save Event")
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
