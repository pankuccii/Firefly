import Foundation
public struct ChargingSession: Sendable {
    public let start: Date
    public let end: Date
    public let startPercent: Int
    public let endPercent: Int
    public var gained: Int { endPercent - startPercent }
}
public enum InsightsEngine {
    public static func sessions(_ observations: [Observation], deviceID: String) -> [ChargingSession] {
        let values = observations.filter { $0.deviceID == deviceID }.sorted { $0.timestamp < $1.timestamp }
        var start: Observation?; var previous: Observation?; var result: [ChargingSession] = []
        func finish() {
            if let a = start, let b = previous, b.timestamp > a.timestamp { result.append(ChargingSession(start: a.timestamp, end: b.timestamp, startPercent: a.percent, endPercent: b.percent)) }
            start = nil
        }
        for value in values {
            if let old = previous, value.timestamp.timeIntervalSince(old.timestamp) > 300 { finish() }
            if value.charging == true { if start == nil { start = value } }
            else { finish() }
            previous = value
        }
        finish(); return result
    }
    // Only a recent uninterrupted charging window can support a rough linear estimate.
    public static func minutesToFull(_ observations: [Observation], deviceID: String, now: Date = Date()) -> Int? {
        let values = observations.filter { $0.deviceID == deviceID && now.timeIntervalSince($0.timestamp) <= 1800 }.sorted { $0.timestamp < $1.timestamp }
        guard values.count >= 4, let last = values.last, last.charging == true,
              last.percent < 95, last.freshness(now: now, connected: true) == .fresh else { return nil }
        var window = [last]
        for value in values.dropLast().reversed() {
            guard let next = window.last, value.charging == true,
                  next.timestamp.timeIntervalSince(value.timestamp) <= 300,
                  next.percent >= value.percent else { break }
            window.append(value)
        }
        guard window.count >= 4, let first = window.last else { return nil }
        let minutes = last.timestamp.timeIntervalSince(first.timestamp) / 60
        let gain = last.percent - first.percent
        guard minutes >= 5, gain >= 3 else { return nil }
        let estimate = Double(100 - last.percent) * minutes / Double(gain)
        guard estimate > 0 && estimate < 600 else { return nil }
        return Int(estimate.rounded(.up))
    }
}
