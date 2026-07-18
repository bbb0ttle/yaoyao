import SwiftUI
import EventKit

struct EventDetailSheet: View {
    let eventId: String
    @State private var event: EKEvent?
    @State private var draftTitle = ""
    @State private var draftDate = Date()
    @State private var draftNotes = ""
    @State private var didInitDrafts = false
    @State private var saveTask: Task<Void, Never>?
    @ObservedObject private var languageManager = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    private var manager: CalendarManager { .shared }

    /// Deletion is offered only for events the user owns: read-only shared
    /// calendars forbid it, and events organised by the partner are hidden
    /// to prevent accidental removal of their hearts.
    private var canDelete: Bool {
        guard let event = event else { return false }
        guard event.calendar.allowsContentModifications else { return false }
        if let organizer = event.organizer, !organizer.isCurrentUser { return false }
        return true
    }

    private var canEdit: Bool { canDelete }

    var body: some View {
        NavigationView {
            Group {
                if let event = event {
                    if canEdit {
                        editableForm(event)
                    } else {
                        readonlyForm(event)
                    }
                } else {
                    ProgressView()
                        .navigationTitle(L10n.tr(.loading))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .onAppear {
            guard let event = manager.event(with: eventId) else { return }
            self.event = event
            draftTitle = event.title
            draftDate = event.startDate
            draftNotes = event.notes ?? ""
            didInitDrafts = true
        }
        .onChange(of: draftTitle) { _ in scheduleSave() }
        .onChange(of: draftDate) { _ in scheduleSave() }
        .onChange(of: draftNotes) { _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            saveNow()
        }
    }

    /// Editable form for events the user owns.
    private func editableForm(_ event: EKEvent) -> some View {
        Form {
            Section(L10n.tr(.title)) {
                TextField(L10n.tr(.eventName), text: $draftTitle)
            }

            Section(L10n.tr(.date)) {
                DatePicker(L10n.tr(.date), selection: $draftDate)
            }

            Section(L10n.tr(.notesOptional)) {
                TextEditor(text: $draftNotes)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle(L10n.tr(.event))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.tr(.close)) { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                if canDelete {
                    deleteMenu()
                }
            }
        }
    }

    /// Read-only form for the partner's events.
    private func readonlyForm(_ event: EKEvent) -> some View {
        Form {
            Section(L10n.tr(.title)) {
                Text(event.title)
                    .font(.body)
            }

            Section(L10n.tr(.date)) {
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
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
        }
    }

    private func deleteMenu() -> some View {
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
                .foregroundColor(.red)
        }
    }

    /// Debounced auto-save: rapid edits (typing) coalesce into one write.
    private func scheduleSave() {
        guard didInitDrafts, canEdit else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard didInitDrafts, canEdit else { return }
        let title = draftTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        manager.updateEvent(
            with: eventId,
            title: title,
            startDate: draftDate,
            notes: draftNotes.trimmingCharacters(in: .whitespaces)
        ) { _ in }
    }
}
