import Foundation

/// Generates, persists, and schedules the daily meteor-shower forecast.
/// Ported from `web/forcast/index.ts`.
final class ForecastStore: ObservableObject {
    @Published var events: [ForecastEvent] = []

    private var updateTimer: Timer?
    private let count: Int

    init(count: Int = 3) {
        self.count = count
        ensureForecastData()
        startAutoUpdate()
    }

    deinit {
        updateTimer?.invalidate()
        events.forEach { $0.cancel() }
    }

    private func ensureForecastData() {
        let defaults = UserDefaults.standard
        let key = storageKey()

        var loaded: [ForecastEvent]?
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ForecastEventData].self, from: data) {
            let fixed = validateAndFix(decoded, maxEvents: count)
            loaded = fixed.map { eventData in
                ForecastEvent(dateTime: eventData.dateTime, durationMs: eventData.durationMs)
            }
        }

        if let loaded = loaded, !loaded.isEmpty {
            events = loaded
        } else {
            events = generateForecastData(count: count).map { eventData in
                ForecastEvent(dateTime: eventData.dateTime, durationMs: eventData.durationMs)
            }
            save()
        }

        for event in events {
            event.onFire = { [weak self] in
                self?.triggerMeteorShower()
            }
            event.schedule()
        }
    }

    private func triggerMeteorShower() {
        let bridge = ZCanvasBridge.shared
        let x = CGFloat(bridge.width) / 3.0
        let y = CGFloat(bridge.height)
        bridge.triggerMeteorShower(at: CGPoint(x: x, y: y))
    }

    private func startAutoUpdate() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.events.forEach { $0.updateStatus() }
            self?.objectWillChange.send()
        }
    }

    private func save() {
        let data = events.map { ForecastEventData(dateTime: $0.dateTime, durationMs: $0.durationMs) }
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: storageKey())
        }
    }

    // MARK: - Forecast generation

    private func generateForecastData(count: Int) -> [ForecastEventData] {
        var result: [ForecastEventData] = []
        let now = Date()
        let endOfToday = endOfTodayShanghai()
        var lastEnd: Date? = nil

        for _ in 0..<count {
            let durationMs = TimeInterval(randomInt(min: 60_000, max: 1_800_000)) / 1000.0

            var minStart = now
            if let lastEnd = lastEnd {
                let gapMs = TimeInterval(randomInt(min: 60_000, max: 300_000)) / 1000.0
                minStart = lastEnd.addingTimeInterval(gapMs)
            }

            guard minStart.addingTimeInterval(durationMs) <= endOfToday else {
                break
            }

            guard let start = randomFutureTimeInToday(minStart: minStart, endOfToday: endOfToday) else {
                break
            }

            result.append(ForecastEventData(dateTime: start, durationMs: durationMs))
            lastEnd = start.addingTimeInterval(durationMs)
        }

        return result.sorted { $0.dateTime < $1.dateTime }
    }

    private func randomFutureTimeInToday(minStart: Date, endOfToday: Date) -> Date? {
        let minTime = max(minStart, Date())
        guard minTime < endOfToday else {
            return endOfToday
        }
        let randomInterval = TimeInterval.random(in: 0...(endOfToday.timeIntervalSince(minTime)))
        return minTime.addingTimeInterval(randomInterval)
    }

    private func validateAndFix(_ data: [ForecastEventData], maxEvents: Int) -> [ForecastEventData] {
        let sorted = data.sorted { $0.dateTime < $1.dateTime }
        var result: [ForecastEventData] = []
        var lastEnd: Date? = nil
        let endOfToday = endOfTodayShanghai()

        for item in sorted {
            let start = item.dateTime
            let end = start.addingTimeInterval(item.durationMs)

            var current = item
            if let lastEnd = lastEnd, start < lastEnd {
                let gapMs = TimeInterval(randomInt(min: 60_000, max: 120_000)) / 1000.0
                let newStart = lastEnd.addingTimeInterval(gapMs)
                guard newStart.addingTimeInterval(item.durationMs) <= endOfToday else {
                    continue
                }
                current = ForecastEventData(dateTime: newStart, durationMs: item.durationMs)
            }

            result.append(current)
            lastEnd = current.dateTime.addingTimeInterval(current.durationMs)

            if result.count >= maxEvents {
                break
            }
        }

        return result
    }

    // MARK: - Date helpers

    private func storageKey() -> String {
        let components = shanghaiDateComponents(from: Date())
        let year = components.year ?? 0
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        return "meteor_shower_forcast_\(year)\(month)\(day)"
    }

    private func endOfTodayShanghai() -> Date {
        let calendar = shanghaiCalendar()
        let components = shanghaiDateComponents(from: Date())
        var endComponents = DateComponents()
        endComponents.year = components.year
        endComponents.month = components.month
        endComponents.day = components.day
        endComponents.hour = 23
        endComponents.minute = 59
        endComponents.second = 59
        endComponents.nanosecond = 999_000_000
        return calendar.date(from: endComponents) ?? Date()
    }

    private func shanghaiDateComponents(from date: Date) -> DateComponents {
        shanghaiCalendar().dateComponents([.year, .month, .day], from: date)
    }

    private func shanghaiCalendar() -> Calendar {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func randomInt(min: Int, max: Int) -> Int {
        Int.random(in: min...max)
    }
}

// MARK: - Persistence model

struct ForecastEventData: Codable {
    let dateTime: Date
    let durationMs: TimeInterval
}
