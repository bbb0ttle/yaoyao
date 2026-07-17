import SwiftUI
import EventKit

struct EventDetailSheet: View {
    let eventId: String
    @State private var event: EKEvent?
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private var manager: CalendarManager { .shared }

    var body: some View {
        NavigationView {
            Group {
                if let event = event {
                    Form {
                        Section(L10n.tr(.title)) {
                            Text(event.title)
                                .font(.body)
                        }

                        if let notes = event.notes, !notes.isEmpty {
                            Section(L10n.tr(.notes)) {
                                Text(notes)
                                    .font(.body)
                            }
                        }

                        if let location = event.location, !location.isEmpty {
                            Section(L10n.tr(.location)) {
                                Text(location)
                                    .font(.body)
                            }
                        }

                    }
                    .navigationTitle(L10n.tr(.event))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(L10n.tr(.close)) { dismiss() }
                        }
                        ToolbarItem(placement: .destructiveAction) {
                            Menu {
                                Button(role: .destructive) {
                                    manager.deleteEvent(with: eventId) { _ in
                                        dismiss()
                                    }
                                } label: {
                                    Label(L10n.tr(.deleteEvent), systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .navigationTitle(L10n.tr(.loading))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear {
            event = manager.event(with: eventId)
        }
    }
}
