import Foundation

/// Persists user-configurable settings in UserDefaults.
enum SettingsStore {
    static let calendarNameKey = "oayao.calendarName"
    static let defaultCalendarName = "oayao"

    /// Name of the calendar the app reads and writes events in.
    /// Falls back to the default when the stored value is blank.
    static var calendarName: String {
        let stored = UserDefaults.standard.string(forKey: calendarNameKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? defaultCalendarName : trimmed
    }
}
