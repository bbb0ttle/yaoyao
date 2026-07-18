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

    /// EventKit predicate queries run off the main thread; renderer calls
    /// (oayao_*) are always applied back on the main queue.
    private let workQueue = DispatchQueue(label: "com.bbking.oayao.calendar-sync", qos: .userInitiated)
    private var pendingSync: DispatchWorkItem?

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
                // Show the last known start date immediately; the authoritative
                // value syncs from the calendar once access resolves.
                oayao_set_days_counter_start_ms(SettingsStore.counterStartMs)
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

    /// EKEventStoreChanged fires on an arbitrary thread and bursts during
    /// iCloud sync; coalesce onto the main queue with a short debounce.
    /// This also keeps renderer C API calls on the render (main) thread.
    @objc private func handleEventStoreChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.hasAccess else { return }
            self.pendingSync?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.resolveCanonicalCalendar { _ in }
            }
            self.pendingSync = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
        }
    }

    private func resolveCanonicalCalendar(completion: @escaping (Bool) -> Void) {
        let allCalendars = eventStore.calendars(for: .event).filter { $0.title == SettingsStore.calendarName }

        // Prefer a writable iCloud calendar (required for sharing), then any
        // writable, then any existing — a read-only shared calendar still
        // provides hearts, so it beats creating an empty personal one.
        let canonical = allCalendars.first(where: { isICloud($0) && calendarWritable($0) })
            ?? allCalendars.first(where: { calendarWritable($0) })
            ?? allCalendars.first

        guard let canonical = canonical else {
            createCalendar(completion: completion)
            return
        }

        oayaoCalendars = [canonical]
        writableCalendar = calendarWritable(canonical) ? canonical : nil
        syncAllEvents()
        completion(true)
    }

    private func isICloud(_ calendar: EKCalendar) -> Bool {
        calendar.source.sourceType == .calDAV && calendar.source.title == "iCloud"
    }

    private func createCalendar(completion: @escaping (Bool) -> Void) {
        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = SettingsStore.calendarName
        calendar.cgColor = UIColor.systemPink.cgColor
        // iCloud first: local calendars can't be shared with a partner.
        if let iCloudSource = eventStore.sources.first(where: {
            $0.sourceType == .calDAV && $0.title == "iCloud"
        }) {
            calendar.source = iCloudSource
        } else if let source = eventStore.defaultCalendarForNewEvents?.source {
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

    /// Query events on the work queue, then apply to the renderer on main.
    private func syncAllEvents() {
        let calendars = oayaoCalendars
        let writable = writableCalendar
        workQueue.async { [weak self] in
            guard let self = self else { return }

            var activeIds: [String] = []
            if !calendars.isEmpty {
                let today = Date()
                let startOfDay = Calendar.current.startOfDay(for: today)
                guard let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) else { return }
                for calendar in calendars {
                    let predicate = self.eventStore.predicateForEvents(
                        withStart: startOfDay, end: endOfDay, calendars: [calendar]
                    )
                    for event in self.eventStore.events(matching: predicate) where !self.isCounterStartEvent(event) {
                        activeIds.append(event.eventIdentifier)
                    }
                }
            }

            let counterStartMs = self.queryCounterStartMs(calendars: calendars, writable: writable)
            let joined = activeIds.joined(separator: "\n")

            DispatchQueue.main.async {
                for eventId in activeIds {
                    oayao_spawn_heart(eventId)
                }
                oayao_sync_hearts(joined)
                SettingsStore.counterStartMs = counterStartMs
                oayao_set_days_counter_start_ms(counterStartMs)
            }
        }
    }

    // MARK: - Days Counter

    /// Title of the all-day marker event anchoring the day counter.
    private let counterStartTitle = "开始的地方"

    /// The chosen start date travels in the marker event's notes
    /// ("yyyy-MM-dd"), so the event itself can be re-dated to stay inside
    /// EventKit's search window: predicates spanning more than 4 years are
    /// clamped to their first 4 years, hence the marker is searched in a
    /// recent window and re-copied well before it ages out.
    private let counterStartSearchPastYears = -3
    private let counterStartRefreshAgeYears = -2

    private static let counterStartNotesFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The date the day counter currently starts from: the last value synced
    /// from the marker event, or the built-in default when never set.
    func counterStartDate() -> Date {
        Date(timeIntervalSince1970: SettingsStore.counterStartMs / 1000)
    }

    /// Persist the chosen start date: cache it locally, push it to the
    /// renderer, and record it in the marker event's notes so it syncs to
    /// anyone the calendar is shared with.
    func setCounterStart(date: Date) {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let startMs = startOfDay.timeIntervalSince1970 * 1000
        SettingsStore.counterStartMs = startMs
        oayao_set_days_counter_start_ms(startMs)

        guard hasAccess, let calendar = writableCalendar else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let event = counterStartEvent() ?? EKEvent(eventStore: eventStore)
        event.title = counterStartTitle
        event.calendar = calendar
        event.isAllDay = true
        event.startDate = today
        event.endDate = Calendar.current.date(byAdding: .day, value: 1, to: today)
        event.notes = Self.counterStartNotesFormatter.string(from: startOfDay)

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            print("[Oayao] Failed to save counter start event: \(error)")
        }
    }

    /// Query the marker event off the main thread: read the latest notes
    /// date, re-copy the marker when it nears the searchable window edge.
    /// Falls back to the renderer's built-in default when no marker exists.
    private func queryCounterStartMs(calendars: [EKCalendar], writable: EKCalendar?) -> Double {
        guard !calendars.isEmpty else { return oayao_days_counter_default_start_ms() }
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .year, value: counterStartSearchPastYears, to: now),
              let end = Calendar.current.date(byAdding: .month, value: 1, to: now)
        else { return oayao_days_counter_default_start_ms() }

        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: calendars)
        guard let marker = eventStore.events(matching: predicate)
            .filter({ isCounterStartEvent($0) })
            .max(by: { $0.startDate < $1.startDate }),
            let date = Self.counterStartNotesFormatter.date(from: marker.notes ?? "")
        else { return oayao_days_counter_default_start_ms() }

        refreshCounterStartEventIfNeeded(marker, writable: writable)
        return date.timeIntervalSince1970 * 1000
    }

    /// The most recently dated marker event within the searchable window.
    private func counterStartEvent() -> EKEvent? {
        guard !oayaoCalendars.isEmpty else { return nil }
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .year, value: counterStartSearchPastYears, to: now),
              let end = Calendar.current.date(byAdding: .month, value: 1, to: now)
        else { return nil }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: oayaoCalendars)
        return eventStore.events(matching: predicate)
            .filter { isCounterStartEvent($0) }
            .max { $0.startDate < $1.startDate }
    }

    /// Re-copy the marker at today's date when the latest copy is close to
    /// aging out of the searchable window, keeping it readable forever.
    private func refreshCounterStartEventIfNeeded(_ event: EKEvent, writable: EKCalendar?) {
        guard let calendar = writable,
              let threshold = Calendar.current.date(byAdding: .year, value: counterStartRefreshAgeYears, to: Date()),
              event.startDate < threshold
        else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let copy = EKEvent(eventStore: eventStore)
        copy.title = event.title
        copy.notes = event.notes
        copy.calendar = calendar
        copy.isAllDay = true
        copy.startDate = today
        copy.endDate = Calendar.current.date(byAdding: .day, value: 1, to: today)

        do {
            try eventStore.save(copy, span: .thisEvent, commit: true)
        } catch {
            print("[Oayao] Failed to refresh counter start event: \(error)")
        }
    }

    private func isCounterStartEvent(_ event: EKEvent) -> Bool {
        guard let title = event.title else { return false }
        return title.trimmingCharacters(in: .whitespaces)
            .caseInsensitiveCompare(counterStartTitle) == .orderedSame
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

    /// Whether the canonical calendar can be shared with others
    /// (iCloud/CalDAV-backed; local or subscribed calendars cannot).
    func currentCalendarIsShareable() -> Bool {
        guard let calendar = oayaoCalendars.first else { return false }
        return calendar.source.sourceType == .calDAV
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
