import SwiftUI

/// SwiftUI list that mirrors the web forecast panel in `web/forcast/ForcastUI.ts`.
struct ForecastView: View {
    @StateObject private var store = ForecastStore(count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(store.events) { event in
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(event.isActive ? .yellow : .primary)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatTime(event.dateTime))
                            .font(.system(size: 14, weight: .medium))
                        if !event.statusText.isEmpty {
                            Text(event.statusText)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(statusColor(for: event))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(event.isActive ? Color.yellow.opacity(0.12) : Color.clear)
            }

            if store.events.isEmpty {
                Text("No meteor showers forecasted today")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(16)
            }
        }
        .background(Color(hex: 0xA9E5D6).opacity(0.35))
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return formatter.string(from: date)
    }

    private func statusColor(for event: ForecastEvent) -> Color {
        if event.isActive { return .orange }
        if event.isEnded { return .gray }
        return .primary
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, opacity: alpha)
    }
}
