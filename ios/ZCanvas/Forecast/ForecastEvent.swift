import Foundation
import Combine

/// A single scheduled meteor-shower event.
/// Mirrors the behavior of `web/forcast/MeteoreShowerEvent.ts`:
/// schedules a start time, fires repeatedly while active, and stops at the end time.
final class ForecastEvent: ObservableObject, Identifiable {
    let id: UUID
    let dateTime: Date
    let durationMs: TimeInterval

    @Published var statusText: String = ""
    @Published var isActive: Bool = false
    @Published var isEnded: Bool = false

    var onFire: (() -> Void)?

    private var startTimer: Timer?
    private var fireTimer: Timer?
    private var endTimer: Timer?
    private var isScheduled = false

    var endDate: Date {
        dateTime.addingTimeInterval(durationMs)
    }

    init(id: UUID = UUID(), dateTime: Date, durationMs: TimeInterval, onFire: (() -> Void)? = nil) {
        self.id = id
        self.dateTime = dateTime
        self.durationMs = durationMs
        self.onFire = onFire
    }

    deinit {
        cancel()
    }

    /// Schedule the event. Safe to call multiple times; later calls are ignored.
    func schedule() {
        guard !isScheduled else { return }
        isScheduled = true
        updateStatus()

        let now = Date()
        if now < dateTime {
            startTimer = Timer.scheduledTimer(withTimeInterval: dateTime.timeIntervalSince(now), repeats: false) { [weak self] _ in
                self?.start()
            }
        } else if now < endDate {
            start()
        } else {
            isEnded = true
            updateStatus()
        }
    }

    private func start() {
        let now = Date()
        guard now >= dateTime, now < endDate else {
            stop()
            return
        }
        isActive = true
        fire()
        scheduleNextFire()

        endTimer = Timer.scheduledTimer(withTimeInterval: endDate.timeIntervalSince(now), repeats: false) { [weak self] _ in
            self?.stop()
        }
    }

    private func scheduleNextFire() {
        guard isActive else { return }
        let now = Date()
        let remaining = endDate.timeIntervalSince(now)
        guard remaining > 0 else {
            stop()
            return
        }
        let maxWait = min(2.0, remaining)
        let wait = Double.random(in: 0...maxWait)
        fireTimer = Timer.scheduledTimer(withTimeInterval: wait, repeats: false) { [weak self] _ in
            self?.fire()
            self?.scheduleNextFire()
        }
    }

    private func fire() {
        onFire?()
    }

    func updateStatus() {
        let now = Date()
        if now < dateTime {
            statusText = Self.formatTimeRemaining(dateTime.timeIntervalSince(now))
        } else if now < endDate {
            statusText = Self.formatTimeRemaining(endDate.timeIntervalSince(now))
        } else {
            statusText = ""
            isEnded = true
        }
    }

    func cancel() {
        startTimer?.invalidate()
        fireTimer?.invalidate()
        endTimer?.invalidate()
        startTimer = nil
        fireTimer = nil
        endTimer = nil
        isActive = false
    }

    private func stop() {
        cancel()
        isEnded = true
        updateStatus()
    }

    static func formatTimeRemaining(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 {
            return String(format: "00:00:%02d", seconds)
        }
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes < 60 {
            return String(format: "00:%02d:%02d", minutes, secs)
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return String(format: "%02d:%02d:%02d", hours, mins, secs)
    }
}
