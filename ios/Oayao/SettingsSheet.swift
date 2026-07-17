import SwiftUI

/// Settings screen styled after the iOS system Settings app.
struct SettingsSheet: View {
    @AppStorage(SettingsStore.calendarNameKey) private var calendarName = SettingsStore.defaultCalendarName
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0
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

                Section {
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        HStack {
                            Text("Theme")
                            Spacer()
                            Text(CanvasTheme(storedId: UInt32(themeId)).name)
                                .foregroundColor(.secondary)
                        }
                    }
                } footer: {
                    Text("Canvas colors fade smoothly when switching themes.")
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

/// Canvas themes; raw values mirror the renderer's ThemeId enum in Zig.
enum CanvasTheme: UInt32, CaseIterable, Identifiable {
    case mint = 0
    case peach = 1
    case custom = 2

    var id: UInt32 { rawValue }

    init(storedId: UInt32) {
        self = CanvasTheme(rawValue: storedId) ?? .mint
    }

    var name: String {
        switch self {
        case .mint: return "Mint"
        case .peach: return "Peach"
        case .custom: return "Custom"
        }
    }

    var backgroundColor: Color {
        switch self {
        case .mint: return Color(packedRGB: 0xA9E5D6)
        case .peach: return Color(packedRGB: 0xF5CDD7)
        case .custom: return Color(packedRGB: SettingsStore.customThemeColors["background"] ?? 0xA9E5D6)
        }
    }
}

/// Roles of the custom theme's editable colors; raw values mirror the
/// renderer's ColorRole enum in Zig.
private enum CustomColorRole: UInt32, CaseIterable {
    case background = 0
    case heartFill = 1
    case heartStroke = 2
    case timerText = 3

    var key: String {
        switch self {
        case .background: return "background"
        case .heartFill: return "heartFill"
        case .heartStroke: return "heartStroke"
        case .timerText: return "timerText"
        }
    }

    var label: String {
        switch self {
        case .background: return "Background"
        case .heartFill: return "Heart Fill"
        case .heartStroke: return "Heart Stroke"
        case .timerText: return "Timer Text"
        }
    }
}

private extension Color {
    init(packedRGB: Int) {
        self.init(
            red: Double((packedRGB >> 16) & 0xFF) / 255,
            green: Double((packedRGB >> 8) & 0xFF) / 255,
            blue: Double(packedRGB & 0xFF) / 255
        )
    }

    var packedRGB: Int {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(round(r * 255)) << 16) | (Int(round(g * 255)) << 8) | Int(round(b * 255))
    }
}

/// Theme picker; selection persists and applies immediately with an animated fade.
private struct ThemeSettingsView: View {
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0
    @State private var customColors: [String: Int] = SettingsStore.customThemeColors

    var body: some View {
        Form {
            Section {
                ForEach(CanvasTheme.allCases) { theme in
                    Button {
                        themeId = Int(theme.rawValue)
                        oayao_transition_to_theme(theme.rawValue)
                    } label: {
                        HStack {
                            Circle()
                                .fill(theme.backgroundColor)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    Circle().stroke(.primary.opacity(0.15), lineWidth: 0.5)
                                }
                            Text(theme.name)
                                .foregroundColor(.primary)
                            Spacer()
                            if Int(theme.rawValue) == themeId {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }

            if CanvasTheme(storedId: UInt32(themeId)) == .custom {
                Section {
                    ForEach(CustomColorRole.allCases, id: \.key) { role in
                        ColorPicker(role.label, selection: customColorBinding(role), supportsOpacity: false)
                    }
                } header: {
                    Text("Custom Colors")
                } footer: {
                    Text("Changes fade in immediately on the canvas.")
                }
            }
        }
        .navigationTitle("Theme")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func customColorBinding(_ role: CustomColorRole) -> Binding<Color> {
        Binding(
            get: { Color(packedRGB: customColors[role.key] ?? 0xFFFFFF) },
            set: { newColor in
                let packed = newColor.packedRGB
                customColors[role.key] = packed
                SettingsStore.customThemeColors = customColors
                oayao_set_custom_theme_color(
                    role.rawValue,
                    UInt8((packed >> 16) & 0xFF),
                    UInt8((packed >> 8) & 0xFF),
                    UInt8(packed & 0xFF)
                )
            }
        )
    }
}
