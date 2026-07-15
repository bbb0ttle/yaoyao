import EventKit
import UIKit

/// Wraps EventKit operations for the oayao calendar.
/// Each calendar event maps to a floating heart in the Metal canvas.
@objc final class CalendarManager: NSObject, @unchecked Sendable {
    static let shared = CalendarManager()

    private let eventStore = EKEventStore()
    private var oayaoCalendar: EKCalendar?
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
                if granted {
                    self?.findOrCreateCalendar(completion: completion)
                } else {
                    completion(false)
                }
            }
        }
    }

    // MARK: - Calendar

    private func findOrCreateCalendar(completion: @escaping (Bool) -> Void) {
        if let existing = eventStore.calendars(for: .event).first(where: { $0.title == "oayao" }) {
            oayaoCalendar = existing
            syncAllEvents()
            completion(true)
            return
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = "oayao"
        calendar.cgColor = UIColor.systemPink.cgColor
        if let source = eventStore.defaultCalendarForNewEvents?.source {
            calendar.source = source
        } else if let localSource = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = localSource
        }

        do {
            try eventStore.saveCalendar(calendar, commit: true)
            oayaoCalendar = calendar
            syncAllEvents()
            completion(true)
        } catch {
            print("[Oayao] Failed to create calendar: \(error)")
            completion(false)
        }
    }

    @objc private func handleEventStoreChanged() {
        guard hasAccess, let calendar = oayaoCalendar else { return }
        if calendarAllowed(calendar) {
            syncAllEvents()
        }
    }

    private func calendarAllowed(_ calendar: EKCalendar) -> Bool {
        if calendar.allowsContentModifications { return true }
        // If we lost write access, try to re-fetch
        if let refreshed = eventStore.calendar(withIdentifier: calendar.calendarIdentifier) {
            oayaoCalendar = refreshed
            return refreshed.allowsContentModifications
        }
        return false
    }

    // MARK: - Sync

    private func syncAllEvents() {
        guard let calendar = oayaoCalendar else { return }
        let today = Date()
        let startOfDay = Calendar.current.startOfDay(for: today)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay, end: endOfDay, calendars: [calendar]
        )
        let events = eventStore.events(matching: predicate)

        for event in events {
            oayao_spawn_heart(event.eventIdentifier)
        }
    }

    // MARK: - CRUD

    func addEvent(
        title: String,
        startDate: Date,
        notes: String?,
        completion: @escaping (Bool) -> Void
    ) {
        guard hasAccess, let calendar = oayaoCalendar else {
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
              let calendar = oayaoCalendar,
              event.calendar.calendarIdentifier == calendar.calendarIdentifier
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

    func event(with identifier: String) -> EKEvent? {
        return eventStore.event(withIdentifier: identifier)
    }

    func shareCalendar(completion: @escaping (URL?) -> Void) {
        // iCloud calendar sharing via system share sheet.
        // For now, open the system Calendar sharing UI.
        guard let calendar = oayaoCalendar,
              let url = URL(string: "calshow:\(calendar.calendarIdentifier)")
        else {
            completion(nil)
            return
        }
        completion(url)
    }
}
