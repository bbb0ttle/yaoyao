import SwiftUI

struct AddEventSheet: View {
    @State private var title = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private var manager: CalendarManager { .shared }

    var body: some View {
        NavigationView {
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
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        manager.addEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            startDate: date,
            notes: notes.trimmingCharacters(in: .whitespaces)
        ) { success in
            dismiss()
        }
    }
}
