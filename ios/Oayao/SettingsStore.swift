import Foundation

/// Persists user-configurable settings in UserDefaults.
enum SettingsStore {
    static let calendarNameKey = "oayao.calendarName"
    static let counterStartMsKey = "oayao.counterStartMs"
    static let themeIdKey = "oayao.themeId"
    static let customThemeColorsKey = "oayao.customThemeColors"
    static let heartOpacityKey = "oayao.heartOpacity"
    static let heartMotionKey = "oayao.heartMotion"
    static let heartYKey = "oayao.heartY"
    static let heartSizeScaleKey = "oayao.heartSizeScale"
    static let defaultCalendarName = "oayao"

    /// Name of the calendar the app reads and writes events in.
    /// Falls back to the default when the stored value is blank.
    static var calendarName: String {
        let stored = UserDefaults.standard.string(forKey: calendarNameKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? defaultCalendarName : trimmed
    }

    /// Day counter start timestamp (Unix epoch milliseconds).
    /// Local cache of the date recorded in the calendar's marker event;
    /// falls back to the renderer's built-in default when never set.
    static var counterStartMs: Double {
        get {
            let stored = UserDefaults.standard.object(forKey: counterStartMsKey) as? Double
            return stored ?? oayao_days_counter_default_start_ms()
        }
        set {
            UserDefaults.standard.set(newValue, forKey: counterStartMsKey)
        }
    }

    /// Selected canvas theme. Values mirror the renderer's ThemeId enum.
    static var themeId: UInt32 {
        get {
            let stored = UserDefaults.standard.object(forKey: themeIdKey) as? Int
            return UInt32(stored ?? 0)
        }
        set {
            UserDefaults.standard.set(Int(newValue), forKey: themeIdKey)
        }
    }

    /// Custom theme colors as packed RGB (0xRRGGBB) keyed by role.
    /// Defaults mirror the renderer's mint palette so the custom theme
    /// starts as an editable copy of mint.
    static var customThemeColors: [String: Int] {
        get {
            let stored = UserDefaults.standard.dictionary(forKey: customThemeColorsKey) as? [String: Int] ?? [:]
            return defaultCustomThemeColors.merging(stored) { _, new in new }
        }
        set {
            UserDefaults.standard.set(newValue, forKey: customThemeColorsKey)
        }
    }

    static let defaultCustomThemeColors: [String: Int] = [
        "background": 0xA9E5D6,
        "heartFill": 0xFFFFFF,
        "heartStroke": 0xDBECE6,
        "timerText": 0xFFFFFF,
    ]

    /// Big heart opacity (0.0–1.0); defaults to fully opaque.
    static var heartOpacity: Double {
        get { UserDefaults.standard.object(forKey: heartOpacityKey) as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: heartOpacityKey) }
    }

    /// Big heart motion mode; values mirror the renderer's MotionMode enum
    /// (0 = beat, 1 = breath).
    static var heartMotion: Int {
        get { UserDefaults.standard.object(forKey: heartMotionKey) as? Int ?? 0 }
        set { UserDefaults.standard.set(newValue, forKey: heartMotionKey) }
    }

    /// Big heart overall size multiplier; defaults to 1.0.
    static var heartSizeScale: Double {
        get { UserDefaults.standard.object(forKey: heartSizeScaleKey) as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: heartSizeScaleKey) }
    }

    /// Big heart vertical position as a fraction of canvas height.
    /// nil means the renderer's built-in default.
    static var heartY: Double? {
        get { UserDefaults.standard.object(forKey: heartYKey) as? Double }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: heartYKey)
            } else {
                UserDefaults.standard.removeObject(forKey: heartYKey)
            }
        }
    }
}
