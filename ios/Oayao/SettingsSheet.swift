import SwiftUI

/// Settings screen styled after the iOS system Settings app.
struct SettingsSheet: View {
    @AppStorage(SettingsStore.calendarNameKey) private var calendarName = SettingsStore.defaultCalendarName
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0
    @AppStorage(SettingsStore.nebulaEnabledKey) private var nebulaEnabled = false
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var counterStart = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    if calendarManager.hasAccess {
                        NavigationLink {
                            CalendarNameSettingsView()
                        } label: {
                            HStack {
                                Text(L10n.tr(.name))
                                Spacer()
                                Text(calendarName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        NavigationLink {
                            ShareGuideView()
                        } label: {
                            Text(L10n.tr(.shareWithPartner))
                        }
                    } else {
                        Button {
                            CalendarManager.openSystemSettings()
                        } label: {
                            HStack {
                                Text(L10n.tr(.calendarAccessNeeded))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(L10n.tr(.openSettings))
                            }
                        }
                    }
                } header: {
                    Text(L10n.tr(.calendar))
                } footer: {
                    Text(L10n.tr(.calendarFooter))
                }

                Section {
                    NavigationLink {
                        CounterStartSettingsView(counterStart: $counterStart)
                    } label: {
                        HStack {
                            Text(L10n.tr(.startDate))
                            Spacer()
                            Text(counterStart, style: .date)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.tr(.daysCounter))
                } footer: {
                    Text(L10n.tr(.counterFooter))
                }

                Section {
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        HStack {
                            Text(L10n.tr(.theme))
                            Spacer()
                            Text(CanvasTheme(storedId: UInt32(themeId)).name)
                                .foregroundColor(.secondary)
                        }
                    }
                    NavigationLink {
                        HeartSettingsView()
                    } label: {
                        Text(L10n.tr(.heart))
                    }
                    Toggle(L10n.tr(.nebula), isOn: $nebulaEnabled)
                        .onChange(of: nebulaEnabled) { oayao_set_nebula_enabled($0 ? 1 : 0) }
                } footer: {
                    Text(L10n.tr(.themeFooter))
                }

                Section {
                    NavigationLink {
                        LanguageSettingsView()
                    } label: {
                        HStack {
                            Text(L10n.tr(.language))
                            Spacer()
                            Text(languageManager.language.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(L10n.tr(.settings))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr(.done)) { dismiss() }
                }
            }
        }
        .onAppear {
            counterStart = CalendarManager.shared.counterStartDate()
        }
    }
}

/// Language picker; defaults to following the system locale.
private struct LanguageSettingsView: View {
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        Form {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        languageManager.language = language
                    } label: {
                        HStack {
                            Text(language.displayName)
                                .foregroundColor(.primary)
                            Spacer()
                            if language == languageManager.language {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr(.language))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Step-by-step guide for sharing the calendar with a partner via iCloud.
/// The final step (adding a person) can only happen in the Calendar app —
/// there is no public API to invite a sharee programmatically.
private struct ShareGuideView: View {
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var isShareable = true

    var body: some View {
        Form {
            Section {
                GuideStep(number: 1, text: L10n.tr(.guideStep1, SettingsStore.calendarName))
                GuideStep(number: 2, text: L10n.tr(.guideStep2))
                GuideStep(number: 3, text: L10n.tr(.guideStep3))
                GuideStep(number: 4, text: L10n.tr(.guideStep4))
            } header: {
                Text(L10n.tr(.howItWorks))
            }

            Section {
                Button(L10n.tr(.openCalendarApp)) {
                    openInCalendarApp()
                }
                if !isShareable {
                    Text(L10n.tr(.calendarNotShareable))
                        .foregroundColor(.secondary)
                }
            } footer: {
                if isShareable {
                    Text(L10n.tr(.sharingUsesIcloud))
                }
            }
        }
        .navigationTitle(L10n.tr(.shareWithPartner))
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
    @ObservedObject private var languageManager = LanguageManager.shared
    @State private var draft = ""

    var body: some View {
        Form {
            Section {
                TextField(L10n.tr(.calendarNamePlaceholder), text: $draft)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            } footer: {
                Text(L10n.tr(.calendarNameFooter))
            }
        }
        .navigationTitle(L10n.tr(.calendarName))
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
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        Form {
            Section {
                DatePicker(
                    L10n.tr(.startDate),
                    selection: $counterStart,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            } footer: {
                Text(L10n.tr(.changesApplyImmediately))
            }
        }
        .navigationTitle(L10n.tr(.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: counterStart) { newValue in
            CalendarManager.shared.setCounterStart(date: newValue)
        }
    }
}

/// Big-heart behaviour: size, opacity, motion style, and vertical position.
/// All changes apply live on the canvas.
private struct HeartSettingsView: View {
    @AppStorage(SettingsStore.heartOpacityKey) private var opacity = 1.0
    @AppStorage(SettingsStore.heartMotionKey) private var motion = 0
    @AppStorage(SettingsStore.heartSizeScaleKey) private var sizeScale = 1.0
    @State private var yFraction: Double? = SettingsStore.heartY
    @ObservedObject private var languageManager = LanguageManager.shared

    private var allDefaults: Bool {
        sizeScale == 1.0 && opacity == 1.0 && motion == 0 && yFraction == nil
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr(.size))
                        Spacer()
                        Text("\(Int((sizeScale * 100).rounded()))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $sizeScale, in: 0.5...2)
                        .onChange(of: sizeScale) { oayao_set_heart_size_scale(Float($0)) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr(.opacity))
                        Spacer()
                        Text("\(Int((opacity * 100).rounded()))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $opacity, in: 0...1)
                        .onChange(of: opacity) { oayao_set_heart_opacity(Float($0)) }
                }
                Picker(L10n.tr(.motion), selection: $motion) {
                    Text(L10n.tr(.motionBeat)).tag(0)
                    Text(L10n.tr(.motionBreath)).tag(1)
                }
                .pickerStyle(.segmented)
                .onChange(of: motion) { oayao_set_heart_motion(UInt32($0)) }
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr(.positionY))
                        Spacer()
                        Text("\(Int((displayedY * 100).rounded()))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: yBinding, in: 0.1...0.9)
                }
            }

            Section {
                Button(L10n.tr(.resetDefaults)) {
                    sizeScale = 1.0
                    opacity = 1.0
                    motion = 0
                    yFraction = nil
                    SettingsStore.heartY = nil
                    oayao_reset_heart_config()
                }
                .disabled(allDefaults)
            }
        }
        .navigationTitle(L10n.tr(.heart))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var displayedY: Double {
        yFraction ?? Double(oayao_default_heart_y())
    }

    private var yBinding: Binding<Double> {
        Binding(
            get: { displayedY },
            set: { newValue in
                yFraction = newValue
                SettingsStore.heartY = newValue
                oayao_set_heart_y(Float(newValue))
            }
        )
    }
}

/// Canvas themes; raw values mirror the renderer's ThemeId enum in Zig.
enum CanvasTheme: UInt32, CaseIterable, Identifiable {
    case mint = 0
    case peach = 1
    case custom = 2
    case midnight = 3

    var id: UInt32 { rawValue }

    /// Picker display order: the custom theme always sorts last, regardless
    /// of raw value or themes added later.
    static var pickerOrder: [CanvasTheme] {
        allCases.filter { $0 != .custom } + [.custom]
    }

    init(storedId: UInt32) {
        self = CanvasTheme(rawValue: storedId) ?? .mint
    }

    var name: String {
        switch self {
        case .mint: return L10n.tr(.themeMint)
        case .peach: return L10n.tr(.themePeach)
        case .custom: return L10n.tr(.themeCustom)
        case .midnight: return L10n.tr(.themeMidnight)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .mint: return Color(packedRGB: 0xA9E5D6)
        case .peach: return Color(packedRGB: 0xF5CDD7)
        case .custom: return Color(packedRGB: SettingsStore.customThemeColors["background"] ?? 0xA9E5D6)
        case .midnight: return Color(packedRGB: 0x12182E)
        }
    }

    /// Heart fill of the theme; pairs with `backgroundColor` for readable
    /// foreground text on theme-tinted surfaces. Values mirror the
    /// renderer's palettes in src/core/theme.zig.
    var heartFillColor: Color {
        switch self {
        case .mint: return Color(packedRGB: 0xFFFFFF)
        case .peach: return Color(packedRGB: 0xFFFFFF)
        case .custom: return Color(packedRGB: SettingsStore.customThemeColors["heartFill"] ?? 0xFFFFFF)
        case .midnight: return Color(packedRGB: 0xEEF3FF)
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
        case .background: return L10n.tr(.colorBackground)
        case .heartFill: return L10n.tr(.colorHeartFill)
        case .heartStroke: return L10n.tr(.colorHeartStroke)
        case .timerText: return L10n.tr(.colorTimerText)
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
    @ObservedObject private var languageManager = LanguageManager.shared
    // Draft colors stay unquantized while dragging the picker; rounding to
    // 8-bit happens only when persisting and pushing to the renderer,
    // otherwise the picker readback snaps the slider to coarse steps.
    @State private var draftColors: [String: Color] = [:]

    var body: some View {
        Form {
            Section {
                ForEach(CanvasTheme.pickerOrder) { theme in
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
                    Text(L10n.tr(.customColors))
                } footer: {
                    Text(L10n.tr(.customColorsFooter))
                }
            }
        }
        .navigationTitle(L10n.tr(.theme))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let stored = SettingsStore.customThemeColors
            var colors: [String: Color] = [:]
            for role in CustomColorRole.allCases {
                colors[role.key] = Color(packedRGB: stored[role.key] ?? 0xFFFFFF)
            }
            draftColors = colors
        }
    }

    private func customColorBinding(_ role: CustomColorRole) -> Binding<Color> {
        Binding(
            get: { draftColors[role.key] ?? .white },
            set: { newColor in
                draftColors[role.key] = newColor
                let packed = newColor.packedRGB
                var stored = SettingsStore.customThemeColors
                stored[role.key] = packed
                SettingsStore.customThemeColors = stored
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
