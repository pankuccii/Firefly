import Foundation
// Least-privilege snapshot: no device identifier or pairing information leaves the app.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let percent: Int
    public let timestamp: Date
    public let connected: Bool
    public let language: String
    public init(name: String, percent: Int, timestamp: Date, connected: Bool, language: String) {
        self.name = name; self.percent = percent; self.timestamp = timestamp; self.connected = connected; self.language = language
    }
    public func live(at date: Date) -> Bool {
        let age = date.timeIntervalSince(timestamp)
        return connected && (0...100).contains(percent) && age >= -30 && age < 300
    }
    public static func location() -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FireflySharedGroup") as? String,
              !group.isEmpty, !group.hasPrefix("."), !group.contains("$") else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("battery-widget-v1.json")
    }
    public static func load() -> WidgetSnapshot? {
        guard let url = location(), let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data), (0...100).contains(value.percent) else { return nil }
        return value
    }
}
