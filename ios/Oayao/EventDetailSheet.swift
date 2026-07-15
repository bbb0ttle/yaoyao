import SwiftUI
import EventKit

struct EventDetailSheet: View {
    let eventId: String
    @State private var event: EKEvent?
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

                        if let location = event.location, !location.isEmpty {
                            Section("Location") {
                                Text(location)
                                    .font(.body)
                            }
                        }

                    }
                    .navigationTitle("Event")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Menu {
                                Button(role: .destructive) {
                                    manager.deleteEvent(with: eventId) { _ in
                                        dismiss()
                                    }
                                } label: {
                                    Label("Delete Event", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
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
    }
}
