import EventKit
import UIKit

/// Wraps EventKit operations for the configured calendar.
/// Each calendar event maps to a floating heart in the Metal canvas.
@objc final class CalendarManager: NSObject, @unchecked Sendable {
    static let shared = CalendarManager()

    private let eventStore = EKEventStore()
    private var oayaoCalendars: [EKCalendar] = []
    private var writableCalendar: EKCalendar?
    private var hasAccess = false

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }

    // MARK: - Permission

    func requestAccess(completion: @escaping (Bool) -> Void) {
        eventStore.requestAccess(to: .event) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.hasAccess = granted
                self?.syncDaysCounter()
                if granted {
                    self?.findOrCreateCalendar(completion: completion)
                } else {
                    completion(false)
                }
            }
        }
    }

    // MARK: - Calendar

    /// Re-resolve the canonical calendar after the configured name changed.
    func calendarNameDidChange() {
        guard hasAccess else { return }
        resolveCanonicalCalendar { _ in }
    }

    /// Resolve a single canonical calendar matching the configured name.
    /// When multiple calendars share the title (self-created + shared subscriptions),
    /// only one is kept — preferring a writable local calendar.
    /// If no writable calendar exists, a new local one is created.
    private func findOrCreateCalendar(completion: @escaping (Bool) -> Void) {
        resolveCanonicalCalendar(completion: completion)
    }

    @objc private func handleEventStoreChanged() {
        guard hasAccess else { return }
        resolveCanonicalCalendar { _ in }
        syncAllEvents()
    }

    private func resolveCanonicalCalendar(completion: @escaping (Bool) -> Void) {
        let allCalendars = eventStore.calendars(for: .event).filter { $0.title == SettingsStore.calendarName }

        // Prefer a writable local calendar, then any writable, then any existing
        let canonical = allCalendars.first(where: { $0.source.sourceType == .local && calendarWritable($0) })
            ?? allCalendars.first(where: { calendarWritable($0) })
            ?? allCalendars.first

        if let canonical = canonical {
            oayaoCalendars = [canonical]
            writableCalendar = calendarWritable(canonical) ? canonical : nil
            if writableCalendar == nil {
                createLocalCalendar(completion: completion)
                return
            }
            syncAllEvents()
            completion(true)
            return
        }

        createLocalCalendar(completion: completion)
    }

    private func createLocalCalendar(completion: @escaping (Bool) -> Void) {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = SettingsStore.calendarName
        calendar.cgColor = UIColor.systemPink.cgColor
        if let source = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = source
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        }

        do {
            try eventStore.saveCalendar(calendar, commit: true)
            oayaoCalendars = [calendar]
            writableCalendar = calendar
            syncAllEvents()
            completion(true)
        } catch {
            print("[Oayao] Failed to create calendar: \(error)")
            completion(false)
        }
    }

    private func calendarWritable(_ calendar: EKCalendar) -> Bool {
        if calendar.allowsContentModifications { return true }
        if let refreshed = eventStore.calendar(withIdentifier: calendar.calendarIdentifier) {
            return refreshed.allowsContentModifications
        }
        return false
    }

    // MARK: - Sync

    private func syncAllEvents() {
        syncDaysCounter()
        guard !oayaoCalendars.isEmpty else { return }
        let today = Date()
        let startOfDay = Calendar.current.startOfDay(for: today)
        guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        var activeIds: [String] = []
        for calendar in oayaoCalendars {
            let predicate = eventStore.predicateForEvents(
                withStart: startOfDay, end: endOfDay, calendars: [calendar]
            )
            let events = eventStore.events(matching: predicate)
            for event in events {
                activeIds.append(event.eventIdentifier)
                oayao_spawn_heart(event.eventIdentifier)
            }
        }

        let joined = activeIds.joined(separator: "\n")
        oayao_sync_hearts(joined)
    }

    // MARK: - Days Counter

    /// The date the day counter currently starts from: the stored setting,
    /// or the built-in default when never set.
    func counterStartDate() -> Date {
        Date(timeIntervalSince1970: SettingsStore.counterStartMs / 1000)
    }

    /// Persist the day counter start date and push it to the renderer.
    func setCounterStart(date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        SettingsStore.counterStartMs = startOfDay.timeIntervalSince1970 * 1000
        syncDaysCounter()
    }

    /// Push the configured counter start to the renderer.
    private func syncDaysCounter() {
        oayao_set_days_counter_start_ms(SettingsStore.counterStartMs)
    }

    // MARK: - CRUD

    func addEvent(
        title: String,
        startDate: Date,
        notes: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard hasAccess, let calendar = writableCalendar else {
            completion(false)
            return
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(3600)
        event.calendar = calendar
        if let notes = notes, !notes.isEmpty {
            event.notes = notes
        }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            oayao_spawn_heart(event.eventIdentifier)
            completion(true)
        } catch {
            print("[Oayao] Failed to save event: \(error)")
            completion(false)
        }
    }

    func deleteEvent(with identifier: String, completion: @escaping (Bool) -> Void) {
        guard hasAccess,
              let event = eventStore.event(withIdentifier: identifier),
              oayaoCalendars.contains(where: { $0.calendarIdentifier == event.calendar.calendarIdentifier }),
              calendarWritable(event.calendar)
        else {
            completion(false)
            return
        }

        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            oayao_remove_heart(identifier)
            completion(true)
        } catch {
            print("[Oayao] Failed to delete event: \(error)")
            completion(false)
        }
    }

    func updateEvent(
        with identifier: String,
        title: String?,
        startDate: Date?,
        notes: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard hasAccess,
              let event = eventStore.event(withIdentifier: identifier),
              oayaoCalendars.contains(where: { $0.calendarIdentifier == event.calendar.calendarIdentifier }),
              calendarWritable(event.calendar)
        else {
            completion(false)
            return
        }

        if let title = title { event.title = title }
        if let startDate = startDate {
            event.startDate = startDate
            event.endDate = startDate.addingTimeInterval(3600)
        }
        if let notes = notes { event.notes = notes }

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            completion(true)
        } catch {
            print("[Oayao] Failed to update event: \(error)")
            completion(false)
        }
    }

    func event(with identifier: String) -> EKEvent? {
        return eventStore.event(withIdentifier: identifier)
    }

    func shareCalendar(completion: @escaping (URL?) -> Void) {
        guard let calendar = writableCalendar,
              let url = URL(string: "calshow:\(calendar.calendarIdentifier)")
        else {
            completion(nil)
            return
        }
        completion(url)
    }
}
