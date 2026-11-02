import Foundation
import CoreFoundation

public enum Transport: String, Codable, CaseIterable, Sendable { case usb = "USB", wifi = "Wi-Fi" }
public enum Freshness: String, Sendable { case fresh, recent, stale, disconnected, unavailable }
public struct Observation: Codable, Equatable, Sendable, Identifiable {
    public var id: Date { timestamp }
    public let deviceID: String
    public let name: String
    public let percent: Int
    public let charging: Bool?
    public let timestamp: Date
    public let transport: Transport
    public let acquisitionResult: String
    public init(deviceID: String, name: String, percent: Int, charging: Bool?, timestamp: Date = Date(), transport: Transport) throws {
        guard !deviceID.isEmpty, (0...100).contains(percent), timestamp.timeIntervalSinceNow <= 30 else { throw AcquisitionError.invalidPayload }
        self.deviceID = deviceID; self.name = name; self.percent = percent; self.charging = charging
        self.timestamp = timestamp; self.transport = transport; self.acquisitionResult = "success"
    }
    public func freshness(now: Date = Date(), connected: Bool) -> Freshness {
        let age = now.timeIntervalSince(timestamp)
        guard age >= -30 else { return .unavailable }
        if !connected { return .disconnected }
        if age <= 90 { return .fresh }
        return age <= 300 ? .recent : .stale
    }
    public static func parse(_ data: Data, deviceID: String, name: String, transport: Transport) throws -> Observation {
        guard let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let n = dict["BatteryCurrentCapacity"] as? NSNumber,
              CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.rounded() == n.doubleValue,
              (0...100).contains(n.doubleValue) else { throw AcquisitionError.invalidPayload }
        let charging: Bool?
        if let b = dict["BatteryIsCharging"] as? NSNumber, CFGetTypeID(b) == CFBooleanGetTypeID() { charging = b.boolValue } else { charging = nil }
        return try Observation(deviceID: deviceID, name: name, percent: n.intValue, charging: charging, transport: transport)
    }
}
public enum AcquisitionError: String, Error, Sendable {
    case dependencyMissing, unsupportedTool, noDevice, queryFailed, invalidPayload, timeout, cancelled, outputTooLarge
}
public enum ConnectionState: Equatable, Sendable {
    case idle, discovering, connected(Transport), retrying(Int, AcquisitionError), paused, waiting(AcquisitionError), failed(AcquisitionError)
    public var connected: Bool { if case .connected = self { return true }; return false }
}
public struct RetryPolicy: Sendable {
    public init() {}
    public func delay(failures: Int) -> TimeInterval { min(300, 5 * pow(2, Double(min(max(failures - 1, 0), 6)))) }
    public func mayRetry(failures: Int) -> Bool { failures < 6 }
}
public struct AlertEngine: Codable, Sendable {
    private var previous: Observation?
    private var last: [String: Date] = [:]
    public init() {}
    public mutating func evaluate(_ value: Observation, lows: [Int], chargeTarget: Int?, now: Date = Date()) -> [String] {
        guard value.freshness(now: now, connected: true) == .fresh else { return [] }
        defer { previous = value }
        guard let old = previous, old.deviceID == value.deviceID, value.timestamp > old.timestamp,
              value.timestamp.timeIntervalSince(old.timestamp) <= 300 else { return [] }
        var keys = Array(Set(lows)).filter { old.percent >= $0 && value.percent < $0 }.sorted().prefix(1).map { "low:\($0)" }
        if let target = chargeTarget, value.charging == true, old.percent < target, value.percent >= target { keys.append("charge:\(target)") }
        return keys.filter { key in
            let compound = value.deviceID + key
            guard now.timeIntervalSince(last[compound] ?? .distantPast) >= 1800 else { return false }
            last[compound] = now; return true
        }
    }
}
public struct ScheduleRule: Codable, Sendable {
    public var enabled = false
    public var weekdays = [2, 3, 4, 5, 6]
    public var hour = 8
    public var minute = 30
    public var threshold = 40
    public init() {}
    public func due(at date: Date, calendar: Calendar = .current) -> Bool {
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        return enabled && weekdays.contains(c.weekday ?? 0) && c.hour == hour && c.minute == minute
    }
}
public struct History: Codable, Sendable {
    public private(set) var values: [Observation] = []
    public init() {}
    public mutating func append(_ value: Observation, now: Date = Date()) {
        guard value.timestamp <= now.addingTimeInterval(30), (0...100).contains(value.percent),
              !values.contains(where: { $0.deviceID == value.deviceID && $0.timestamp == value.timestamp }) else { return }
        values.append(value)
        values = Array(values.filter { now.timeIntervalSince($0.timestamp) <= 7 * 86400 }.sorted { $0.timestamp < $1.timestamp }.suffix(12000))
    }
    public func validated(now: Date = Date()) -> History {
        var seen = [String: Set<Date>]()
        var result = History()
        result.values = Array(values.filter { value in
            let age = now.timeIntervalSince(value.timestamp)
            return !value.deviceID.isEmpty && value.acquisitionResult == "success" && (0...100).contains(value.percent) && age >= -30 && age <= 604800 && seen[value.deviceID, default: []].insert(value.timestamp).inserted
        }.sorted { $0.timestamp < $1.timestamp }.suffix(12000))
        return result
    }
    public func csv(deviceID: String) -> String {
        let formatter = ISO8601DateFormatter()
        return "timestamp,percent,charging,transport\n" + values.filter { $0.deviceID == deviceID }.map {
            "\(formatter.string(from: $0.timestamp)),\($0.percent),\($0.charging.map(String.init) ?? ""),\($0.transport.rawValue)"
        }.joined(separator: "\n")
    }
}

// Shortcuts writes two lines: a whole percentage and the phone's ISO 8601 date.
public struct RemoteBatteryReading: Equatable, Sendable {
    public let percent: Int
    public let date: Date

    public static func parse(_ data: Data, now: Date = Date()) throws -> Self {
        guard data.count <= 256, let text = String(data: data, encoding: .utf8) else { throw AcquisitionError.invalidPayload }
        let lines = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.count == 2, let percent = Int(lines[0]), (0...100).contains(percent) else { throw AcquisitionError.invalidPayload }
        let iso = ISO8601DateFormatter()
        var date = iso.date(from: lines[1])
        if date == nil {
            iso.formatOptions.insert(.withFractionalSeconds)
            date = iso.date(from: lines[1])
        }
        guard let date, date <= now.addingTimeInterval(30) else { throw AcquisitionError.invalidPayload }
        return Self(percent: percent, date: date)
    }
    public func recent(at now: Date) -> Bool { (-30...300).contains(now.timeIntervalSince(date)) }
}
