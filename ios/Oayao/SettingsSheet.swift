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
                    NavigationLink {
                        ShareGuideView()
                    } label: {
                        Text("Share with Partner")
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Events in this calendar appear as floating hearts. Share it with your partner to see each other's hearts.")
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
                    Text("Recorded in the calendar so it syncs to your partner when shared.")
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
}

/// Step-by-step guide for sharing the calendar with a partner via iCloud.
/// The final step (adding a person) can only happen in the Calendar app —
/// there is no public API to invite a sharee programmatically.
private struct ShareGuideView: View {
    @State private var isShareable = true

    var body: some View {
        Form {
            Section {
                GuideStep(number: 1, text: "Tap \"Open Calendar App\" below to jump to this calendar. If you land on the calendar list, tap the info button next to \"\(SettingsStore.calendarName)\".")
                GuideStep(number: 2, text: "Tap \"Add Person\" under Shared With.")
                GuideStep(number: 3, text: "Enter your partner's Apple ID email and send the invitation.")
                GuideStep(number: 4, text: "Once they accept, their events appear as hearts on your canvas — and yours on theirs. They only need this app with the same calendar name (the default works).")
            } header: {
                Text("How It Works")
            }

            Section {
                Button("Open Calendar App") {
                    openInCalendarApp()
                }
                if !isShareable {
                    Text("The current calendar is not iCloud-backed, so it can't be shared. Calendars created by this app use iCloud when it's available.")
                        .foregroundColor(.secondary)
                }
            } footer: {
                if isShareable {
                    Text("Sharing uses iCloud — no account or sign-up needed in this app.")
                }
            }
        }
        .navigationTitle("Share with Partner")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isShareable = CalendarManager.shared.currentCalendarIsShareable()
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

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number, format: .number)
                .font(.footnote.weight(.bold))
                .foregroundColor(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
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
                Text("Changes apply immediately.")
            }
        }
        .navigationTitle("Start Date")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: counterStart) { newValue in
            CalendarManager.shared.setCounterStart(date: newValue)
        }
    }
}
