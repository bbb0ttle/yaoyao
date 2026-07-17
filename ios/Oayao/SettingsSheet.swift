import SwiftUI

/// Settings screen styled after the iOS system Settings app.
struct SettingsSheet: View {
    @AppStorage(SettingsStore.calendarNameKey) private var calendarName = SettingsStore.defaultCalendarName
    @State private var counterStart = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    NavigationLink {
                        CalendarNameSettingsView()
                    } label: {
                        HStack {
                            Text("Name")
                            Spacer()
                            Text(calendarName)
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("Open in Calendar") {
                        openInCalendarApp()
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Events in this calendar appear as floating hearts.")
                }

                Section {
                    NavigationLink {
                        CounterStartSettingsView(counterStart: $counterStart)
                    } label: {
                        HStack {
                            Text("Start Date")
                            Spacer()
                            Text(counterStart, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Days Counter")
                } footer: {
                    Text("Saved as a \"counter start\" event in the calendar. Deleting that event restores the default date.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            counterStart = CalendarManager.shared.counterStartDate()
        }
    }

    private func openInCalendarApp() {
        CalendarManager.shared.shareCalendar { url in
            guard let url = url else { return }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }
}

/// Edit page for the calendar the app reads and writes events in.
private struct CalendarNameSettingsView: View {
    @AppStorage(SettingsStore.calendarNameKey) private var calendarName = SettingsStore.defaultCalendarName
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                TextField("Calendar name", text: $draft)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            } footer: {
                Text("If no calendar with this name exists, a new one is created.")
            }
        }
        .navigationTitle("Calendar Name")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = calendarName
        }
        .onDisappear {
            save()
        }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        let resolved = trimmed.isEmpty ? SettingsStore.defaultCalendarName : trimmed
        guard resolved != calendarName else { return }
        calendarName = resolved
        CalendarManager.shared.calendarNameDidChange()
    }
}

/// Edit page for the day counter start date; changes apply immediately.
private struct CounterStartSettingsView: View {
    @Binding var counterStart: Date

    var body: some View {
        Form {
            Section {
                DatePicker(
                    "Start Date",
                    selection: $counterStart,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            } footer: {
                Text("Creates or moves the \"counter start\" event in the calendar.")
            }
        }
        .navigationTitle("Start Date")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: counterStart) { newValue in
            CalendarManager.shared.setCounterStart(date: newValue) { _ in }
        }
    }
}
