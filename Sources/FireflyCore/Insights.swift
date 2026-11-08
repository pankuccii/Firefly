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
    public struct Estimate: Sendable {
        public let minutes: Int
        public let fromHistory: Bool
    }

    public static func minutesToFull(_ observations: [Observation], deviceID: String, now: Date = Date()) -> Int? {
        guard let latest = observations.filter({ $0.deviceID == deviceID }).max(by: { $0.timestamp < $1.timestamp }) else { return nil }
        return completionEstimate(observations, current: latest, now: now)?.minutes
    }

    public static func completionEstimate(_ observations: [Observation], current: Observation, now: Date = Date()) -> Estimate? {
        guard current.charging == true, current.percent < 100,
              current.freshness(now: now, connected: true) == .fresh else { return nil }
        let earlier = observations.filter {
            $0.deviceID == current.deviceID && $0.timestamp < current.timestamp &&
            current.timestamp.timeIntervalSince($0.timestamp) <= 7 * 86400
        }.sorted { $0.timestamp < $1.timestamp }

        // Use a contiguous, rising window. A disconnect, fall in level or long gap ends it.
        var first = current
        var count = 1
        for sample in earlier.reversed() {
            guard sample.charging == true, sample.percent <= first.percent,
                  first.timestamp.timeIntervalSince(sample.timestamp) <= 300,
                  current.timestamp.timeIntervalSince(sample.timestamp) <= 1800 else { break }
            first = sample
            count += 1
        }
        func estimate(_ minutesPerPoint: Double, historical: Bool) -> Estimate? {
            let minutes = minutesPerPoint * Double(100 - current.percent)
            guard minutes > 0, minutes < 600 else { return nil }
            return Estimate(minutes: Int(minutes.rounded(.up)), fromHistory: historical)
        }
        let duration = current.timestamp.timeIntervalSince(first.timestamp) / 60
        let gain = current.percent - first.percent
        if count >= 3, duration >= 1, gain >= 2 {
            return estimate(duration / Double(gain), historical: false)
        }
        // One rate per completed observed interval; exclude the immature current interval.
        // Near full, only reuse intervals actually observed in the slower, near-full region.
        let prior = sessions(earlier, deviceID: current.deviceID).filter {
            $0.end < first.timestamp && $0.gained >= 3 && $0.end.timeIntervalSince($0.start) >= 300 &&
            (current.percent < 80 || $0.startPercent >= 80)
        }
        let rates = prior.map { $0.end.timeIntervalSince($0.start) / 60 / Double($0.gained) }.sorted()
        guard !rates.isEmpty else { return nil }
        let middle = rates.count / 2
        let median = rates.count.isMultiple(of: 2) ? (rates[middle - 1] + rates[middle]) / 2 : rates[middle]
        return estimate(median, historical: true)
    }
}
