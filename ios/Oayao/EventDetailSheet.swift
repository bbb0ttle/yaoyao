import SwiftUI
import EventKit

struct EventDetailSheet: View {
    let eventId: String
    @State private var event: EKEvent?
    @State private var editDate: Date = Date()
    @State private var showDeleteConfirmation = false
    @Environment(\.dismiss) private var dismiss

    private var manager: CalendarManager { .shared }

    var body: some View {
        NavigationView {
            Group {
                if let event = event {
                    Form {
                        Section("Title") {
                            Text(event.title)
                                .font(.body)
                        }

                        if let notes = event.notes, !notes.isEmpty {
                            Section("Notes") {
                                Text(notes)
                                    .font(.body)
                            }
                        }

                        Section("Date") {
                            HStack {
                                DatePicker("Date", selection: $editDate, displayedComponents: [.date])
                                    .labelsHidden()
                                DatePicker("Time", selection: $editDate, displayedComponents: [.hourAndMinute])
                                    .labelsHidden()
                            }
                            .onChange(of: editDate) { newDate in
                                manager.updateEvent(
                                    with: eventId,
                                    title: nil,
                                    startDate: newDate,
                                    notes: nil
                                ) { _ in
                                    self.event = manager.event(with: eventId)
                                }
                            }
                        }


                        if let location = event.location, !location.isEmpty {
                            Section("Location") {
                                Text(location)
                                    .font(.body)
                            }
                        }

                        Section {
                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Event")
                                    Spacer()
                                }
                            }
                        }
                    }
                    .navigationTitle("Event")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                } else {
                    ProgressView()
                        .navigationTitle("Loading...")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear {
            if let e = manager.event(with: eventId) {
                event = e
                editDate = e.startDate
            }
        }
        .confirmationDialog(
            "Delete this event?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                manager.deleteEvent(with: eventId) { success in
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
