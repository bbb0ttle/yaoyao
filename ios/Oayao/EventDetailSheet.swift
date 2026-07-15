import SwiftUI
import EventKit

struct EventDetailSheet: View {
    let eventId: String
    @State private var event: EKEvent?
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
                            Text(event.startDate, style: .date)
                                .font(.body)
                            Text(event.startDate, style: .time)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
            event = manager.event(with: eventId)
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
