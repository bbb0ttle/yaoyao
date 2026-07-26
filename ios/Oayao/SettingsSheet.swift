import SwiftUI

/// Settings screen styled after the iOS system Settings app.
struct SettingsSheet: View {
    @AppStorage(SettingsStore.calendarNameKey) private var calendarName = SettingsStore.defaultCalendarName
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0
    @State private var skyOn = true
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var counterStart: Date? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle(L10n.tr(.sky), isOn: $skyOn)
                        .onChange(of: skyOn) { on in
                            SettingsStore.skyMode = on ? 1 : 0
                            oayao_set_sky_mode(on ? 1 : 0)
                        }
                    NavigationLink {
                        ThemeSettingsView()
                    } label: {
                        HStack {
                            Text(L10n.tr(.colors))
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
                } header: {
                    Text(L10n.tr(.theme))
                } footer: {
                    Text(L10n.tr(.themeFooter))
                }

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
                    NavigationLink {
                        CounterStartSettingsView(counterStart: $counterStart)
                    } label: {
                        HStack {
                            Text(L10n.tr(.startDate))
                            Spacer()
                            if let counterStart {
                                Text(counterStart, style: .date)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(L10n.tr(.notSet))
                                    .foregroundColor(.secondary)
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
            skyOn = SettingsStore.skyMode != 0
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
    @Binding var counterStart: Date?
    @State private var picked = Date()
    @ObservedObject private var languageManager = LanguageManager.shared

    var body: some View {
        Form {
            Section {
                DatePicker(
                    L10n.tr(.startDate),
                    selection: $picked,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
            } footer: {
                Text(L10n.tr(.changesApplyImmediately))
            }
        }
        .navigationTitle(L10n.tr(.startDate))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            picked = counterStart ?? Date()
        }
        .onChange(of: picked) { newValue in
            counterStart = newValue
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

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L10n.tr(.positionY))
                        Spacer()
                        Text("\(Int((displayedY * 100).rounded()))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: yBinding, in: 0.1...0.9)
                }

                Button(L10n.tr(.resetDefaults)) {
                    sizeScale = 1.0
                    opacity = 1.0
                    motion = 0
                    yFraction = nil
                    SettingsStore.heartY = nil
                    oayao_reset_heart_config()
                }
                .buttonStyle(.borderless)
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
        Color(packedRGB: backgroundPacked)
    }

    /// Heart fill of the theme; pairs with `backgroundColor` for readable
    /// foreground text on theme-tinted surfaces. Values mirror the
    /// renderer's palettes in src/core/theme.zig.
    var heartFillColor: Color {
        Color(packedRGB: heartFillPacked)
    }

    var backgroundPacked: Int {
        switch self {
        case .mint: return 0xA9E5D6
        case .peach: return 0xF5CDD7
        case .custom: return SettingsStore.customThemeColors["background"] ?? 0xA9E5D6
        case .midnight: return 0x12182E
        }
    }

    var heartFillPacked: Int {
        switch self {
        case .mint: return 0xFFFFFF
        case .peach: return 0xFFFFFF
        case .custom: return SettingsStore.customThemeColors["heartFill"] ?? 0xFFFFFF
        case .midnight: return 0xEEF3FF
        }
    }

    /// Text color on `backgroundColor`: the theme's heart fill when it
    /// already meets WCAG AA contrast (4.5:1), otherwise the softest
    /// grayscale that still passes — never stark black or white.
    var readableTextColor: Color {
        Color(packedRGB: Self.readablePacked(heartFillPacked, on: backgroundPacked))
    }

    private static let minTextContrast: Double = 4.5

    private static func readablePacked(_ text: Int, on background: Int) -> Int {
        let bgLuminance = luminance(rgb(background))
        if contrast(bgLuminance, luminance(rgb(text))) >= minTextContrast {
            return text
        }
        // Grayscale luminance is monotone in value, so binary-search the
        // gentlest compliant gray: the lightest dark gray on light
        // backgrounds, the darkest light gray on dark ones.
        let preferDark = contrast(bgLuminance, 0.0) >= contrast(bgLuminance, 1.0)
        var lo = 0.0
        var hi = 1.0
        var best = preferDark ? 0.0 : 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if contrast(bgLuminance, luminance((mid, mid, mid))) >= minTextContrast {
                best = mid
                if preferDark { lo = mid } else { hi = mid }
            } else {
                if preferDark { hi = mid } else { lo = mid }
            }
        }
        let v = Int((best * 255).rounded())
        return v << 16 | v << 8 | v
    }

    private static func rgb(_ packed: Int) -> (r: Double, g: Double, b: Double) {
        (
            Double((packed >> 16) & 0xFF) / 255.0,
            Double((packed >> 8) & 0xFF) / 255.0,
            Double(packed & 0xFF) / 255.0
        )
    }

    private static func luminance(_ c: (r: Double, g: Double, b: Double)) -> Double {
        func linearize(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(c.r) + 0.7152 * linearize(c.g) + 0.0722 * linearize(c.b)
    }

    private static func contrast(_ a: Double, _ b: Double) -> Double {
        (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // MARK: - Derived heart stroke (custom palette)

    /// Stroke for a custom fill/background pair: the fill's own hue (same
    /// color family, so the canvas never turns into a rainbow), shifted in
    /// lightness just far enough to outline the heart — never so dark it
    /// reads as grime against the background.
    static func derivedStrokePacked(_ fill: Int, on background: Int) -> Int {
        let hslFill = hsl(rgb(fill))
        let fillLum = luminance(rgb(fill))
        let bgLum = luminance(rgb(background))

        func make(_ lightness: Double) -> Int {
            packed(hsl: (hslFill.h, hslFill.s, min(max(lightness, 0.08), 0.95)))
        }
        func meets(_ packedStroke: Int) -> Bool {
            contrast(luminance(rgb(packedStroke)), fillLum) >= 1.35
        }

        // Darken by default; if the darkest acceptable candidate already
        // dips well under the background luminance it would look dirty, so
        // go lighter instead.
        let darken = luminance(rgb(make(hslFill.l - 0.2))) >= bgLum * 0.85
        let lo = darken ? 0.08 : hslFill.l + 0.12
        let hi = darken ? hslFill.l - 0.12 : 0.95

        // Minimal |ΔL| that still outlines the heart (contrast grows with
        // distance from the fill, so the compliant point nearest the fill
        // is the answer; fall back to the far endpoint if none qualifies).
        var best = darken ? lo : hi
        if lo <= hi {
            var a = lo
            var b = hi
            for _ in 0..<20 {
                let mid = (a + b) / 2
                if meets(make(mid)) {
                    best = mid
                    if darken { a = mid } else { b = mid }
                } else {
                    if darken { b = mid } else { a = mid }
                }
            }
        }
        return make(best)
    }

    private static func hsl(_ c: (r: Double, g: Double, b: Double)) -> (h: Double, s: Double, l: Double) {
        let maxC = max(c.r, c.g, c.b)
        let minC = min(c.r, c.g, c.b)
        let l = (maxC + minC) / 2
        let d = maxC - minC
        if d == 0 { return (0, 0, l) }
        let s = l < 0.5 ? d / (maxC + minC) : d / (2 - maxC - minC)
        let h: Double
        if maxC == c.r {
            h = ((c.g - c.b) / d + (c.g < c.b ? 6 : 0)) / 6
        } else if maxC == c.g {
            h = ((c.b - c.r) / d + 2) / 6
        } else {
            h = ((c.r - c.g) / d + 4) / 6
        }
        return (h, s, l)
    }

    private static func packed(hsl c: (h: Double, s: Double, l: Double)) -> Int {
        func hueToRgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        let r: Double
        let g: Double
        let b: Double
        if c.s == 0 {
            r = c.l
            g = c.l
            b = c.l
        } else {
            let q = c.l < 0.5 ? c.l * (1 + c.s) : c.l + c.s - c.l * c.s
            let p = 2 * c.l - q
            r = hueToRgb(p, q, c.h + 1.0 / 3)
            g = hueToRgb(p, q, c.h)
            b = hueToRgb(p, q, c.h - 1.0 / 3)
        }
        return Int((r * 255).rounded()) << 16 | Int((g * 255).rounded()) << 8 | Int((b * 255).rounded())
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

/// Theme picker ("配色"): the three built-in palettes plus a link to the
/// custom-color page. Selection persists and applies immediately with an
/// animated fade.
private struct ThemeSettingsView: View {
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0

    var body: some View {
        Form {
            Section {
                ForEach(CanvasTheme.allCases.filter { $0 != .custom }) { theme in
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
                NavigationLink {
                    CustomColorView()
                } label: {
                    HStack {
                        Circle()
                            .fill(Color(packedRGB: SettingsStore.customThemeColors["background"] ?? 0xA9E5D6))
                            .frame(width: 22, height: 22)
                            .overlay {
                                Circle().stroke(.primary.opacity(0.15), lineWidth: 0.5)
                            }
                        Text(L10n.tr(.customColors))
                        Spacer()
                        if themeId == Int(CanvasTheme.custom.rawValue) {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            }
        }
        .navigationTitle(L10n.tr(.colors))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Custom colors: background and heart fill only. The heart stroke is
/// derived from the pair (same hue family as the fill, never grimy, always
/// a clear outline) and the timer text simply follows the fill — the two
/// knobs can't produce a broken palette.
private struct CustomColorView: View {
    @AppStorage(SettingsStore.themeIdKey) private var themeId = 0
    // Draft colors stay unquantized while dragging the picker; rounding to
    // 8-bit happens only when persisting and pushing to the renderer,
    // otherwise the picker readback snaps the slider to coarse steps.
    @State private var background: Color = .white
    @State private var heartFill: Color = .white

    var body: some View {
        Form {
            Section {
                ColorPicker(L10n.tr(.colorBackground), selection: $background, supportsOpacity: false)
                ColorPicker(L10n.tr(.colorHeartFill), selection: $heartFill, supportsOpacity: false)
            } footer: {
                Text(L10n.tr(.customColorsFooter))
            }
        }
        .navigationTitle(L10n.tr(.customColors))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let stored = SettingsStore.customThemeColors
            background = Color(packedRGB: stored["background"] ?? 0xA9E5D6)
            heartFill = Color(packedRGB: stored["heartFill"] ?? 0xFFFFFF)
            // Entering the page means previewing the custom palette live —
            // deferred one runloop: mutating @AppStorage mid-push makes the
            // legacy NavigationView bounce the destination straight back.
            DispatchQueue.main.async {
                themeId = Int(CanvasTheme.custom.rawValue)
                oayao_transition_to_theme(CanvasTheme.custom.rawValue)
            }
        }
        .onChange(of: background) { _ in push() }
        .onChange(of: heartFill) { _ in push() }
    }

    private func push() {
        let bg = background.packedRGB
        let fill = heartFill.packedRGB
        let stroke = CanvasTheme.derivedStrokePacked(fill, on: bg)
        var stored = SettingsStore.customThemeColors
        stored["background"] = bg
        stored["heartFill"] = fill
        stored["heartStroke"] = stroke
        stored["timerText"] = fill
        SettingsStore.customThemeColors = stored
        for role in CustomColorRole.allCases {
            let packed = stored[role.key]!
            oayao_set_custom_theme_color(
                role.rawValue,
                UInt8((packed >> 16) & 0xFF),
                UInt8((packed >> 8) & 0xFF),
                UInt8(packed & 0xFF)
            )
        }
    }
}
