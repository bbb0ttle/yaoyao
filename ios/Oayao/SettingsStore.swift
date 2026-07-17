import Foundation

/// Persists user-configurable settings in UserDefaults.
enum SettingsStore {
    static let calendarNameKey = "oayao.calendarName"
    static let counterStartMsKey = "oayao.counterStartMs"
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
}
